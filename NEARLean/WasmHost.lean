import NEARLean.Wasm

/-!
# Minimal NEAR host for the compiled counter

Only the six imports used by the Milestone 9 counter are implemented here.
The WebAssembly machine remains host-polymorphic in `NEARLean.Wasm`.
-/

namespace NEARLean.WasmHost

open Wasm
open NEARLean.WasmExecution

abbrev Bytes := List UInt8
abbrev Storage := List (Bytes × Bytes)
abbrev Registers := List (UInt64 × Bytes)

structure State where
  storage : Storage := []
  registers : Registers := []
  returnValue : Bytes := []
  logs : List Bytes := []
  deriving Inhabited, Repr

def State.beginCall (state : State) : State :=
  { state with registers := [], returnValue := [], logs := [] }

private def lookupStorage (storage : Storage) (key : Bytes) : Option Bytes :=
  (storage.find? fun entry => entry.1 == key).map (·.2)

private def setStorage (storage : Storage) (key value : Bytes) : Storage :=
  storage.filter (fun entry => entry.1 != key) ++ [(key, value)]

private def lookupRegister (registers : Registers) (id : UInt64) : Option Bytes :=
  (registers.find? fun entry => entry.1 == id).map (·.2)

private def setRegister (registers : Registers) (id : UInt64) (value : Bytes) : Registers :=
  registers.filter (fun entry => entry.1 != id) ++ [(id, value)]

private def readMemory (store : Store State) (length pointer : UInt64) : Bytes :=
  store.mem.readBytes pointer.toNat length.toNat

def storageRead : HostFn State := {
  params := [.i64, .i64, .i64]
  results := [.i64]
  invoke := fun store arguments => match arguments with
    | [.i64 length, .i64 pointer, .i64 registerId] =>
        let key := readMemory store length pointer
        match lookupStorage store.host.storage key with
        | none => .Return [.i64 0] store
        | some value =>
            let host := { store.host with
              registers := setRegister store.host.registers registerId value }
            .Return [.i64 1] { store with host := host }
    | _ => .Trap store "storage_read: bad arguments"
}

def storageWrite : HostFn State := {
  params := [.i64, .i64, .i64, .i64, .i64]
  results := [.i64]
  invoke := fun store arguments => match arguments with
    | [.i64 keyLength, .i64 keyPointer, .i64 valueLength, .i64 valuePointer,
        .i64 registerId] =>
        let key := readMemory store keyLength keyPointer
        let value := readMemory store valueLength valuePointer
        let previous := lookupStorage store.host.storage key
        let registers := match previous with
          | none => store.host.registers
          | some old => setRegister store.host.registers registerId old
        let host := { store.host with
          storage := setStorage store.host.storage key value
          registers := registers }
        .Return [.i64 (if previous.isSome then 1 else 0)] { store with host := host }
    | _ => .Trap store "storage_write: bad arguments"
}

def registerLen : HostFn State := {
  params := [.i64]
  results := [.i64]
  invoke := fun store arguments => match arguments with
    | [.i64 registerId] =>
        let length := match lookupRegister store.host.registers registerId with
          | some value => UInt64.ofNat value.length
          | none => (18446744073709551615 : UInt64)
        .Return [.i64 length] store
    | _ => .Trap store "register_len: bad arguments"
}

def readRegister : HostFn State := {
  params := [.i64, .i64]
  results := []
  invoke := fun store arguments => match arguments with
    | [.i64 registerId, .i64 pointer] =>
        match lookupRegister store.host.registers registerId with
        | none => .Trap store "read_register: missing register"
        | some value =>
            .Return [] { store with mem := store.mem.writeBytes pointer.toNat value }
    | _ => .Trap store "read_register: bad arguments"
}

def valueReturn : HostFn State := {
  params := [.i64, .i64]
  results := []
  invoke := fun store arguments => match arguments with
    | [.i64 length, .i64 pointer] =>
        let host := { store.host with returnValue := readMemory store length pointer }
        .Return [] { store with host := host }
    | _ => .Trap store "value_return: bad arguments"
}

def logUtf8 : HostFn State := {
  params := [.i64, .i64]
  results := []
  invoke := fun store arguments => match arguments with
    | [.i64 length, .i64 pointer] =>
        let message := readMemory store length pointer
        let host := { store.host with logs := store.host.logs ++ [message] }
        .Return [] { store with host := host }
    | _ => .Trap store "log_utf8: bad arguments"
}

def environment : HostEnv State := {
  funcs := [storageRead, storageWrite, registerLen, readRegister, valueReturn, logUtf8]
}

def counterSource : String := include_str "../Oracle/contracts/counter.compiled.wat"

def counterModule : Except Error Module := do
  let module ← decodeAndValidate counterSource
  let expected := ["storage_read", "storage_write", "register_len",
    "read_register", "value_return", "log_utf8"]
  if module.imports.map (·.name) = expected ∧ module.imports.all (·.«module» = "env") then
    return module
  throw (.invalid "compiled counter imports do not match the Milestone 9 host surface")

def runCounter
    (state : State)
    (method : String)
    (fuel : Nat := 100000) : Except Error (Run State) := do
  let module ← counterModule
  execute module environment state.beginCall method fuel

end NEARLean.WasmHost
