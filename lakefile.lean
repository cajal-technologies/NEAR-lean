import Lake

open Lake DSL

require CodeLib from git
  "https://github.com/cajal-technologies/talos.git" @
  "87336df09b41d819c670be99860481573fd00055" / "codelib"

package «near-lean» where
  version := v!"0.0.0"
  leanOptions := #[⟨`warningAsError, true⟩]

@[default_target]
lean_lib NEARLean

lean_lib Oracle

@[test_driver]
lean_exe nearLeanTests where
  root := `Test.Main

lean_exe nearLeanOracle where
  root := `Oracle.LeanRunner

lean_exe wasmValidation where
  root := `Oracle.WasmValidation

lean_exe m10Validation where
  root := `Oracle.M10Validation
