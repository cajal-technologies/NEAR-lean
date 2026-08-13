/-!
# Semantic layers

The project keeps proof-oriented semantics separate from byte-accurate nearcore
compatibility semantics. This module names that boundary before either layer is
implemented, so future APIs cannot accidentally blur the distinction.
-/

namespace NEARLean

/-- The two semantic layers maintained by the project. -/
inductive SemanticsLayer where
  /-- Mathematical semantics optimized for specifications and proofs. -/
  | abstract
  /-- Protocol-versioned semantics optimized for nearcore compatibility. -/
  | concreteCompatibility
  deriving BEq, DecidableEq, Repr

/-- A short, stable label suitable for reports and serialized diagnostics. -/
def SemanticsLayer.label : SemanticsLayer → String
  | .abstract => "abstract"
  | .concreteCompatibility => "concrete-compatibility"

/-- The two semantic layers are definitionally distinct. -/
theorem SemanticsLayer.abstract_ne_concrete :
    SemanticsLayer.abstract ≠ SemanticsLayer.concreteCompatibility := by
  decide

end NEARLean
