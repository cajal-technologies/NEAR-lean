# Semantic architecture

NEAR Lean maintains two deliberately separate semantic layers.

## Abstract semantics

The abstract layer is a mathematical state-transition system designed for
contract specifications and proofs. It uses proof-friendly identifiers, maps,
numbers, and explicit invariants. Serialization, trie layout, byte encodings,
protocol migrations, and VM implementation details do not belong in its public
verification API.

## Concrete compatibility semantics

The concrete layer is indexed by protocol version and models externally
observable nearcore behavior: encodings, hashes, gas schedules, receipt order,
WASM execution, trie keys, state roots, and migrations. Differential and replay
tests exercise this layer against the pinned nearcore oracle.

## Refinement boundary

An explicit abstraction function will connect concrete states and observations to
the abstract layer. Milestone 11 requires refinement results of the form:

```text
observe (concreteStep state input) =
  abstractStep (abstract state) input
```

Until such a result exists for a feature, concrete compatibility must not be
inferred from an abstract proof. Conversely, contract proofs should not import
concrete runtime internals. `NEARLean.SemanticsLayer` gives this boundary a stable
name from the first milestone.
