import Oracle.Differential

open NEARLean

def main (args : List String) : IO UInt32 := do
  let paths ← match args with
    | [] =>
        IO.eprintln "usage: nearLeanOracle TRACE.json..."
        return 2
    | paths => pure paths
  let runs ← paths.mapM fun path => do
    let source ← IO.FS.readFile ⟨path⟩
    match CanonicalTrace.parse source >>= CanonicalTrace.run with
    | .error message => throw <| IO.userError s!"{path}: {message}"
    | .ok run => pure run
  if runs.length = 1 then
    match runs with
    | [run] => IO.println run.json
    | _ =>
        IO.eprintln "unreachable runner state"
        return 1
  else
    IO.println <| Lean.Json.pretty (Lean.toJson runs)
  return 0
