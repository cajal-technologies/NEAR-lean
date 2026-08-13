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

The same interface executes four abstract actions. Account creation
is represented as an authorized creator plus an initial balance, matching the
observable effect of nearcore's create, transfer, and access-key action sequence.
The kernel commits a candidate state only after checking `WorldState.WellFormed`;
execution and validation failures return the unchanged pre-state. `Transition`
remains defined by equality with `step`, so there is no separately maintained
relational semantics.

`NEARLean.Sandbox` exposes `NearChain.init`, `deploy`, `call`, `view`, transfers,
account creation, and state queries. The temporary native backend contains a
counter and simple escrow. It is synchronous and remains separate from receipts,
promises, the concrete WASM machine, and near-workspaces RPC.

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

## WebAssembly and host boundary

`NEARLean.Wasm` is a host-polymorphic wrapper around pinned Talos. It decodes and
validates the reproducibly rendered WAT, resolves exports, initializes memory,
globals, data segments, and tables, then executes the deterministic small-step
machine with an explicit fuel cap. It has no NEAR-specific state or import
behavior.

`NEARLean.WasmHost` is the separate NEAR adapter. At Milestone 9 it resolves only
the six imports used by the compiled counter: storage read/write, register length
and read, value return, and UTF-8 logging. The checked-in `counter.wasm` is the
single artifact consumed by nearcore; `counter.compiled.wat` is a reproducible
`wasm-tools print` rendering of those bytes consumed by Talos. The L4 fixture sets
`wasmMode`, which prevents the Lean canonical runner from using the native counter
implementation for deployment, calls, storage, logs, returns, and traps.

## Transactions and receipts

`NEARLean.Receipts` adds an abstract asynchronous state machine without changing
the synchronous action kernel. Transactions create root action receipts. Action
receipts contain actions, output data receivers, and input data dependencies;
data receipts supply `PromiseResult` values. A receipt with missing inputs is
postponed, and processing a matching data receipt may execute it immediately.

Receipt identifiers are fresh natural numbers in this proof layer. The L4 oracle
maps nearcore hashes to those numbers by transaction-root and child-creation order,
then compares executor, child identities, status, return bytes, and execution
order. Economic refund receipts are intentionally omitted until Milestone 7.
The current cross-contract program covers `promise_create`, `promise_then`, and
`promise_return` with one successful callback dependency.

## Refinement boundary

`NEARLean.Concrete.State` now provides the explicit abstraction function and the
Milestone 11 refinement result:

```text
observe (concreteStep state input) =
  abstractStep (abstract state) input
```

The concrete wrapper reuses the abstract transition and independently projects
exact Borsh records and near-store-compatible roots. Contract proofs still do not
import concrete runtime internals. See `docs/CONCRETE_SEMANTICS.md` for its scoped
L7 corpus and remaining adapters.

`NEARLean.Concrete.Historical` extends only the import boundary: it decodes real
block/chunk headers and preserves transaction, receipt, outcome, and state-change
JSON for the historical tools. It does not enter the verification API or promote
imported root commitments into a theorem about independent historical execution.
