import NEARLean.WasmHost
import NEARLean.Sandbox

namespace NEARLean.M10Validation

open NEARLean.WasmExecution
open NEARLean.WasmHost

private def require (condition : Bool) (message : String) : Except String Unit :=
  if condition then .ok () else .error message

private def run
    (contract method : String)
    (state : State)
    (context : Context) : Except String State := do
  let execution ← runContract contract state context method
    |>.mapError fun error => s!"{repr error}"
  match execution.outcome with
  | .trap message => throw message
  | .success _ store => return store.host

private def context (input : String := "") : Context := {
  currentAccountId := "contract.bench".toUTF8.toList
  predecessorAccountId := "caller.bench".toUTF8.toList
  signerAccountId := "caller.bench".toUTF8.toList
  input := input.toUTF8.toList
  attachedDeposit := 9
  prepaidGas := UInt64.ofNat 100000000000000
}

private structure HostCase where
  name : String
  module : Wasm.Module
  function : Wasm.HostFn State

private def hostCases : Except String (List HostCase) := do
  let mut cases : List HostCase := []
  for contract in ["counter", "escrow", "fungible_token", "nft", "async"] do
    let module ← contractModule contract |>.mapError fun error => s!"{repr error}"
    let environment ← environmentFor module |>.mapError fun error => s!"{repr error}"
    for (decl, function) in module.imports.zip environment.funcs do
      if !(cases.any fun hostCase => hostCase.name == decl.name) then
        cases := cases ++ [{ name := decl.name, module, function }]
  return cases

private def hostArguments : String → List Wasm.Value
  | "input" | "current_account_id" | "predecessor_account_id" |
      "signer_account_id" => [.i64 0]
  | "attached_deposit" => [.i64 1088]
  | "register_len" => [.i64 0]
  | "read_register" => [.i64 0, .i64 1088]
  | "value_return" | "log_utf8" => [.i64 1, .i64 1057]
  | "sha256" => [.i64 1, .i64 1057, .i64 1]
  | "storage_write" => [.i64 1, .i64 1056, .i64 1, .i64 1057, .i64 1]
  | "storage_read" | "storage_remove" => [.i64 1, .i64 1056, .i64 1]
  | "promise_create" =>
      [.i64 12, .i64 1024, .i64 4, .i64 1040, .i64 1, .i64 1057,
        .i64 1072, .i64 1]
  | "promise_then" =>
      [.i64 0, .i64 12, .i64 1024, .i64 4, .i64 1040, .i64 1, .i64 1057,
        .i64 1072, .i64 1]
  | "promise_result" => [.i64 0, .i64 1]
  | "promise_return" => [.i64 0]
  | _ => []

private def hostStore (hostCase : HostCase) (prepaidGas : Nat) : Wasm.Store State :=
  let initial := (State.ofStorage [([1], [2])]).beginCall {
    context with prepaidGas := UInt64.ofNat prepaidGas
  }
  let host : State := {
    initial with
    registers := fun id => if id = 0 then some [1] else none
    promiseResults := [.successful [7]]
    promises := [.batch "target.bench".toUTF8.toList []]
  }
  let store : Wasm.Store State := {
    (hostCase.module.initialStore (α := State)) with host
  }
  let memory := store.mem
    |>.writeBytes 1024 "target.bench".toUTF8.toList
    |>.writeBytes 1040 "echo".toUTF8.toList
    |>.writeBytes 1056 [1, 2]
    |>.writeBytes 1072 (List.replicate 16 0)
  { store with mem := memory }

private def successfulHostStore
    (name : String) : Wasm.HostResult State → Except String (Wasm.Store State)
  | .Return _ store => .ok store
  | .Trap _ message => .error s!"{name} valid invocation trapped: {message}"
  | _ => .error s!"{name} valid invocation threw"

private def validateHostFunction (hostCase : HostCase) : Except String Unit := do
  let arguments := hostArguments hostCase.name
  require (!arguments.isEmpty) s!"missing test arguments for {hostCase.name}"
  let high := hostStore hostCase 100000000000000
  let charged ← successfulHostStore hostCase.name (hostCase.function.invoke high arguments)
  let cost := charged.host.context.usedGas.toNat
  require (cost > 0) s!"{hostCase.name} did not charge gas"
  let exact := hostStore hostCase cost
  let _ ← successfulHostStore hostCase.name (hostCase.function.invoke exact arguments)
  let low := hostStore hostCase (cost - 1)
  match hostCase.function.invoke low arguments with
  | .Trap _ "GasExceeded" => pure ()
  | _ => throw s!"{hostCase.name} did not trap one unit below its gas boundary"
  match hostCase.function.invoke high [] with
  | .Trap _ message =>
      require (message != "GasExceeded") s!"{hostCase.name} malformed call reported gas error"
  | _ => throw s!"{hostCase.name} accepted malformed arguments"

private def validateHostFunctions : Except String Nat := do
  let cases ← hostCases
  require (cases.length == 17) "host corpus did not contain 17 distinct imports"
  for hostCase in cases do
    validateHostFunction hostCase
  return cases.length

private def validateBenchmarks : Except String Unit := do
  let counter ← run "counter" "init" (State.ofStorage []) context
  let counter ← run "counter" "increment" counter context
  require (counter.returnData == some [0]) "counter did not execute compiled increment"
  let escrow ← run "escrow" "deposit" (State.ofStorage []) context
  require (escrow.returnData.map List.length == some 16) "escrow deposit return mismatch"
  let fungible ← run "fungible_token" "mint" (State.ofStorage []) (context "alice")
  require (fungible.storageKeys.length == 1) "fungible-token mint did not write storage"
  let nft ← run "nft" "nft_mint" (State.ofStorage []) (context "token-1")
  require (nft.returnData.map List.length == some 32) "NFT SHA-256 return mismatch"
  let asyncState ← run "async" "call_then" (State.ofStorage [])
    (context "contract.bench")
  let (_, asyncValue) ← resolveReturnedPromise "async" (context "contract.bench") asyncState
    |>.mapError fun error => s!"{repr error}"
  require (asyncValue == [7]) "compiled promise callback did not resolve"

private def validateErrorsAndGas : Except String Unit := do
  let module ← contractModule "async" |>.mapError fun error => s!"{repr error}"
  let environment ← environmentFor module |>.mapError fun error => s!"{repr error}"
  let initial := State.ofStorage []
  let lowGas : Context := { context with prepaidGas := 1 }
  let execution ← NEARLean.WasmExecution.execute module environment
    (initial.beginCall lowGas) "echo"
    |>.mapError fun error => s!"{repr error}"
  match execution.outcome with
  | .success .. => throw "one-unit gas boundary did not trap"
  | .trap message => require (message == "GasExceeded") "wrong gas boundary error"
  match runContract "async" initial context "missing" with
  | .error (.missingExport _) => pure ()
  | _ => throw "missing method did not return the exact resolution error"
  let charged ← run "async" "echo" initial context
  require (charged.context.usedGas.toNat == 2878432644)
    "value_return did not charge the exact protocol-86 host cost"
  require (charged.context.usedGas ≤ charged.context.prepaidGas) "gas exceeded prepaid amount"

private def validateHashes : Except String Unit := do
  let expected : List Nat := [186, 120, 22, 191, 143, 1, 207, 234, 65, 65, 64, 222,
    93, 174, 34, 35, 176, 3, 97, 163, 150, 23, 122, 156, 180, 16, 255, 97,
    242, 0, 21, 173]
  let actual := NEARLean.Crypto.SHA256.hash "abc".toUTF8.toList |>.map UInt8.toNat
  require (actual == expected) "SHA-256 known-answer test failed"

private def validateRefinement : Except String Unit := do
  let genesis : List (NEARLean.AccountId × NEARLean.Account) := [
    ([1], { NEARLean.Account.initial with balance := 100 }),
    ([2], { NEARLean.Account.initial with balance := 10 })]
  let chain ← NEARLean.NearChain.init NEARLean.RuntimeConfig.default genesis
    |>.mapError fun error => s!"{repr error}"
  let (chain, deployed) := chain.deploy [1] [2] NEARLean.NativeContract.counterId
  let _ ← deployed.mapError fun error => s!"{repr error}"
  let (_, nativeCounter) := chain.call [1] [2] NEARLean.NativeMethod.increment [] 0 100
  let nativeCounter ← nativeCounter.mapError fun error => s!"{repr error}"
  let compiledCounter ← run "counter" "init" (State.ofStorage []) context
  let compiledCounter ← run "counter" "increment" compiledCounter context
  require (compiledCounter.returnData == some nativeCounter.returnValue)
    "native and WASM counter observations do not refine"
  let asyncGenesis : List (NEARLean.AccountId × NEARLean.Account) := [
    ([1], { NEARLean.Account.initial with balance := 100 }),
    ([2], { NEARLean.Account.initial with balance := 10 })]
  let asyncChain ← NEARLean.NearChain.init NEARLean.RuntimeConfig.default asyncGenesis
    |>.mapError fun error => s!"{repr error}"
  let (asyncChain, deployed) := asyncChain.deploy [1] [2] NEARLean.NativeContract.asyncId
  let _ ← deployed.mapError fun error => s!"{repr error}"
  let (_, nativeEcho) := asyncChain.call [1] [2] NEARLean.NativeMethod.echo [] 0 100
  let nativeEcho ← nativeEcho.mapError fun error => s!"{repr error}"
  let compiledEcho ← run "async" "echo" (State.ofStorage []) context
  require (compiledEcho.returnData == some nativeEcho.returnValue)
    "native and WASM async observations do not refine"

private def generatedCalls (count : Nat) : Except String Unit := do
  let module ← contractModule "async" |>.mapError fun error => s!"{repr error}"
  let environment ← environmentFor module |>.mapError fun error => s!"{repr error}"
  let initial := State.ofStorage []
  let final ← (List.range count).foldlM (fun state _ => do
    let execution ← NEARLean.WasmExecution.execute module environment
      (state.beginCall context) "echo"
      |>.mapError fun error => s!"{repr error}"
    match execution.outcome with
    | .trap message => throw message
    | .success _ store =>
        require (store.host.returnData == some [7]) "generated echo return mismatch"
        return store.host) initial
  require (final.returnData == some [7]) "generated campaign lost final return"

def validateAll : Except String (Nat × Nat) := do
  let count := 10000
  validateBenchmarks
  let hostFunctionCount ← validateHostFunctions
  validateErrorsAndGas
  validateHashes
  validateRefinement
  generatedCalls count
  return (count, hostFunctionCount)

end NEARLean.M10Validation

def main : IO UInt32 := do
  match NEARLean.M10Validation.validateAll with
  | .error message => throw <| IO.userError message
  | .ok (count, hostFunctionCount) =>
      IO.println ("{\"schemaVersion\":1,\"compiledCalls\":" ++ toString count ++
        ",\"benchmarkContracts\":5,\"hostFunctionCount\":" ++ toString hostFunctionCount ++
        ",\"hostBoundaryTests\":true,\"hostErrorTests\":true," ++
        "\"hostGasTests\":true,\"promiseCallbacks\":true,\"sha256KnownAnswer\":true," ++
        "\"nativeWasmRefinement\":true}")
      return 0
