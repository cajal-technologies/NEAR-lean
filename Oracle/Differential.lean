import Lean.Data.Json
import NEARLean.Blocks
import NEARLean.Economics
import NEARLean.Sandbox
import NEARLean.WasmHost

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
  blockMode : Option Bool
  economicMode : Option Bool
  wasmMode : Option Bool
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
  blockIndex : Option Nat
  deriving BEq, FromJson, ToJson, Repr

structure CanonicalReceiptGraph where
  transactionReceiptIds : List Nat
  outcomes : List CanonicalReceiptOutcome
  deriving BEq, FromJson, ToJson, Repr

def CanonicalReceiptGraph.empty : CanonicalReceiptGraph := {
  transactionReceiptIds := []
  outcomes := []
}

structure CanonicalStorageUsageDelta where
  id : String
  bytes : String
  deriving BEq, FromJson, ToJson, Repr

structure CanonicalEconomics where
  gasBurnt : String
  gasUsed : String
  tokensBurnt : String
  refundCount : Nat
  storageUsageDelta : List CanonicalStorageUsageDelta
  deriving BEq, FromJson, ToJson, Repr

def CanonicalEconomics.empty : CanonicalEconomics := {
  gasBurnt := "0"
  gasUsed := "0"
  tokensBurnt := "0"
  refundCount := 0
  storageUsageDelta := []
}

structure CanonicalObservation where
  index : Nat
  success : Bool
  errorCategory : Option String
  returnValue : List Nat
  logs : List (List Nat)
  receiptGraph : CanonicalReceiptGraph
  economics : CanonicalEconomics
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
  | "fungible_token" => .ok NativeContract.fungibleTokenId
  | "nft" => .ok NativeContract.nftId
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
  | "mint" => .ok NativeMethod.mint
  | "ft_balance_of" => .ok NativeMethod.ftBalanceOf
  | "ft_transfer" => .ok NativeMethod.ftTransfer
  | "nft_mint" => .ok NativeMethod.nftMint
  | "nft_token" => .ok NativeMethod.nftToken
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
      else if id = NativeContract.fungibleTokenId then some "fungible_token"
      else if id = NativeContract.nftId then some "nft"
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

private def canonicalReceiptOutcome
    (outcome : ReceiptOutcome) (blockIndex : Option Nat := none) : CanonicalReceiptOutcome :=
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
    blockIndex := blockIndex
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

private def runBlockInput
    (chain : NearChain)
    (input : Input) : NearChain × Except RuntimeError Output × CanonicalReceiptGraph :=
  let initialHeight := chain.state.block.height
  let scheduler := BlockScheduler.init chain.config chain.state 10
    |>.submit input.transaction
    |>.runUntil 32
  let blockOutcomes := scheduler.blocks.flatMap (·.outcomes)
  let outcomes := blockOutcomes.map fun outcome =>
    canonicalReceiptOutcome outcome.outcome (some (outcome.blockHeight - initialHeight))
  let graph : CanonicalReceiptGraph := {
    transactionReceiptIds := if outcomes.isEmpty then [] else [0]
    outcomes := outcomes
  }
  let result := match blockOutcomes.getLast? with
    | none => Except.error RuntimeError.invariantViolation
    | some outcome => match outcome.outcome.status with
      | .failure runtimeError => .error runtimeError
      | .successValue value => .ok { Output.empty with returnValue := value }
      | .successReceiptId _ => .ok Output.empty
  ({ chain with state := scheduler.machine.world }, result, graph)

private def economics
    (trace : CanonicalTrace)
    (action : TraceAction)
    (succeeded : Bool) : CanonicalEconomics :=
  if trace.economicMode.getD false ∧ succeeded ∧ action.kind = "transfer" then {
    gasBurnt := toString EconomicConfig.protocol86Sandbox.schedule.transferTotalGas
    gasUsed := toString EconomicConfig.protocol86Sandbox.schedule.transferTotalGas
    tokensBurnt := "0"
    refundCount := 1
    storageUsageDelta := trace.observeAccounts.map fun id => { id := id, bytes := "0" }
  } else
    CanonicalEconomics.empty

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
        if trace.blockMode.getD false then
          runBlockInput chain input
        else if trace.receiptMode.getD false then
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
            economics := economics trace action false
            accounts := snapshot next.state trace.observeAccounts
          }
        | .ok output => {
            index := index
            success := true
            errorCategory := none
            returnValue := naturals output.returnValue
            logs := output.logs.map naturals
            receiptGraph := receiptGraph
            economics := economics trace action true
            accounts := snapshot next.state trace.observeAccounts
          }
      runActions trace (index + 1) next rest (observation :: observations)

private def directReceiptGraph
    (executor : String)
    (success : Bool)
    (returnValue : List Nat)
    (errorCategory : Option String) : CanonicalReceiptGraph := {
  transactionReceiptIds := [0]
  outcomes := [{
    id := 0
    executorId := naturals (bytes executor)
    receiptIds := []
    statusKind := if success then "successValue" else "failure"
    returnValue := returnValue
    statusReceiptId := none
    errorCategory := errorCategory
    blockIndex := none
  }]
}

private def updateWasmStorage
    (chain : NearChain)
    (accountId : String)
    (host : WasmHost.State) : Except String NearChain := do
  let id := bytes accountId
  let account ← match chain.state.account? id with
    | some account => pure account
    | none => throw s!"WASM account `{accountId}` does not exist"
  return { chain with state := chain.state.setAccount id {
    account with storage := host.storageEntries } }

private def wasmContractName (chain : NearChain) (accountId : String) : Except String String := do
  let account ← match chain.state.account? (bytes accountId) with
    | some account => pure account
    | none => throw s!"WASM account `{accountId}` does not exist"
  match canonicalContract account.contract with
  | some contract => pure contract
  | none => throw s!"WASM account `{accountId}` has no compiled contract"

private def wasmContext
    (chain : NearChain)
    (action : TraceAction)
    (receiver caller : String) : Except String WasmHost.Context := do
  let attachedDeposit ← parseAmount "attachedDeposit" action.attachedDeposit
  let prepaidGas ← parseAmount "prepaidGas" action.prepaidGas
  let account ← match chain.state.account? (bytes receiver) with
    | some account => pure account
    | none => throw s!"WASM account `{receiver}` does not exist"
  return {
    currentAccountId := bytes receiver
    predecessorAccountId := bytes caller
    signerAccountId := bytes caller
    input := bytes (action.arguments.getD "")
    blockIndex := UInt64.ofNat chain.state.block.height
    blockTimestamp := UInt64.ofNat chain.state.block.timestamp
    storageUsage := UInt64.ofNat (account.storage.foldl
      (fun total entry => total + entry.1.length + entry.2.length) 0)
    accountBalance := account.balance
    accountLockedBalance := account.locked
    attachedDeposit := attachedDeposit
    prepaidGas := UInt64.ofNat prepaidGas
  }

private def executeWasmCall
    (chain : NearChain)
    (action : TraceAction)
    (receiver caller method : String) : Except String
      (NearChain × Bool × Option String × Output × WasmHost.State) := do
  let attachedDeposit ← parseAmount "attachedDeposit" action.attachedDeposit
  let depositedState ← chain.state.transferBalance chain.config
    (bytes caller) (bytes receiver) attachedDeposit
    |>.mapError (fun error => s!"WASM deposit transfer failed: {error.category}")
  let executionChain := { chain with state := depositedState }
  let account ← match executionChain.state.account? (bytes receiver) with
    | some account => pure account
    | none => throw s!"WASM account `{receiver}` does not exist"
  let contract ← wasmContractName executionChain receiver
  let context ← wasmContext executionChain action receiver caller
  let initial := WasmHost.State.ofStorage account.storage
  match WasmHost.runContract contract initial context method with
  | .error (.missingExport _) =>
      pure (chain, false, some "methodNotFound", Output.empty, initial)
  | .error executionError =>
      throw s!"WASM execution failed: {repr executionError}"
  | .ok run => match run.outcome with
    | .trap _ => pure (chain, false, some "contractFailure", Output.empty, initial)
    | .success _ store =>
        let (host, returnValue) ← WasmHost.resolveReturnedPromise contract context store.host
          |>.mapError (fun error => s!"WASM promise execution failed: {repr error}")
        let next ← updateWasmStorage executionChain receiver host
        let output := { Output.empty with
          returnValue := returnValue
          logs := host.logs }
        pure (next, true, none, output, host)

private def runWasmActions
    (trace : CanonicalTrace)
    (index : Nat)
    (chain : NearChain)
    (actions : List TraceAction)
    (observations : List CanonicalObservation) : Except String (List CanonicalObservation) := do
  match actions with
  | [] => return observations.reverse
  | action :: rest =>
      let (next, success, errorCategory, output, executor, host) ←
        match action.kind with
        | "functionCall" =>
            let receiver ← requireField "receiver" action.receiver
            let caller ← requireField "caller" action.caller
            let method ← requireField "method" action.method
            let (next, success, errorCategory, output, host) ←
              executeWasmCall chain action receiver caller method
            pure (next, success, errorCategory, output, receiver, host)
        | "deployContract" =>
            let accountId ← requireField "accountId" action.accountId
            let deployer ← requireField "deployer" action.deployer
            let input ← action.toInput
            let (deployed, result) := chain.apply input
            match result with
            | .error runtimeError =>
                pure (chain, false, some runtimeError.category, Output.empty, accountId,
                  WasmHost.State.ofStorage [])
            | .ok output =>
                let account ← match deployed.state.account? (bytes accountId) with
                  | some account => pure account
                  | none => throw s!"deployed WASM account `{accountId}` does not exist"
                let cleanState := deployed.state.setAccount
                  (bytes accountId) { account with storage := [] }
                let deployed := { deployed with state := cleanState }
                let account := { account with storage := [] }
                let contract ← requireField "contract" action.contract
                let initial := WasmHost.State.ofStorage account.storage
                let context : WasmHost.Context := {
                  currentAccountId := bytes accountId
                  predecessorAccountId := bytes deployer
                  signerAccountId := bytes deployer
                  prepaidGas := UInt64.ofNat 100000000000000
                }
                match WasmHost.runContract contract initial context "init" with
                | .error (.missingExport _) =>
                    pure (deployed, true, none, output, accountId, initial)
                | .error executionError =>
                    throw s!"WASM initialization failed: {repr executionError}"
                | .ok run => match run.outcome with
                  | .trap _ =>
                      pure (chain, false, some "contractFailure", Output.empty, accountId, initial)
                  | .success _ store =>
                      let deployed ← updateWasmStorage deployed accountId store.host
                      pure (deployed, true, none, output, accountId, store.host)
        | _ =>
            let input ← action.toInput
            let (next, result) := chain.apply input
            let executor ← match action.accountId.orElse fun _ => action.receiver with
              | some executor => pure executor
              | none => throw s!"action `{action.kind}` has no executor"
            match result with
            | .error runtimeError =>
                pure (chain, false, some runtimeError.category, Output.empty, executor,
                  WasmHost.State.ofStorage [])
            | .ok output =>
                pure (next, true, none, output, executor, WasmHost.State.ofStorage [])
      let returnValue := naturals output.returnValue
      let receiptGraph := if trace.receiptMode.getD false ∧ success then
        directReceiptGraph executor success returnValue errorCategory
      else CanonicalReceiptGraph.empty
      let observation : CanonicalObservation := {
        index := index
        success := success
        errorCategory := errorCategory
        returnValue := returnValue
        logs := output.logs.map naturals
        receiptGraph := receiptGraph
        economics := economics trace action success
        accounts := snapshot next.state trace.observeAccounts
      }
      let _ := host
      runWasmActions trace (index + 1) next rest (observation :: observations)

def CanonicalTrace.run (trace : CanonicalTrace) : Except String CanonicalRun := do
  if trace.schemaVersion != 1 then
    throw s!"unsupported trace schema {trace.schemaVersion}"
  let chain ← initialChain trace
  let observations ← if trace.wasmMode.getD false then
    runWasmActions trace 0 chain trace.actions []
  else
    runActions trace 0 chain trace.actions []
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
