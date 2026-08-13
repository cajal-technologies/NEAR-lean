# Semantic architecture

NEAR Lean maintains two deliberately separate semantic layers.

## Abstract semantics

The abstract layer is a mathematical state-transition system designed for
contract specifications and proofs. It uses proof-friendly identifiers, maps,
numbers, and explicit invariants. Serialization, trie layout, byte encodings,
protocol migrations, and VM implementation details do not belong in its public
verification API.

`NEARLean.AbstractKernel` is the Milestone 1 implementation of this layer. It
defines finite association-list state, executable invariant checks, and the total
transition interface:

```lean
step :
  RuntimeConfig →
  WorldState →
  Input →
  WorldState × Except RuntimeError Output
```

At Milestone 3 the same interface executes four abstract actions. Account creation
is represented as an authorized creator plus an initial balance, matching the
observable effect of nearcore's create, transfer, and access-key action sequence.
The kernel commits a candidate state only after checking `WorldState.WellFormed`;
execution and validation failures return the unchanged pre-state. `Transition`
remains defined by equality with `step`, so there is no separately maintained
relational semantics.

`NEARLean.Sandbox` exposes `NearChain.init`, `deploy`, `call`, `view`, transfers,
account creation, and state queries. The temporary native backend contains a
counter and simple escrow. It is synchronous and does not model receipts, promises,
WASM, host functions, or near-workspaces RPC.

## Concrete compatibility semantics

The concrete layer is indexed by protocol version and models externally
observable nearcore behavior: encodings, hashes, gas schedules, receipt order,
WASM execution, trie keys, state roots, and migrations. Differential and replay
tests exercise this layer against the pinned nearcore oracle.

`Oracle.Differential` defines schema version 1 of the canonical boundary. The
Lean executable and the Node adapter consume the same genesis, actions, baseline,
protocol version, and seed. The Milestone 3 canonicalizer reaches L3 for account
creation, transfers, counter deployment and calls, and insufficient-balance
failures. It waits for nearcore finality and projects transaction gas burn out of
balances because the abstract kernel does not model gas economics until Milestone
7. That projection is explicit adapter code, not a claim about exact economics.

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
