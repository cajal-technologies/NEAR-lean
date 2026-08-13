import Lean.Data.Json
import NEARLean.WasmHost

namespace NEARLean.WasmValidation

open Lean
open NEARLean.WasmExecution

structure MutationResult where
  name : String
  killed : Bool
  deriving ToJson

structure CoverageEntry where
  name : String
  count : Nat
  deriving ToJson

structure Report where
  schemaVersion : Nat
  talosCommit : String
  wasmVersion : String
  instructionCoverage : List CoverageEntry
  mutations : List MutationResult
  mutationScore : Nat
  deriving ToJson

private def rejects (source : String) : Bool :=
  match decodeAndValidate source with
  | .error _ => true
  | .ok _ => false

private def traps (source exportName : String) : Bool :=
  match decodeValidateExecute source (α := Unit) {} () exportName 1000 with
  | .ok { outcome := .trap _, .. } => true
  | _ => false

private def exhaustsFuel (source exportName : String) : Bool :=
  match decodeValidateExecute source (α := Unit) {} () exportName 20 with
  | .error .outOfFuel => true
  | _ => false

private def hostlessTrace
    (source exportName : String)
    (expected : List Wasm.Value) : Except Error (List String) := do
  let run ← decodeValidateExecute source (α := Unit) {} () exportName 1000
  match run.outcome with
  | .success values _ =>
      if values = expected then return run.instructionTrace
      throw (.internal s!"unexpected values from `{exportName}`")
  | .trap message => throw (.internal message)

private def counterEvidence : Except Error (List String × WasmHost.State) := do
  let initialized ← WasmHost.runCounter {} "init"
  let (state, trace) ← match initialized.outcome with
    | .success _ store => pure (store.host, initialized.instructionTrace)
    | .trap message => throw (.internal message)
  let incremented ← WasmHost.runCounter state "increment"
  let (state, trace) ← match incremented.outcome with
    | .success _ store => pure (store.host, trace ++ incremented.instructionTrace)
    | .trap message => throw (.internal message)
  let read ← WasmHost.runCounter state "get"
  let (state, trace) ← match read.outcome with
    | .success _ store => pure (store.host, trace ++ read.instructionTrace)
    | .trap message => throw (.internal message)
  let trapped ← WasmHost.runCounter state "trap"
  let trace ← match trapped.outcome with
  | .trap _ => pure (trace ++ trapped.instructionTrace)
  | .success _ _ => throw (.internal "unreachable mutation was not detected")
  let callTrace ← hostlessTrace
    "(module (func $value (result i32) i32.const 7) (func (export \"run\") (result i32) call $value))"
    "run" [.i32 7]
  let globalTrace ← hostlessTrace
    "(module (global i32 (i32.const 9)) (func (export \"run\") (result i32) global.get 0))"
    "run" [.i32 9]
  let tableTrace ← hostlessTrace
    "(module (type $t (func (result i32))) (table 1 funcref) (elem (i32.const 0) $value) (func $value (result i32) i32.const 11) (func (export \"run\") (result i32) i32.const 0 call_indirect (type $t)))"
    "run" [.i32 11]
  return (trace ++ callTrace ++ globalTrace ++ tableTrace, state)

private def coverage (trace : List String) : List CoverageEntry :=
  trace.eraseDups.mergeSort (· < ·) |>.map fun name => { name, count := trace.count name }

private def mutations (counterState : WasmHost.State) : List MutationResult := [
  { name := "empty-module", killed := rejects "" },
  { name := "truncated-module", killed := rejects "(module" },
  { name := "wrong-top-level", killed := rejects "(func)" },
  { name := "local-index-off-by-one",
    killed := rejects "(module (func (export \"bad\") local.get 0))" },
  { name := "unknown-export-index",
    killed := rejects "(module (export \"bad\" (func 1)) (func))" },
  { name := "unreachable-as-nop",
    killed := traps "(module (func (export \"run\") unreachable))" "run" },
  { name := "divide-by-zero-not-trap",
    killed := traps
      "(module (func (export \"run\") (result i32) i32.const 1 i32.const 0 i32.div_s))"
      "run" },
  { name := "memory-boundary-off-by-one",
    killed := traps
      "(module (memory 1) (func (export \"run\") (result i32) i32.const 65536 i32.load))"
      "run" },
  { name := "missing-export-fallback",
    killed := match WasmHost.runCounter counterState "missing" with
      | .error (.missingExport _) => true
      | _ => false },
  { name := "fuel-cap-ignored",
    killed := exhaustsFuel "(module (func (export \"run\") loop br 0 end))" "run" },
  { name := "counter-storage-write-dropped",
    killed := counterState.storage == [([1], [0])] },
  { name := "counter-return-dropped",
    killed := counterState.returnValue == [0] }
]

def report : Except Error Report := do
  let (trace, counterState) ← counterEvidence
  let mutationResults := mutations counterState
  let killed := mutationResults.countP (·.killed)
  return {
    schemaVersion := 1
    talosCommit := "87336df09b41d819c670be99860481573fd00055"
    wasmVersion := "WebAssembly Core 1.0 (MVP)"
    instructionCoverage := coverage trace
    mutations := mutationResults
    mutationScore := 100 * killed / mutationResults.length
  }

end NEARLean.WasmValidation

def main : IO UInt32 := do
  match NEARLean.WasmValidation.report with
  | .error error =>
      IO.eprintln s!"WASM validation failed: {repr error}"
      return 1
  | .ok report =>
      IO.println <| Lean.Json.pretty (Lean.toJson report)
      return 0
