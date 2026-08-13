import NEARLean.Concrete.Historical

namespace NEARLean.M12Validation

open NEARLean.Concrete.Historical

private def require (condition : Bool) (message : String) : Except String Unit :=
  if condition then .ok () else .error message

def validate (source : String) : Except String Fixture := do
  let fixture ← importFixture source
  require fixture.wellFormed "historical fixture is not well formed"
  require (fixture.blocks.size == 2) "historical block importer sample differs"
  require (fixture.samples.any fun chunk => !chunk.transactions.isEmpty)
    "historical transaction importer sample is empty"
  require (fixture.samples.any fun chunk => !chunk.receipts.isEmpty)
    "historical receipt importer sample is empty"
  require (fixture.samples.any fun chunk => !chunk.outcomes.isEmpty)
    "historical outcome importer sample is empty"
  require (fixture.samples.any fun chunk => !chunk.stateChanges.isEmpty)
    "historical state-change importer sample is empty"
  require (fixture.samples.all fun chunk =>
    chunk.importedPreStateRoot == chunk.header.inputStateRoot)
    "historical pre-state-root import differs"
  pure fixture

end NEARLean.M12Validation

def main : IO UInt32 := do
  let source ← IO.FS.readFile "replay/sample.json"
  match NEARLean.M12Validation.validate source with
  | .error message => throw <| IO.userError message
  | .ok fixture =>
      IO.println ("{\"schemaVersion\":1,\"blocks\":" ++ toString fixture.blocks.size ++
        ",\"chunks\":" ++ toString fixture.samples.size ++ ",\"importKinds\":5}")
      return 0
