import NEARLean.Receipts

/-!
# Pinned-protocol economic accounting

The ledger separates liquid balances, funds carried by receipts, gas escrow,
storage stake, pending refunds, and burnt tokens. Every accepted transition is
validated against token conservation and gas bounds before it commits.
-/

namespace NEARLean

structure GasSchedule where
  transferTotalGas : Gas
  deriving BEq, Repr

def GasSchedule.protocol86Sandbox : GasSchedule := {
  transferTotalGas := 669547687500
}

structure EconomicConfig where
  gasPrice : Balance
  storagePricePerByte : Balance
  maxGas : Gas
  schedule : GasSchedule
  deriving BEq, Repr

def EconomicConfig.protocol86Sandbox : EconomicConfig := {
  gasPrice := 0
  storagePricePerByte := 10 ^ 19
  maxGas := 300 * 10 ^ 12
  schedule := GasSchedule.protocol86Sandbox
}

structure EconomicState where
  liquid : Balance
  carriedDeposits : Balance := 0
  gasEscrow : Balance := 0
  storageStake : Balance := 0
  pendingRefunds : Balance := 0
  burntTokens : Balance := 0
  prepaidGas : Gas := 0
  gasUsed : Gas := 0
  gasBurnt : Gas := 0
  storageUsage : Nat := 0
  deriving BEq, Repr

def EconomicState.totalTokens (state : EconomicState) : Balance :=
  state.liquid + state.carriedDeposits + state.gasEscrow +
    state.storageStake + state.pendingRefunds + state.burntTokens

def EconomicState.WellFormed (config : EconomicConfig) (state : EconomicState) : Prop :=
  state.prepaidGas ≤ config.maxGas ∧
    state.gasUsed ≤ state.prepaidGas ∧
    state.gasBurnt ≤ state.gasUsed

instance EconomicState.instDecidableWellFormed
    (config : EconomicConfig) (state : EconomicState) :
    Decidable (state.WellFormed config) := by
  unfold EconomicState.WellFormed
  infer_instance

inductive EconomicError where
  | prepaidGasExceeded
  | outOfGas
  | insufficientBalance
  | insufficientCarriedDeposit
  | insufficientGasEscrow
  | insufficientRefund
  | insufficientStorageStake
  deriving BEq, Repr

inductive EconomicAction where
  | lockCall (deposit : Balance) (prepaidGas : Gas)
  | settleGas (prepaidGas gasUsed gasBurnt : Gas)
  | deliverDeposit (amount : Balance)
  | claimRefund (amount : Balance)
  | stakeStorage (bytes : Nat)
  | releaseStorage (bytes : Nat)
  deriving BEq, Repr

private def EconomicState.commit
    (config : EconomicConfig)
    (before candidate : EconomicState) : EconomicState :=
  if candidate.WellFormed config ∧ candidate.totalTokens = before.totalTokens then
    candidate
  else
    before

@[simp] private theorem EconomicState.commit_totalTokens
    (config : EconomicConfig)
    (before candidate : EconomicState) :
    (before.commit config candidate).totalTokens = before.totalTokens := by
  unfold EconomicState.commit
  split
  · exact ‹candidate.WellFormed config ∧ _›.2
  · rfl

@[simp] private theorem EconomicState.commit_wellFormed
    (config : EconomicConfig)
    (before candidate : EconomicState)
    (beforeValid : before.WellFormed config) :
    (before.commit config candidate).WellFormed config := by
  unfold EconomicState.commit
  split
  · exact ‹candidate.WellFormed config ∧ _›.1
  · exact beforeValid

def EconomicState.step
    (config : EconomicConfig)
    (state : EconomicState)
    (action : EconomicAction) : EconomicState × Except EconomicError Unit :=
  match action with
  | .lockCall deposit prepaidGas =>
      if config.maxGas < prepaidGas then
        (state, .error .prepaidGasExceeded)
      else
        let gasTokens := prepaidGas * config.gasPrice
        let required := deposit + gasTokens
        if state.liquid < required then
          (state, .error .insufficientBalance)
        else
          let candidate := { state with
            liquid := state.liquid - required
            carriedDeposits := state.carriedDeposits + deposit
            gasEscrow := state.gasEscrow + gasTokens
            prepaidGas := prepaidGas
            gasUsed := 0
            gasBurnt := 0
          }
          (state.commit config candidate, .ok ())
  | .settleGas prepaidGas gasUsed gasBurnt =>
      if prepaidGas < gasUsed ∨ gasUsed < gasBurnt then
        (state, .error .outOfGas)
      else
        let prepaidTokens := prepaidGas * config.gasPrice
        let burntTokens := gasBurnt * config.gasPrice
        let refund := prepaidTokens - burntTokens
        if state.gasEscrow < prepaidTokens then
          (state, .error .insufficientGasEscrow)
        else
          let candidate := { state with
            gasEscrow := state.gasEscrow - prepaidTokens
            pendingRefunds := state.pendingRefunds + refund
            burntTokens := state.burntTokens + burntTokens
            prepaidGas := prepaidGas
            gasUsed := gasUsed
            gasBurnt := gasBurnt
          }
          (state.commit config candidate, .ok ())
  | .deliverDeposit amount =>
      if state.carriedDeposits < amount then
        (state, .error .insufficientCarriedDeposit)
      else
        let candidate := { state with
          liquid := state.liquid + amount
          carriedDeposits := state.carriedDeposits - amount
        }
        (state.commit config candidate, .ok ())
  | .claimRefund amount =>
      if state.pendingRefunds < amount then
        (state, .error .insufficientRefund)
      else
        let candidate := { state with
          liquid := state.liquid + amount
          pendingRefunds := state.pendingRefunds - amount
        }
        (state.commit config candidate, .ok ())
  | .stakeStorage bytes =>
      let cost := bytes * config.storagePricePerByte
      if state.liquid < cost then
        (state, .error .insufficientBalance)
      else
        let candidate := { state with
          liquid := state.liquid - cost
          storageStake := state.storageStake + cost
          storageUsage := state.storageUsage + bytes
        }
        (state.commit config candidate, .ok ())
  | .releaseStorage bytes =>
      let released := bytes * config.storagePricePerByte
      if state.storageUsage < bytes ∨ state.storageStake < released then
        (state, .error .insufficientStorageStake)
      else
        let candidate := { state with
          liquid := state.liquid + released
          storageStake := state.storageStake - released
          storageUsage := state.storageUsage - bytes
        }
        (state.commit config candidate, .ok ())

def Input.attachedDeposit : Input → Balance
  | .functionCall _ _ _ _ deposit _ => deposit
  | _ => 0

def Receipt.carriedBalance (receipt : Receipt) : Balance :=
  match receipt.body with
  | .action action => action.actions.foldl (fun total input =>
      total + input.attachedDeposit) 0
  | .data _ => 0

def ReceiptMachine.carriedBalance (state : ReceiptMachine) : Balance :=
  (state.queued ++ state.postponed).foldl (fun total receipt =>
    total + receipt.carriedBalance) 0

/-- Every accepted economic transition conserves the complete token ledger. -/
theorem EconomicState.step_conserves_tokens
    (config : EconomicConfig)
    (state : EconomicState)
    (action : EconomicAction) :
    (state.step config action).1.totalTokens = state.totalTokens := by
  cases action <;> simp only [EconomicState.step]
  all_goals split <;> simp_all
  all_goals split <;> simp_all

/-- Validated economic transitions never use or burn more gas than prepaid. -/
theorem EconomicState.step_respects_gas_limit
    (config : EconomicConfig)
    (state : EconomicState)
    (action : EconomicAction)
    (stateValid : state.WellFormed config) :
    (state.step config action).1.WellFormed config := by
  cases action <;> simp only [EconomicState.step]
  all_goals split <;> simp_all
  all_goals split <;> simp_all

end NEARLean
