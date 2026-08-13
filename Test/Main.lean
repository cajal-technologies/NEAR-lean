import NEARLean

open NEARLean

private def assertEqual [BEq α] [Repr α] (expected actual : α) : IO Unit :=
  if expected == actual then
    pure ()
  else
    throw <| IO.userError s!"expected {repr expected}, got {repr actual}"

def main : IO Unit := do
  assertEqual "abstract" (SemanticsLayer.label .abstract)
  assertEqual "concrete-compatibility" (SemanticsLayer.label .concreteCompatibility)
  IO.println "2 tests passed"
