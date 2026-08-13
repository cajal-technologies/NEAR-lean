import Interpreter.Wasm.Decoder.Wat
import Interpreter.Wasm.SmallStep
import Interpreter.Wasm.Validate

/-!
# Deterministic WebAssembly execution

This module is the host-independent Talos boundary. It decodes, validates, and
executes WebAssembly while treating the host state and imported functions as
parameters. NEAR-specific host semantics live in `NEARLean.WasmHost`.
-/

namespace NEARLean.WasmExecution

open Wasm
open Wasm.SmallStep

inductive Error where
  | decode (message : String)
  | invalid (message : String)
  | missingExport (name : String)
  | initialization (message : String)
  | outOfFuel
  | internal (message : String)
  deriving BEq, Repr

inductive Outcome (α : Type) where
  | success (values : List Value) (store : Store α)
  | trap (message : String)

structure Run (α : Type) where
  outcome : Outcome α
  instructionTrace : List String

def instructionClass : Instruction → String
  | .const _ => "i32.const"
  | .constI64 _ => "i64.const"
  | .localGet _ => "local.get"
  | .localSet _ => "local.set"
  | .globalGet _ => "global.get"
  | .globalSet _ => "global.set"
  | .add => "i32.add"
  | .addI64 => "i64.add"
  | .wrapI64 => "i32.wrap_i64"
  | .store8 _ => "i32.store8"
  | .call _ => "call"
  | .callIndirect _ _ => "call_indirect"
  | .drop => "drop"
  | .unreachable => "unreachable"
  | _ => "other"

def stepClass : StepKind → String
  | .instruction instruction => instructionClass instruction
  | .host index => s!"host.{index}"
  | .administrative _ => "administrative"

def decodeAndValidate (source : String) : Except Error Module := do
  let module ← Wasm.Decoder.Wat.decode source |>.mapError Error.decode
  module.validate |>.mapError Error.invalid
  return module

def execute
    [Inhabited α]
    (module : Module)
    (host : HostEnv α)
    (initialHost : α)
    (exportName : String)
    (fuel : Nat := 100000) : Except Error (Run α) := do
  let entry ← match module.findExport exportName with
    | some entry => .ok entry
    | none => .error (.missingExport exportName)
  let store : Store α := { module.initialStore (α := α) with host := initialHost }
  let store := module.runConstGlobals fuel store host
  let store := module.runActiveSegments fuel store host
  let runtime : RuntimeEnv α := { module := module, host := host }
  let config ← initConfig runtime entry store []
    |>.mapError fun error => .initialization error.message
  let executed := runSteps fuel config
  let instructionTrace := executed.trace.map stepClass
  match executed.result with
  | .success values finalStore =>
      return { outcome := .success values finalStore.wasm, instructionTrace }
  | .trapped reason _ =>
      return { outcome := .trap reason.message, instructionTrace }
  | .outOfFuel _ => throw .outOfFuel
  | .internalError error _ => throw (.internal error.message)

def decodeValidateExecute
    [Inhabited α]
    (source : String)
    (host : HostEnv α)
    (initialHost : α)
    (exportName : String)
    (fuel : Nat := 100000) : Except Error (Run α) := do
  let module ← decodeAndValidate source
  execute module host initialHost exportName fuel

end NEARLean.WasmExecution
