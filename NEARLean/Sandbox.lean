import NEARLean.AbstractKernel

/-!
# Basic sandbox API

This module exposes the Milestone 2 kernel through a small Workspaces-style API
and provides the temporary native counter and escrow backend.
-/

namespace NEARLean

structure NearChain where
  config : RuntimeConfig
  state : WorldState
  deriving BEq, Repr

/-- Initialize a chain only when the supplied genesis accounts satisfy all invariants. -/
def NearChain.init
    (config : RuntimeConfig)
    (genesisAccounts : List (AccountId × Account)) : Except RuntimeError NearChain :=
  let state := { WorldState.initial config with accounts := genesisAccounts }
  if state.WellFormed config then
    .ok { config := config, state := state }
  else
    .error .invalidInitialState

def NearChain.initEmpty (config : RuntimeConfig) : NearChain :=
  { config := config, state := WorldState.initial config }

def NearChain.apply (chain : NearChain) (input : Input) : NearChain × Except RuntimeError Output :=
  let transitioned := step chain.config chain.state input
  ({ chain with state := transitioned.1 }, transitioned.2)

def NearChain.createAccount
    (chain : NearChain)
    (creator accountId : AccountId)
    (initialBalance : Balance) : NearChain × Except RuntimeError Output :=
  chain.apply (.createAccount creator accountId initialBalance)

def NearChain.transfer
    (chain : NearChain)
    (sender receiver : AccountId)
    (amount : Balance) : NearChain × Except RuntimeError Output :=
  chain.apply (.transfer sender receiver amount)

def NearChain.deploy
    (chain : NearChain)
    (deployer accountId : AccountId)
    (contractId : ContractId) : NearChain × Except RuntimeError Output :=
  chain.apply (.deployContract deployer accountId contractId)

def NearChain.call
    (chain : NearChain)
    (caller receiver : AccountId)
    (methodName : StorageKey)
    (arguments : StorageValue := [])
    (attachedDeposit : Balance := 0)
    (prepaidGas : Gas := 1) : NearChain × Except RuntimeError Output :=
  chain.apply (.functionCall caller receiver methodName arguments attachedDeposit prepaidGas)

def viewNative
    (state : WorldState)
    (receiver : AccountId)
    (methodName : StorageKey) : Except RuntimeError Output := do
  let account ← Option.orError (.accountNotFound receiver) (state.account? receiver)
  let contractId ← Option.orError (.contractNotDeployed receiver) account.contract
  let contract ← Option.orError (.unsupportedContract contractId) (NativeContract.ofId contractId)
  match contract with
  | .counter =>
      if methodName = NativeMethod.get then
        return {
          returnValue := account.storage.lookup NativeStorage.counter |>.getD []
          gasBurnt := 1
        }
      throw (.methodNotFound methodName)
  | .escrow =>
      if methodName = NativeMethod.balance then
        return { gasBurnt := 1, balance := some account.balance }
      throw (.methodNotFound methodName)
  | .asyncContract =>
      if methodName = NativeMethod.echo then
        return { returnValue := [7], gasBurnt := 1 }
      throw (.methodNotFound methodName)
  | .fungibleToken | .nft =>
      throw (.methodNotFound methodName)

/-- Views return an explicit unchanged chain alongside their result. -/
def NearChain.view
    (chain : NearChain)
    (receiver : AccountId)
    (methodName : StorageKey) : NearChain × Except RuntimeError Output :=
  (chain, viewNative chain.state receiver methodName)

def NearChain.account? (chain : NearChain) (accountId : AccountId) : Option Account :=
  chain.state.account? accountId

def NearChain.balance? (chain : NearChain) (accountId : AccountId) : Option Balance :=
  (chain.account? accountId).map (·.balance)

def NearChain.storage? (chain : NearChain) (accountId : AccountId) (key : StorageKey) : Option StorageValue :=
  (chain.account? accountId).bind (·.storage.lookup key)

/-- Successful initialization exposes only a well-formed world. -/
theorem NearChain.init_wellFormed
    (config : RuntimeConfig)
    (genesisAccounts : List (AccountId × Account))
    (chain : NearChain)
    (initialized : NearChain.init config genesisAccounts = .ok chain) :
    chain.state.WellFormed chain.config := by
  unfold NearChain.init at initialized
  dsimp only at initialized
  split at initialized
  · cases initialized
    assumption
  · contradiction

/-- Views are pure by construction, including failed views. -/
theorem NearChain.view_pure :
    ∀ (chain : NearChain) (receiver : AccountId) (methodName : StorageKey),
      (chain.view receiver methodName).1 = chain := by
  intros
  rfl

/-- Failed public API calls retain the exact input chain. -/
theorem NearChain.apply_error_rolls_back
    (chain : NearChain)
    (input : Input)
    (runtimeError : RuntimeError)
    (failed : (chain.apply input).2 = Except.error runtimeError) :
    (chain.apply input).1 = chain := by
  unfold NearChain.apply
  have rollback := step_error_rolls_back (config := chain.config) (state := chain.state)
    (input := input) failed
  cases chain
  simp_all

/-- Public state-changing operations preserve world-state well-formedness. -/
theorem NearChain.apply_preserves_wellFormed
    (chain : NearChain)
    (input : Input)
    (stateValid : chain.state.WellFormed chain.config) :
    (chain.apply input).1.state.WellFormed (chain.apply input).1.config := by
  exact step_preserves_wellFormed stateValid

def counterExample : Except RuntimeError StorageValue := do
  let config := RuntimeConfig.default
  let owner := { Account.initial with balance := 10 }
  let chain ← NearChain.init config [([1], owner), ([2], Account.initial)]
  let (chain, deployed) := chain.deploy [1] [2] NativeContract.counterId
  let _ ← deployed
  let (chain, incremented) := chain.call [1] [2] NativeMethod.increment
  let _ ← incremented
  let (_, viewed) := chain.view [2] NativeMethod.get
  let output ← viewed
  return output.returnValue

def escrowExample : Except RuntimeError Balance := do
  let config := RuntimeConfig.default
  let owner := { Account.initial with balance := 10 }
  let chain ← NearChain.init config [([1], owner), ([2], Account.initial), ([3], Account.initial)]
  let (chain, deployed) := chain.deploy [1] [2] NativeContract.escrowId
  let _ ← deployed
  let (chain, deposited) := chain.call [1] [2] NativeMethod.deposit [] 4
  let _ ← deposited
  let (chain, released) := chain.call [1] [2] NativeMethod.release [3]
  let _ ← released
  return chain.balance? [3] |>.getD 0

#eval counterExample
#eval escrowExample

end NEARLean
