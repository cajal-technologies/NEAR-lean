import Lean.Data.Json
import NEARLean.Receipts
import NEARLean.Sandbox

/-!
# Canonical differential traces

The types in this executable adapter are the stable boundary shared by the Lean
executor and the pinned nearcore oracle. Token amounts are decimal strings so
the same files round-trip without precision loss in JavaScript tooling.
-/

namespace NEARLean

open Lean

structure TraceGenesisAccount where
  id : String
  balance : String
  contract : Option String
  deriving FromJson, Repr

structure TraceAction where
  kind : String
  creator : Option String
  accountId : Option String
  initialBalance : Option String
  sender : Option String
  receiver : Option String
  amount : Option String
  deployer : Option String
  contract : Option String
  caller : Option String
  method : Option String
  arguments : Option String
  attachedDeposit : Option String
  prepaidGas : Option String
  deriving FromJson, Repr

structure CanonicalTrace where
  schemaVersion : Nat
  nearcoreCommit : String
  nearcoreRelease : String
  protocolVersion : Nat
  seed : Nat
  genesis : List TraceGenesisAccount
  actions : List TraceAction
  observeAccounts : List String
  receiptMode : Option Bool
  deriving FromJson, Repr

structure CanonicalStorageEntry where
  key : List Nat
  value : List Nat
  deriving BEq, FromJson, ToJson, Repr

structure CanonicalAccount where
  id : String
  present : Bool
  balance : Option String
  storage : List CanonicalStorageEntry
  contract : Option String
  deriving BEq, FromJson, ToJson, Repr

structure CanonicalReceiptOutcome where
  id : Nat
  executorId : List Nat
  receiptIds : List Nat
  statusKind : String
  returnValue : List Nat
  statusReceiptId : Option Nat
  errorCategory : Option String
  deriving BEq, FromJson, ToJson, Repr

structure CanonicalReceiptGraph where
  transactionReceiptIds : List Nat
  outcomes : List CanonicalReceiptOutcome
  deriving BEq, FromJson, ToJson, Repr

def CanonicalReceiptGraph.empty : CanonicalReceiptGraph := {
  transactionReceiptIds := []
  outcomes := []
}

structure CanonicalObservation where
  index : Nat
  success : Bool
  errorCategory : Option String
  returnValue : List Nat
  logs : List (List Nat)
  receiptGraph : CanonicalReceiptGraph
  accounts : List CanonicalAccount
  deriving BEq, FromJson, ToJson, Repr

structure CanonicalRun where
  schemaVersion : Nat
  nearcoreCommit : String
  nearcoreRelease : String
  protocolVersion : Nat
  seed : Nat
  observations : List CanonicalObservation
  deriving BEq, FromJson, ToJson, Repr

private def requireField (name : String) : Option α → Except String α
  | none => .error s!"action is missing `{name}`"
  | some value => .ok value

private def parseAmount (name : String) (value : Option String) : Except String Nat := do
  let text ← requireField name value
  match text.toNat? with
  | none => .error s!"action field `{name}` is not a natural number"
  | some amount => .ok amount

private def bytes (value : String) : List UInt8 :=
  value.toUTF8.toList

private def contractId : String → Except String ContractId
  | "counter" => .ok NativeContract.counterId
  | "escrow" => .ok NativeContract.escrowId
  | "async" => .ok NativeContract.asyncId
  | name => .error s!"unsupported canonical contract `{name}`"

private def methodId : String → Except String StorageKey
  | "increment" => .ok NativeMethod.increment
  | "get" => .ok NativeMethod.get
  | "deposit" => .ok NativeMethod.deposit
  | "release" => .ok NativeMethod.release
  | "balance" => .ok NativeMethod.balance
  | "call_then" => .ok NativeMethod.callThen
  | "echo" => .ok NativeMethod.echo
  | "callback" => .ok NativeMethod.callback
  | name => .error s!"unsupported canonical method `{name}`"

def TraceAction.toInput (action : TraceAction) : Except String Input := do
  match action.kind with
  | "createAccount" =>
      let creator ← requireField "creator" action.creator
      let accountId ← requireField "accountId" action.accountId
      let initialBalance ← parseAmount "initialBalance" action.initialBalance
      return .createAccount (bytes creator) (bytes accountId) initialBalance
  | "transfer" =>
      let sender ← requireField "sender" action.sender
      let receiver ← requireField "receiver" action.receiver
      let amount ← parseAmount "amount" action.amount
      return .transfer (bytes sender) (bytes receiver) amount
  | "deployContract" =>
      let deployer ← requireField "deployer" action.deployer
      let accountId ← requireField "accountId" action.accountId
      let contract ← requireField "contract" action.contract >>= contractId
      return .deployContract (bytes deployer) (bytes accountId) contract
  | "functionCall" =>
      let caller ← requireField "caller" action.caller
      let receiver ← requireField "receiver" action.receiver
      let method ← requireField "method" action.method >>= methodId
      let arguments := bytes (action.arguments.getD "")
      let attachedDeposit ← parseAmount "attachedDeposit" action.attachedDeposit
      let prepaidGas ← parseAmount "prepaidGas" action.prepaidGas
      return .functionCall (bytes caller) (bytes receiver) method arguments
        attachedDeposit prepaidGas
  | kind => .error s!"unsupported canonical action `{kind}`"

def Input.transaction (input : Input) : Transaction :=
  match input with
  | .createAccount creator accountId _ => {
      signerId := creator
      receiverId := accountId
      actions := [input]
    }
  | .transfer sender receiver _ => {
      signerId := sender
      receiverId := receiver
      actions := [input]
    }
  | .deployContract deployer accountId _ => {
      signerId := deployer
      receiverId := accountId
      actions := [input]
    }
  | .functionCall caller receiver _ _ _ _ => {
      signerId := caller
      receiverId := receiver
      actions := [input]
    }

def RuntimeError.category : RuntimeError → String
  | .invalidInitialState => "invalidInitialState"
  | .invalidAccountId _ => "invalidAccountId"
  | .accountAlreadyExists _ => "accountAlreadyExists"
  | .accountNotFound _ => "accountNotFound"
  | .insufficientBalance _ => "insufficientBalance"
  | .balanceOverflow _ => "balanceOverflow"
  | .invalidGas => "invalidGas"
  | .contractAlreadyDeployed _ => "contractAlreadyDeployed"
  | .unsupportedContract _ => "unsupportedContract"
  | .contractNotDeployed _ => "contractNotDeployed"
  | .methodNotFound _ => "methodNotFound"
  | .depositRequired => "depositRequired"
  | .unauthorized => "unauthorized"
  | .invalidArguments => "invalidArguments"
  | .invariantViolation => "invariantViolation"

private def naturals (value : List UInt8) : List Nat :=
  value.map UInt8.toNat

private def canonicalContract : Option ContractId → Option String
  | some id =>
      if id = NativeContract.counterId then some "counter"
      else if id = NativeContract.escrowId then some "escrow"
      else if id = NativeContract.asyncId then some "async"
      else some "unknown"
  | none => none

private def canonicalAccount (state : WorldState) (id : String) : CanonicalAccount :=
  match state.account? (bytes id) with
  | none => {
      id := id
      present := false
      balance := none
      storage := []
      contract := none
    }
  | some account => {
      id := id
      present := true
      balance := some (toString account.balance)
      storage := account.storage.map fun entry => {
        key := naturals entry.1
        value := naturals entry.2
      }
      contract := canonicalContract account.contract
    }

private def snapshot (state : WorldState) (accountIds : List String) : List CanonicalAccount :=
  accountIds.map (canonicalAccount state)

private def canonicalReceiptOutcome (outcome : ReceiptOutcome) : CanonicalReceiptOutcome :=
  let (statusKind, returnValue, statusReceiptId, errorCategory) := match outcome.status with
    | .successValue value => ("successValue", naturals value, none, none)
    | .successReceiptId receiptId => ("successReceiptId", [], some receiptId, none)
    | .failure runtimeError => ("failure", [], none, some runtimeError.category)
  {
    id := outcome.receiptId
    executorId := naturals outcome.executorId
    receiptIds := outcome.receiptIds
    statusKind := statusKind
    returnValue := returnValue
    statusReceiptId := statusReceiptId
    errorCategory := errorCategory
  }

private def runReceiptInput
    (chain : NearChain)
    (input : Input) : NearChain × Except RuntimeError Output × CanonicalReceiptGraph :=
  let machine := ReceiptMachine.init chain.state
  let machine := (machine.submit chain.config input.transaction).run chain.config 32
  let graph : CanonicalReceiptGraph := {
    transactionReceiptIds := if machine.outcomes.isEmpty then [] else [0]
    outcomes := machine.outcomes.map canonicalReceiptOutcome
  }
  let result := match machine.outcomes.getLast? with
    | none => Except.error RuntimeError.invariantViolation
    | some outcome => match outcome.status with
      | .failure runtimeError => .error runtimeError
      | .successValue value => .ok { Output.empty with returnValue := value }
      | .successReceiptId _ => .ok Output.empty
  ({ chain with state := machine.world }, result, graph)

private def initialChain (trace : CanonicalTrace) : Except String NearChain := do
  let accounts ← trace.genesis.mapM fun entry => do
    let balance ← match entry.balance.toNat? with
      | none => .error s!"genesis balance for `{entry.id}` is not a natural number"
      | some balance => .ok balance
    let contract ← match entry.contract with
      | none => .ok none
      | some name => contractId name |>.map some
    return (bytes entry.id, { Account.initial with balance := balance, contract := contract })
  match NearChain.init RuntimeConfig.default accounts with
  | .error runtimeError => .error s!"invalid canonical genesis: {runtimeError.category}"
  | .ok chain => .ok chain

private def runActions
    (trace : CanonicalTrace)
    (index : Nat)
    (chain : NearChain)
    (actions : List TraceAction)
    (observations : List CanonicalObservation) : Except String (List CanonicalObservation) := do
  match actions with
  | [] => return observations.reverse
  | action :: rest =>
      let input ← action.toInput
      let (next, result, receiptGraph) :=
        if trace.receiptMode.getD false then
          runReceiptInput chain input
        else
          let (next, result) := chain.apply input
          (next, result, CanonicalReceiptGraph.empty)
      let observation := match result with
        | .error runtimeError => {
            index := index
            success := false
            errorCategory := some runtimeError.category
            returnValue := []
            logs := []
            receiptGraph := receiptGraph
            accounts := snapshot next.state trace.observeAccounts
          }
        | .ok output => {
            index := index
            success := true
            errorCategory := none
            returnValue := naturals output.returnValue
            logs := output.logs.map naturals
            receiptGraph := receiptGraph
            accounts := snapshot next.state trace.observeAccounts
          }
      runActions trace (index + 1) next rest (observation :: observations)

def CanonicalTrace.run (trace : CanonicalTrace) : Except String CanonicalRun := do
  if trace.schemaVersion != 1 then
    throw s!"unsupported trace schema {trace.schemaVersion}"
  let chain ← initialChain trace
  let observations ← runActions trace 0 chain trace.actions []
  return {
    schemaVersion := trace.schemaVersion
    nearcoreCommit := trace.nearcoreCommit
    nearcoreRelease := trace.nearcoreRelease
    protocolVersion := trace.protocolVersion
    seed := trace.seed
    observations := observations
  }

def CanonicalTrace.parse (source : String) : Except String CanonicalTrace := do
  let json ← Json.parse source
  fromJson? json

def CanonicalRun.json (run : CanonicalRun) : String :=
  Json.pretty (toJson run)

end NEARLean
