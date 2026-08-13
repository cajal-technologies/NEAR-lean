import Lake

open Lake DSL

package «near-lean» where
  version := v!"0.0.0"
  leanOptions := #[⟨`warningAsError, true⟩]

@[default_target]
lean_lib NEARLean

@[test_driver]
lean_exe nearLeanTests where
  root := `Test.Main
