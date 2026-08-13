import CodeLib.Near.Env
import NEARLean.Crypto.SHA256
import NEARLean.Wasm

/-!
# Protocol-86 NEAR host adapter

Talos supplies the host semantics. This module adds the pinned nearcore limits,
gas schedule, per-call context, persistent-storage projection, and actual
compiled-contract selection used by the differential oracle.
-/

namespace NEARLean.WasmHost

open Wasm
open NEARLean.WasmExecution

abbrev Bytes := List UInt8
abbrev Storage := List (Bytes × Bytes)
abbrev State := Wasm.NearState
abbrev Context := Wasm.NearContext

namespace Protocol86Gas

def base : Nat := 264768111
def readMemoryBase : Nat := 2609863200
def readMemoryByte : Nat := 3801333
def writeMemoryBase : Nat := 2803794861
def writeMemoryByte : Nat := 2723772
def readRegisterBase : Nat := 2517165186
def readRegisterByte : Nat := 98562
def writeRegisterBase : Nat := 2865522486
def writeRegisterByte : Nat := 3801564
def utf8Base : Nat := 3111779061
def utf8Byte : Nat := 291580479
def sha256Base : Nat := 4540970250
def sha256Byte : Nat := 24117351
def logBase : Nat := 3543313050
def logByte : Nat := 13198791
def storageWriteBase : Nat := 64196736000
def storageWriteKeyByte : Nat := 70482867
def storageWriteValueByte : Nat := 31018539
def storageWriteEvictedByte : Nat := 32117307
def storageReadBase : Nat := 56356845749
def storageReadKeyByte : Nat := 30952533
def storageReadValueByte : Nat := 5611004
def storageRemoveBase : Nat := 53473030500
def storageRemoveKeyByte : Nat := 38220384
def storageRemoveValueByte : Nat := 11531556
def storageHasKeyBase : Nat := 54039896625
def storageHasKeyByte : Nat := 30790845
def promiseReturn : Nat := 560152386
def actionReceiptSend : Nat := 108059500000
def actionReceiptExecution : Nat := 108059500000
def dataReceiptBaseSend : Nat := 36486732312
def dataReceiptBaseExecution : Nat := 36486732312
def functionCallSend : Nat := 200000000000
def functionCallExecution : Nat := 780000000000
def functionCallByteSend : Nat := 2235934
def functionCallByteExecution : Nat := 2235934

end Protocol86Gas

def protocol86Config : Wasm.NearConfig := {
  maxRegisterLen := some (100 * 1024 * 1024)
  maxReturnLen := some (4 * 1024 * 1024)
  maxLogLen := some (16 * 1024)
  maxNumberLogs := some 100
  maxStorageKeyLen := some (4 * 1024)
  maxStorageValueLen := some (4 * 1024 * 1024)
  validAccountId := fun value => 2 ≤ value.length ∧ value.length ≤ 64
  validPublicKey := fun value => value.length = 33
}

private def storageLookup (storage : Storage) (key : Bytes) : Option Bytes :=
  (storage.find? fun entry => entry.1 == key).map (·.2)

def State.ofStorage (storage : Storage) : State := {
  storage := fun key => storageLookup storage key
  storageKeys := storage.map (·.1)
  config := protocol86Config
  sha256 := NEARLean.Crypto.SHA256.hash
}

def State.storageEntries (state : State) : Storage :=
  state.storageKeys.filterMap fun key => (state.storage key).map fun value => (key, value)

def State.beginCall (state : State) (context : Context) : State := {
  state with
  registers := fun _ => none
  context := context
  returnData := none
  logs := []
  promiseResults := state.promiseResults
  promises := []
  returnedPromise := none
  yieldResumes := []
  config := protocol86Config
}

private def registerBytes (store : Store State) (id : UInt64) : Bytes :=
  (store.host.registers id.toNat).getD []

private def memoryOrRegisterBytes
    (store : Store State) (pointer length : UInt64) : Bytes :=
  (Wasm.getMemOrReg store pointer length).getD []

private def inputCost (store : Store State) (pointer length : UInt64) : Nat :=
  if length = Wasm.u64Max then
    let count := registerBytes store pointer |>.length
    Protocol86Gas.readRegisterBase + Protocol86Gas.readRegisterByte * count
  else
    Protocol86Gas.readMemoryBase + Protocol86Gas.readMemoryByte * length.toNat

private def outputRegisterCost (count : Nat) : Nat :=
  Protocol86Gas.writeRegisterBase + Protocol86Gas.writeRegisterByte * count

private def outputMemoryCost (count : Nat) : Nat :=
  Protocol86Gas.writeMemoryBase + Protocol86Gas.writeMemoryByte * count

private def contextRegisterCost (count : Nat) : Nat :=
  Protocol86Gas.base + outputRegisterCost count

private def argI64? : List Value → Nat → Option UInt64
  | [], _ => none
  | .i64 value :: _, 0 => some value
  | _ :: _, 0 => none
  | _ :: rest, index + 1 => argI64? rest index

private def hostCost (name : String) (store : Store State) (args : List Value) : Nat :=
  let argument (index : Nat) := (argI64? args index).getD 0
  let mem (lenIndex ptrIndex : Nat) :=
    memoryOrRegisterBytes store (argument ptrIndex) (argument lenIndex)
  match name with
  | "input" => contextRegisterCost store.host.context.input.length
  | "current_account_id" => contextRegisterCost store.host.context.currentAccountId.length
  | "predecessor_account_id" => contextRegisterCost store.host.context.predecessorAccountId.length
  | "signer_account_id" => contextRegisterCost store.host.context.signerAccountId.length
  | "signer_account_pk" => contextRegisterCost store.host.context.signerAccountPk.length
  | "random_seed" => contextRegisterCost store.host.randomSeed.length
  | "attached_deposit" => Protocol86Gas.base + outputMemoryCost 16
  | "account_balance" => Protocol86Gas.base + outputMemoryCost 16
  | "account_locked_balance" => Protocol86Gas.base + outputMemoryCost 16
  | "block_index" | "block_height" | "block_timestamp" | "epoch_height" |
      "storage_usage" | "prepaid_gas" | "used_gas" => Protocol86Gas.base
  | "register_len" => Protocol86Gas.base
  | "read_register" =>
      let count := registerBytes store (argument 0) |>.length
      Protocol86Gas.base + Protocol86Gas.readRegisterBase +
        Protocol86Gas.readRegisterByte * count + outputMemoryCost count
  | "write_register" =>
      let value := mem 1 2
      Protocol86Gas.base + inputCost store (argument 2) (argument 1) + outputRegisterCost value.length
  | "value_return" => Protocol86Gas.base + inputCost store (argument 1) (argument 0)
  | "log_utf8" =>
      let value := mem 0 1
      Protocol86Gas.base + inputCost store (argument 1) (argument 0) +
        Protocol86Gas.utf8Base + Protocol86Gas.utf8Byte * value.length +
        Protocol86Gas.logBase + Protocol86Gas.logByte * value.length
  | "sha256" =>
      let value := mem 0 1
      Protocol86Gas.sha256Base + Protocol86Gas.sha256Byte * value.length +
        inputCost store (argument 1) (argument 0) + outputRegisterCost 32
  | "storage_write" =>
      let key := mem 0 1
      let value := mem 2 3
      let old := store.host.storage key
      Protocol86Gas.base + Protocol86Gas.storageWriteBase +
        inputCost store (argument 1) (argument 0) +
        inputCost store (argument 3) (argument 2) +
        Protocol86Gas.storageWriteKeyByte * key.length +
        Protocol86Gas.storageWriteValueByte * value.length +
        match old with
        | none => 0
        | some previous =>
            Protocol86Gas.storageWriteEvictedByte * previous.length +
              outputRegisterCost previous.length
  | "storage_read" =>
      let key := mem 0 1
      Protocol86Gas.base + Protocol86Gas.storageReadBase +
        inputCost store (argument 1) (argument 0) +
        Protocol86Gas.storageReadKeyByte * key.length +
        match store.host.storage key with
        | none => 0
        | some value =>
            Protocol86Gas.storageReadValueByte * value.length + outputRegisterCost value.length
  | "storage_remove" =>
      let key := mem 0 1
      Protocol86Gas.base + Protocol86Gas.storageRemoveBase +
        inputCost store (argument 1) (argument 0) +
        Protocol86Gas.storageRemoveKeyByte * key.length +
        match store.host.storage key with
        | none => 0
        | some value =>
            Protocol86Gas.storageRemoveValueByte * value.length + outputRegisterCost value.length
  | "storage_has_key" =>
      let key := mem 0 1
      Protocol86Gas.base + Protocol86Gas.storageHasKeyBase +
        inputCost store (argument 1) (argument 0) + Protocol86Gas.storageHasKeyByte * key.length
  | "promise_create" =>
      let account := mem 0 1
      let method := mem 2 3
      let callArgs := mem 4 5
      Protocol86Gas.base * 2 +
        inputCost store (argument 1) (argument 0) +
        Protocol86Gas.utf8Base + Protocol86Gas.utf8Byte * account.length +
        inputCost store (argument 3) (argument 2) +
        Protocol86Gas.utf8Base + Protocol86Gas.utf8Byte * method.length +
        inputCost store (argument 5) (argument 4) +
        Protocol86Gas.readMemoryBase + Protocol86Gas.readMemoryByte * 16 +
        Protocol86Gas.actionReceiptSend + Protocol86Gas.actionReceiptExecution +
        Protocol86Gas.functionCallSend + Protocol86Gas.functionCallExecution +
        (Protocol86Gas.functionCallByteSend + Protocol86Gas.functionCallByteExecution) *
          (method.length + callArgs.length) + (argument 7).toNat
  | "promise_then" =>
      let account := mem 1 2
      let method := mem 3 4
      let callArgs := mem 5 6
      Protocol86Gas.base * 2 +
        inputCost store (argument 2) (argument 1) +
        Protocol86Gas.utf8Base + Protocol86Gas.utf8Byte * account.length +
        inputCost store (argument 4) (argument 3) +
        Protocol86Gas.utf8Base + Protocol86Gas.utf8Byte * method.length +
        inputCost store (argument 6) (argument 5) +
        Protocol86Gas.readMemoryBase + Protocol86Gas.readMemoryByte * 16 +
        Protocol86Gas.actionReceiptSend + Protocol86Gas.actionReceiptExecution +
        Protocol86Gas.dataReceiptBaseSend + Protocol86Gas.dataReceiptBaseExecution +
        Protocol86Gas.functionCallSend + Protocol86Gas.functionCallExecution +
        (Protocol86Gas.functionCallByteSend + Protocol86Gas.functionCallByteExecution) *
          (method.length + callArgs.length) + (argument 8).toNat
  | "promise_result" =>
      let value := match store.host.promiseResults.getD (argument 0).toNat .failed with
        | .successful bytes => bytes
        | _ => []
      Protocol86Gas.base + if value.isEmpty then 0 else outputRegisterCost value.length
  | "promise_return" => Protocol86Gas.base + Protocol86Gas.promiseReturn
  | _ => Protocol86Gas.base

private def charge (store : Store State) (cost : Nat) : Except String (Store State) := do
  let used := store.host.context.usedGas.toNat
  let prepaid := store.host.context.prepaidGas.toNat
  let next := used + cost
  if next > prepaid then
    throw "GasExceeded"
  return { store with host := {
    store.host with context := { store.host.context with usedGas := UInt64.ofNat next }
  } }

private def metered (decl : ImportDecl) (function : HostFn State) : HostFn State := {
  function with invoke := fun store args =>
    match charge store (hostCost decl.name store args) with
    | .error error => .Trap store error
    | .ok charged => function.invoke charged args
}

def environmentFor (module : Module) : Except Error (HostEnv State) := do
  let resolved ← match Wasm.Near.resolveImports? module.imports with
    | some environment => pure environment
    | none => throw (.invalid "module contains an unknown or type-incompatible NEAR import")
  return { funcs := (module.imports.zip resolved.funcs).map fun pair =>
    metered pair.1 pair.2 }

def contractSource : String → Except Error String
  | "counter" => .ok (include_str "../Oracle/contracts/counter.compiled.wat")
  | "async" => .ok (include_str "../Oracle/contracts/async.compiled.wat")
  | "escrow" => .ok (include_str "../Oracle/contracts/escrow.compiled.wat")
  | "fungible_token" => .ok (include_str "../Oracle/contracts/fungible_token.compiled.wat")
  | "nft" => .ok (include_str "../Oracle/contracts/nft.compiled.wat")
  | name => .error (.invalid s!"unsupported compiled contract `{name}`")

def contractModule (contract : String) : Except Error Module := do
  decodeAndValidate (← contractSource contract)

def runContract
    (contract : String)
    (state : State)
    (context : Context)
    (method : String)
    (fuel : Nat := 100000) : Except Error (Run State) := do
  let module ← contractModule contract
  let environment ← environmentFor module
  execute module environment (state.beginCall context) method fuel

def runCounter
    (state : State)
    (method : String)
    (fuel : Nat := 100000) : Except Error (Run State) :=
  runContract "counter" state
    { prepaidGas := UInt64.ofNat 100000000000000 } method fuel

private def promiseAt? : List Wasm.NearPromise → Nat → Option Wasm.NearPromise
  | [], _ => none
  | promise :: _, 0 => some promise
  | _ :: rest, index + 1 => promiseAt? rest index

private def methodString (bytes : Bytes) : String :=
  (String.fromUTF8? ⟨bytes.toArray⟩).getD ""

private def executePromiseActions
    (contract : String)
    (context : Context)
    (state : State)
    (accountId : Bytes)
    (actions : List Wasm.PromiseAction) : Except Error (State × Bytes) := do
  match actions.find? (fun action => match action with
    | .functionCall .. => true
    | _ => false) with
  | some (.functionCall method args _ gas) =>
      let nestedContext := {
        context with
        currentAccountId := accountId
        predecessorAccountId := context.currentAccountId
        input := args
        prepaidGas := gas
        usedGas := 0
      }
      let run ← runContract contract state nestedContext (methodString method)
      match run.outcome with
      | .trap message => throw (.internal s!"promise execution trapped: {message}")
      | .success _ store => return (store.host, store.host.returnData.getD [])
  | _ => return (state, [])

private def resolvePromise
    (contract : String)
    (context : Context)
    (promises : List Wasm.NearPromise) : Nat → Nat → State → Except Error (State × Bytes)
  | 0, _, _ => throw .outOfFuel
  | fuel + 1, index, state => do
      match promiseAt? promises index with
      | none => throw (.internal "returned promise index is invalid")
      | some (.batch accountId actions) =>
          executePromiseActions contract context state accountId actions
      | some (.callback base accountId actions) =>
          let (state, value) ← resolvePromise contract context promises fuel base state
          let state := { state with promiseResults := [.successful value] }
          executePromiseActions contract context state accountId actions
      | some (.and dependencies) =>
          match dependencies.getLast? with
          | none => return (state, [])
          | some dependency => resolvePromise contract context promises fuel dependency state
      | some (.yielded _ _ _ _ _) => return (state, [])

/-- Resolve a promise returned by a benchmark call by executing each function
call and callback through the same compiled module. -/
def resolveReturnedPromise
    (contract : String)
    (context : Context)
    (state : State)
    (fuel : Nat := 32) : Except Error (State × Bytes) :=
  match state.returnedPromise with
  | none => .ok (state, state.returnData.getD [])
  | some index => resolvePromise contract context state.promises fuel index state

end NEARLean.WasmHost
