import NEARLean.AbstractKernel

/-!
# Abstract transactions and receipts

This module models the asynchronous receipt graph separately from concrete hash
encoding. Receipt and data identifiers are fresh natural numbers; the oracle
canonicalizes nearcore hashes to the same creation-order identity space.
-/

namespace NEARLean

abbrev ReceiptId := Nat
abbrev DataId := Nat

structure DataReceiver where
  dataId : DataId
  receiverId : AccountId
  deriving BEq, Repr

structure ActionReceipt where
  signerId : AccountId
  outputDataReceivers : List DataReceiver
  inputDataIds : List DataId
  actions : List Input
  deriving Repr

structure DataReceipt where
  dataId : DataId
  data : Option StorageValue
  deriving BEq, Repr

inductive ReceiptBody where
  | action (receipt : ActionReceipt)
  | data (receipt : DataReceipt)
  deriving Repr

structure Receipt where
  predecessorId : AccountId
  receiverId : AccountId
  receiptId : ReceiptId
  body : ReceiptBody
  deriving Repr

structure Transaction where
  signerId : AccountId
  receiverId : AccountId
  actions : List Input
  deriving Repr

inductive PromiseResult where
  | successful (value : StorageValue)
  | failed
  deriving BEq, Repr

inductive ReceiptExecutionStatus where
  | successValue (value : StorageValue)
  | successReceiptId (receiptId : ReceiptId)
  | failure (runtimeError : RuntimeError)
  deriving BEq, Repr

structure ReceiptOutcome where
  receiptId : ReceiptId
  executorId : AccountId
  receiptIds : List ReceiptId
  status : ReceiptExecutionStatus
  deriving BEq, Repr

inductive ReceiptDisposition where
  | executed
  | discarded (runtimeError : RuntimeError)
  deriving BEq, Repr

structure CompletedReceipt where
  receipt : Receipt
  disposition : ReceiptDisposition
  deriving Repr

structure ReceivedData where
  receiverId : AccountId
  dataId : DataId
  data : Option StorageValue
  deriving BEq, Repr

def ReceivedData.lookup
    (receiverId : AccountId) (dataId : DataId) : List ReceivedData → Option ReceivedData
  | [] => none
  | entry :: rest =>
      if entry.receiverId = receiverId ∧ entry.dataId = dataId then
        some entry
      else
        lookup receiverId dataId rest

def ReceivedData.set (entry : ReceivedData) : List ReceivedData → List ReceivedData
  | [] => [entry]
  | current :: rest =>
      if current.receiverId = entry.receiverId ∧ current.dataId = entry.dataId then
        entry :: rest
      else
        current :: set entry rest

def ReceivedData.remove
    (receiverId : AccountId) (dataIds : List DataId) : List ReceivedData → List ReceivedData
  | [] => []
  | entry :: rest =>
      if entry.receiverId = receiverId ∧ dataIds.contains entry.dataId then
        remove receiverId dataIds rest
      else
        entry :: remove receiverId dataIds rest

structure ReceiptMachine where
  world : WorldState
  queued : List Receipt := []
  postponed : List Receipt := []
  completed : List CompletedReceipt := []
  receivedData : List ReceivedData := []
  outcomes : List ReceiptOutcome := []
  nextReceiptId : ReceiptId := 0
  nextDataId : DataId := 0
  deriving Repr

def ReceiptMachine.allReceiptIds (state : ReceiptMachine) : List ReceiptId :=
  state.queued.map (·.receiptId) ++
    state.postponed.map (·.receiptId) ++
    state.completed.map (·.receipt.receiptId)

def ReceiptMachine.WellFormed (config : RuntimeConfig) (state : ReceiptMachine) : Prop :=
  state.world.WellFormed config ∧
    state.allReceiptIds.Nodup ∧
    state.allReceiptIds.all (· < state.nextReceiptId) = true ∧
    (state.receivedData.map fun entry => (entry.receiverId, entry.dataId)).Nodup

instance (config : RuntimeConfig) (state : ReceiptMachine) :
    Decidable (state.WellFormed config) := by
  unfold ReceiptMachine.WellFormed
  infer_instance

def ReceiptMachine.init (world : WorldState) : ReceiptMachine :=
  { world := world }

theorem ReceiptMachine.init_wellFormed
    (config : RuntimeConfig)
    (world : WorldState)
    (worldValid : world.WellFormed config) :
    (ReceiptMachine.init world).WellFormed config := by
  exact ⟨worldValid, List.Pairwise.nil, rfl, List.Pairwise.nil⟩

def Transaction.toReceipt (transaction : Transaction) (receiptId : ReceiptId) : Receipt := {
  predecessorId := transaction.signerId
  receiverId := transaction.receiverId
  receiptId := receiptId
  body := .action {
    signerId := transaction.signerId
    outputDataReceivers := []
    inputDataIds := []
    actions := transaction.actions
  }
}

def ReceiptMachine.commit
    (config : RuntimeConfig)
    (before candidate : ReceiptMachine) : ReceiptMachine :=
  if candidate.WellFormed config then candidate else before

def ReceiptMachine.submitCandidate
    (state : ReceiptMachine) (transaction : Transaction) : ReceiptMachine :=
  let receipt := transaction.toReceipt state.nextReceiptId
  { state with
    queued := state.queued ++ [receipt]
    nextReceiptId := state.nextReceiptId + 1
  }

def ReceiptMachine.submit
    (config : RuntimeConfig)
    (state : ReceiptMachine)
    (transaction : Transaction) : ReceiptMachine :=
  state.commit config (state.submitCandidate transaction)

def ActionReceipt.ready
    (state : ReceiptMachine) (receiverId : AccountId) (receipt : ActionReceipt) : Bool :=
  receipt.inputDataIds.all fun dataId =>
    (ReceivedData.lookup receiverId dataId state.receivedData).isSome

def ActionReceipt.promiseResults
    (state : ReceiptMachine)
    (receiverId : AccountId)
    (receipt : ActionReceipt) : List PromiseResult :=
  receipt.inputDataIds.map fun dataId =>
    match ReceivedData.lookup receiverId dataId state.receivedData with
    | some data => match data.data with
      | some value => .successful value
      | none => .failed
    | none => .failed

inductive ActionDecision where
  | execute
  | postpone
  deriving BEq, Repr

def decideAction
    (state : ReceiptMachine) (receipt : Receipt) (action : ActionReceipt) : ActionDecision :=
  if action.ready state receipt.receiverId then .execute else .postpone

/-- An action receipt can be selected for execution only after all dependencies exist. -/
theorem callback_cannot_execute_before_dependencies
    (selected : decideAction state receipt action = .execute) :
    action.ready state receipt.receiverId = true := by
  unfold decideAction at selected
  split at selected
  · assumption
  · contradiction

private def ReceiptMachine.complete
    (state : ReceiptMachine)
    (receipt : Receipt)
    (disposition : ReceiptDisposition) : ReceiptMachine :=
  { state with completed := state.completed ++ [{ receipt := receipt, disposition := disposition }] }

private def buildDataReceipts
    (nextId : ReceiptId)
    (predecessorId : AccountId)
    (receivers : List DataReceiver)
    (data : Option StorageValue) : List Receipt × ReceiptId :=
  match receivers with
  | [] => ([], nextId)
  | receiver :: rest =>
      let receipt : Receipt := {
        predecessorId := predecessorId
        receiverId := receiver.receiverId
        receiptId := nextId
        body := .data { dataId := receiver.dataId, data := data }
      }
      let (receipts, followingId) :=
        buildDataReceipts (nextId + 1) predecessorId rest data
      (receipt :: receipts, followingId)

private def executeInputs
    (config : RuntimeConfig)
    (original : WorldState)
    (inputs : List Input) : WorldState × Except RuntimeError Output :=
  let rec loop (state : WorldState) : List Input → WorldState × Except RuntimeError Output
    | [] => (state, .ok Output.empty)
    | input :: rest =>
        match step config state input with
        | (_, .error runtimeError) => (original, .error runtimeError)
        | (next, .ok output) =>
            match rest with
            | [] => (next, .ok output)
            | _ => loop next rest
  loop original inputs

private def ReceiptMachine.finishAction
    (state : ReceiptMachine)
    (receipt : Receipt)
    (action : ActionReceipt)
    (world : WorldState)
    (result : Except RuntimeError Output) : ReceiptMachine :=
  let data := match result with
    | .ok output => some output.returnValue
    | .error _ => none
  let (dataReceipts, nextReceiptId) :=
    buildDataReceipts state.nextReceiptId receipt.receiverId action.outputDataReceivers data
  let status := match result with
    | .ok output => ReceiptExecutionStatus.successValue output.returnValue
    | .error runtimeError => .failure runtimeError
  let disposition := match result with
    | .ok _ => ReceiptDisposition.executed
    | .error runtimeError => .discarded runtimeError
  let state := state.complete receipt disposition
  { state with
    world := world
    queued := state.queued ++ dataReceipts
    receivedData := ReceivedData.remove receipt.receiverId action.inputDataIds state.receivedData
    outcomes := state.outcomes ++ [{
      receiptId := receipt.receiptId
      executorId := receipt.receiverId
      receiptIds := []
      status := status
    }]
    nextReceiptId := nextReceiptId
  }

private def ReceiptMachine.executeCallThen
    (config : RuntimeConfig)
    (state : ReceiptMachine)
    (receipt : Receipt)
    (action : ActionReceipt)
    (caller receiver target : AccountId)
    (attachedDeposit : Balance)
    (prepaidGas : Gas) : ReceiptMachine :=
  let validated : Except RuntimeError WorldState := do
    if prepaidGas = 0 ∨ config.maxGas < prepaidGas then
      throw .invalidGas
    let deposited ← state.world.transferBalance config caller receiver attachedDeposit
    let receiverAccount ← Option.orError (.accountNotFound receiver) (deposited.account? receiver)
    if receiverAccount.contract != some NativeContract.asyncId then
      throw (.contractNotDeployed receiver)
    let targetAccount ← Option.orError (.accountNotFound target) (deposited.account? target)
    if targetAccount.contract != some NativeContract.asyncId then
      throw (.contractNotDeployed target)
    return deposited
  match validated with
  | .error runtimeError => state.finishAction receipt action state.world (.error runtimeError)
  | .ok world =>
      let targetId := state.nextReceiptId
      let callbackId := targetId + 1
      let dataId := state.nextDataId
      let targetReceipt : Receipt := {
        predecessorId := receiver
        receiverId := target
        receiptId := targetId
        body := .action {
          signerId := action.signerId
          outputDataReceivers := [{ dataId := dataId, receiverId := receiver }]
          inputDataIds := []
          actions := [.functionCall receiver target NativeMethod.echo [] 0 prepaidGas]
        }
      }
      let callbackReceipt : Receipt := {
        predecessorId := receiver
        receiverId := receiver
        receiptId := callbackId
        body := .action {
          signerId := action.signerId
          outputDataReceivers := []
          inputDataIds := [dataId]
          actions := [.functionCall receiver receiver NativeMethod.callback [] 0 prepaidGas]
        }
      }
      let state := state.complete receipt .executed
      { state with
        world := world
        queued := state.queued ++ [targetReceipt, callbackReceipt]
        outcomes := state.outcomes ++ [{
          receiptId := receipt.receiptId
          executorId := receipt.receiverId
          receiptIds := [targetId, callbackId]
          status := .successReceiptId callbackId
        }]
        nextReceiptId := callbackId + 1
        nextDataId := dataId + 1
      }

private def ReceiptMachine.executeCallback
    (state : ReceiptMachine)
    (receipt : Receipt)
    (action : ActionReceipt) : ReceiptMachine :=
  let result := match action.promiseResults state receipt.receiverId with
    | .successful value :: _ => Except.ok { Output.empty with returnValue := value }
    | _ => Except.ok Output.empty
  state.finishAction receipt action state.world result

private def ReceiptMachine.executeAction
    (config : RuntimeConfig)
    (state : ReceiptMachine)
    (receipt : Receipt)
    (action : ActionReceipt) : ReceiptMachine :=
  match action.actions with
  | [.functionCall caller receiver method arguments deposit gas] =>
      if method = NativeMethod.callThen then
        state.executeCallThen config receipt action caller receiver arguments deposit gas
      else if method = NativeMethod.callback then
        state.executeCallback receipt action
      else
        let (world, result) := executeInputs config state.world action.actions
        state.finishAction receipt action world result
  | _ =>
      let (world, result) := executeInputs config state.world action.actions
      state.finishAction receipt action world result

private def ReceiptMachine.takeReady :
    ReceiptMachine → List Receipt → Option (Receipt × List Receipt)
  | _, [] => none
  | state, receipt :: rest =>
      match receipt.body with
      | .action action =>
          if action.ready state receipt.receiverId then
            some (receipt, rest)
          else
            match takeReady state rest with
            | none => none
            | some (ready, remaining) => some (ready, receipt :: remaining)
      | .data _ =>
          match takeReady state rest with
          | none => none
          | some (ready, remaining) => some (ready, receipt :: remaining)

private def ReceiptMachine.processData
    (config : RuntimeConfig)
    (state : ReceiptMachine)
    (receipt : Receipt)
    (data : DataReceipt) : ReceiptMachine :=
  let state := state.complete receipt .executed
  let received : ReceivedData := {
    receiverId := receipt.receiverId
    dataId := data.dataId
    data := data.data
  }
  let state := { state with
    receivedData := ReceivedData.set received state.receivedData }
  match state.takeReady state.postponed with
  | none => state
  | some (ready, remaining) =>
      match ready.body with
      | .action action => { state with postponed := remaining }.executeAction config ready action
      | .data _ => state

def ReceiptMachine.processCandidate
    (config : RuntimeConfig) (state : ReceiptMachine) : ReceiptMachine :=
  match state.queued with
  | [] => state
  | receipt :: rest =>
      let state := { state with queued := rest }
      match receipt.body with
      | .action action =>
          match decideAction state receipt action with
          | .execute => state.executeAction config receipt action
          | .postpone => { state with postponed := state.postponed ++ [receipt] }
      | .data data => state.processData config receipt data

def ReceiptMachine.processOne
    (config : RuntimeConfig) (state : ReceiptMachine) : ReceiptMachine :=
  state.commit config (state.processCandidate config)

def ReceiptMachine.run
    (config : RuntimeConfig) : Nat → ReceiptMachine → ReceiptMachine
  | 0, state => state
  | steps + 1, state => run config steps (state.processOne config)

/-- Runtime validation preserves receipt and world-state invariants. -/
theorem ReceiptMachine.commit_preserves_wellFormed
    (config : RuntimeConfig)
    (before candidate : ReceiptMachine)
    (beforeValid : before.WellFormed config) :
    (before.commit config candidate).WellFormed config := by
  unfold ReceiptMachine.commit
  split
  · assumption
  · exact beforeValid

theorem ReceiptMachine.submit_preserves_wellFormed
    (config : RuntimeConfig)
    (state : ReceiptMachine)
    (transaction : Transaction)
    (stateValid : state.WellFormed config) :
    (state.submit config transaction).WellFormed config :=
  ReceiptMachine.commit_preserves_wellFormed
    config state (state.submitCandidate transaction) stateValid

theorem ReceiptMachine.process_preserves_wellFormed
    (config : RuntimeConfig)
    (state : ReceiptMachine)
    (stateValid : state.WellFormed config) :
    (state.processOne config).WellFormed config :=
  ReceiptMachine.commit_preserves_wellFormed
    config state (state.processCandidate config) stateValid

theorem ReceiptMachine.run_preserves_wellFormed
    (config : RuntimeConfig)
    (state : ReceiptMachine)
    (steps : Nat)
    (stateValid : state.WellFormed config) :
    (state.run config steps).WellFormed config := by
  induction steps generalizing state with
  | zero => exact stateValid
  | succ steps ih =>
      exact ih (state := state.processOne config)
        (ReceiptMachine.process_preserves_wellFormed config state stateValid)

/-- Receipt identifiers remain unique after every validated processing step. -/
theorem ReceiptMachine.receiptId_unique
    (config : RuntimeConfig)
    (state : ReceiptMachine)
    (stateValid : state.WellFormed config) :
    (state.processOne config).allReceiptIds.Nodup :=
  (ReceiptMachine.process_preserves_wellFormed config state stateValid).2.1

/-- Fixed state, inputs, and scheduling determine exactly one next receipt state. -/
theorem ReceiptMachine.processing_deterministic
    (config : RuntimeConfig)
    (state next₁ next₂ : ReceiptMachine)
    (first : state.processOne config = next₁)
    (second : state.processOne config = next₂) :
    next₁ = next₂ := by
  rw [first] at second
  exact second

def ReceiptMachine.Accounted (state : ReceiptMachine) (receiptId : ReceiptId) : Prop :=
  receiptId ∈ state.queued.map (·.receiptId) ∨
    receiptId ∈ state.postponed.map (·.receiptId) ∨
    receiptId ∈ state.completed.map (·.receipt.receiptId)

/-- Every created receipt remains queued, postponed, executed, or explicitly discarded. -/
theorem ReceiptMachine.every_created_receipt_accounted
    (state : ReceiptMachine)
    (receiptId : ReceiptId)
    (created : receiptId ∈ state.allReceiptIds) :
    state.Accounted receiptId := by
  unfold ReceiptMachine.allReceiptIds at created
  rw [List.mem_append] at created
  unfold ReceiptMachine.Accounted
  rcases created with active | completed
  · rw [List.mem_append] at active
    rcases active with queued | postponed
    · exact Or.inl queued
    · exact Or.inr (Or.inl postponed)
  · exact Or.inr (Or.inr completed)

def asyncAccount : Account :=
  { Account.initial with contract := some NativeContract.asyncId }

def crossContractExample : List ReceiptOutcome :=
  let config := RuntimeConfig.default
  let owner := { Account.initial with balance := 10 }
  let world := { WorldState.initial config with
    accounts := [([1], owner), ([2], asyncAccount), ([3], asyncAccount)] }
  let machine := ReceiptMachine.init world
  let transaction : Transaction := {
    signerId := [1]
    receiverId := [2]
    actions := [.functionCall [1] [2] NativeMethod.callThen [3] 0 10]
  }
  (machine.submit config transaction).run config 4 |>.outcomes

#eval crossContractExample

end NEARLean
