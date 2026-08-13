This project is meant to be developed by AI agents, so it is important to have a clear measure of progress
at every stage, here we write a guideline.



-- Codex output verbatim below

Yes. I would add four major categories to your list:

1. Protocol coverage.
2. Strength and trustworthiness of the proofs.
3. Resistance of the test suite to plausible bugs.
4. Usability for writing contract specifications.

The central principle should be: **do not use one aggregate “percent complete.”** Autonomous agents will naturally optimize whatever number you expose. A small dashboard of independent metrics is much harder to game.

## 1. Define exactly what “same behavior” means

Differential tests should compare progressively stronger observations:

| Level | Compared with nearcore |
|---|---|
| L1 | Success/failure and error category |
| L2 | Return value and logs |
| L3 | Account balances and contract storage |
| L4 | Generated receipts, dependencies, and execution order |
| L5 | Gas burnt, gas used, refunds, and storage usage |
| L6 | Serialized outcomes and state changes |
| L7 | Exact trie/state root |

L3 is already useful for contract verification. L7 requires exact serialization, hashing, trie layout, migrations, sharding, and protocol-version behavior.

This makes “differential test passed” unambiguous. A test might currently pass through L4 but not yet L5.

NEAR’s runtime turns transactions into receipts, processes those receipts in a defined order, and performs balance consistency checks, so receipt behavior and accounting must be first-class comparison targets—not just final storage. [Runtime processing](https://nomicon.io/RuntimeSpec/Components/RuntimeCrate.html), [chunk application order](https://nomicon.io/RuntimeSpec/ApplyingChunk).

## 2. Protocol feature coverage matrix

Maintain a machine-readable manifest with one row for every semantic feature:

```text
feature
protocol-version range
nearcore source/reference
implemented
executable tests
differential tests
proof obligations
known deviations
```

Feature groups should include:

- Action types.
- Receipt and promise behavior.
- Host functions.
- WASM instructions and validation rules.
- Errors and rollback cases.
- Gas charging rules.
- Storage accounting.
- Account-ID rules.
- Protocol-version gates.
- Sharding and receipt routing.
- Runtime migrations.

Useful metrics:

- Percentage of features implemented.
- Percentage with differential coverage.
- Percentage with preservation theorems.
- Number of undocumented deviations.
- Number of supported protocol versions.

Weight features by importance rather than counting them equally. Implementing ten trivial host functions should not look better than implementing promise callbacks correctly.

A feature should only be called “complete” when it has:

1. A pinned nearcore reference.
2. An executable implementation.
3. Positive and negative tests.
4. Differential tests.
5. Relevant invariant proofs.
6. No undocumented divergence.

Pinning protocol versions is essential because nearcore releases introduce observable runtime changes, including gas limits, receipt ordering, refunds, and account behavior. [nearcore releases](https://github.com/near/nearcore/releases).

## 3. Historical replay, but as a ladder

Full-history replay is an excellent eventual gold standard, but a poor early metric. Most early blocks will not exercise the difficult corners, and exact roots require support for every historical protocol version and migration.

Use these milestones:

- Replay a synthetic single-shard chain for 1,000 blocks.
- Replay selected real blocks from one protocol era.
- Replay blocks containing specific action types and contract behaviors.
- Replay across a protocol upgrade boundary.
- Replay a contiguous 10,000-block mainnet interval.
- Replay one complete protocol era.
- Replay genesis to a selected checkpoint.
- Eventually replay genesis to head.

Track three separate values:

```text
highest contiguous replay interval
stratified sampled-block pass rate
number of protocol upgrade boundaries crossed
```

The sampled corpus should deliberately include:

- Failed transactions.
- Out-of-gas calls.
- Cross-contract callbacks.
- Account creation/deletion.
- Contract deployment and upgrade.
- Refunds.
- Delayed and postponed receipts.
- High-storage calls.
- Shard-boundary traffic.

“99% of random blocks pass” is much less informative than “every semantic category has at least 1,000 passing examples.”

## 4. Generated differential testing

Build a deterministic trace generator:

```lean
Generator → GenesisState → List BlockInput
```

Execute each trace through Lean and pinned nearcore, then compare at the strongest currently supported level.

Metrics:

- Number of generated traces.
- Total actions and receipts executed.
- Maximum trace length.
- Distribution across semantic features.
- Differential pass rate by feature.
- Smallest remaining counterexample.
- Fuzz executions per second.

Every failure should be automatically minimized into a permanent regression fixture. Record:

- Random seed.
- Protocol version.
- nearcore commit.
- Genesis state.
- Inputs.
- First differing observation.

For autonomous development, keep both:

- A visible corpus for fast iteration.
- A held-out corpus or periodically regenerated seeds for detecting overfitting.

## 5. Mutation score

This may be the best additional metric for an AI-built system.

Deliberately introduce plausible semantic bugs:

- Confuse `signer_id` and `predecessor_id`.
- Execute receipts in the wrong order.
- Commit storage after a failed call.
- Omit a deposit refund.
- Charge gas one step too early or too late.
- Execute a callback before all promise results arrive.
- Reuse a receipt identifier.
- Expose mutated state through a view call.

Then measure how many mutations are caught by:

- Lean proofs.
- Unit/property tests.
- Differential tests.
- Historical replay.

Target something like a **95%+ semantic mutation score** for completed features. This measures whether the verification apparatus can detect incorrect implementations rather than merely whether the current implementation passes.

## 6. Metamorphic properties

Differential tests depend on nearcore as an oracle. Metamorphic tests give an independent signal.

Examples:

- Replaying the same input is deterministic.
- A view call leaves state unchanged.
- A failed call leaves contract storage unchanged.
- Adding an unrelated account does not affect execution.
- Independent transfers commute.
- Splitting execution at a block boundary preserves the expected receipt queue.
- Total tokens before and after execution equal balances, attached funds, refunds, and burnt tokens.
- Permuting receipts only changes behavior where the protocol ordering makes them dependent.

These are especially valuable because they can expose a bug shared by fixture-generation code and comparison code.

## 7. Formal verification metrics

Avoid “number of theorems” and “lines of proof.” Both are easy to inflate.

Track meaningful proof obligations instead:

- State well-formedness preserved by every transition.
- Token conservation.
- Receipt-ID uniqueness.
- Receipt dependency safety.
- Failed-call rollback.
- View purity.
- Runtime determinism.
- Gas never exceeds prepaid gas.
- Storage accounting consistency.
- Account authorization rules.
- Refinement between abstract and concrete execution.

A good dashboard entry is:

```text
Invariant: token conservation
Actions covered: 4/8
Receipt transitions covered: 6/9
Protocol versions: 1
Assumptions: hash collision resistance
```

This is much more informative than “42 theorems proven.”

## 8. Separate the proof model from the compatibility engine

I strongly recommend two layers:

```text
Abstract semantics
    simple state and transition definitions
    convenient for contract proofs

Concrete compatibility semantics
    bytes, serialization, trie keys, gas tables, protocol versions

Refinement theorem
    observe concrete execution = abstract execution
```

Otherwise, every contract proof will become entangled with Borsh serialization, trie representation, and protocol migration details.

Progress can then be measured by:

- Percentage of concrete transitions connected to the abstract model.
- Observation levels covered by refinement.
- Remaining trusted adapters.
- Concrete features implemented without a refinement theorem.

## 9. Contract-verification benchmark suite

“Correct under arbitrary blockchain evolution” needs to mean arbitrary **valid** evolution under an explicit threat model.

For example:

```lean
∀ trace,
  ValidTrace config initialState trace →
  AdversaryControls callers args ordering gas deposits timestamps →
  ContractInvariant (trace.last)
```

The adversary may control:

- Caller identity.
- Arguments.
- Transaction ordering.
- Attached deposit and gas.
- Cross-contract responses.
- Callback success or failure.
- Block height and timestamp within protocol constraints.

But it cannot violate runtime semantics. Contract upgrades must either be excluded, restricted by code hash, or included in the property.

Create increasingly difficult benchmark contracts:

1. Counter: isolation and arithmetic invariant.
2. Escrow: conservation and authorization.
3. Fungible token: supply conservation and access control.
4. NFT: uniqueness and ownership.
5. Auction: time-dependent behavior.
6. Cross-contract swap: callbacks and partial failures.
7. DAO: authorization and adversarial proposal ordering.
8. Upgradeable contract: code-hash and migration invariants.

Track:

- Benchmarks expressible.
- Properties completely proved.
- Maximum adversarial trace structure handled.
- Specification size relative to contract API.
- Proof elaboration time.
- Proof breakage caused by runtime changes.
- Whether counterexamples contain understandable execution traces.

A key usability target could be:

> A new user can state and prove the counter and escrow invariants without editing runtime internals.

## 10. Trusted computing base and proof hygiene

Your syntactic gates are good, but expand them to:

- Zero `sorry`.
- Zero unexpected axioms.
- Zero `unsafe` in proof-relevant modules.
- Zero warnings.
- Formatter and linter clean.
- Pinned Lean, Lake, dependencies, nearcore commit, and protocol configuration.
- Reproducible generated fixtures.
- All public theorems audited with `#print axioms`.

Lean’s `#print axioms` reports the transitive axioms used by a declaration, including `sorryAx`, so this can become a CI-enforced artifact rather than a manual check. [Lean axiom auditing](https://lean-lang.org/doc/reference/latest/Axioms/).

Also maintain an explicit trusted-base document:

```text
Lean kernel
standard axioms permitted
hash implementation/assumption
WASM decoder
fixture importer
nearcore oracle adapter
generated-code boundary
```

Track trusted non-Lean code and unproved assumptions as quantities that should decrease.

## 11. Agent-development metrics

Since agents will do most of the implementation, measure the development process itself:

- Percentage of agent PRs passing CI on first submission.
- Median time from assigned feature to minimized differential test.
- Regression rate after merging.
- Percentage of failures producing reproducible seeds.
- Median Lean feedback time for a local edit.
- Full CI duration.
- Number of files/modules an agent must understand to add one action.
- Documentation coverage for public semantic definitions.

Fast feedback matters enormously. I would target:

- Unit/property suite under 30 seconds.
- Selected differential suite under 5 minutes.
- Full fuzz/replay suite scheduled separately.
- Incremental Lean proof feedback below one second for normal edits.

## Recommended top-level dashboard

I would begin with these ten numbers:

```text
Protocol feature coverage
Differential feature coverage
Strongest observation level matched
Generated trace actions executed
Semantic mutation score
Historical protocol eras replayed
Core invariant transition coverage
Contract benchmark properties proved
Unproved assumptions / trusted adapters
Sorries, warnings, and unexpected axioms
```

The north-star goal is not simply “Lean matches nearcore.” It is:

> For every supported protocol feature, we know where its semantics came from, can execute it, can compare it against nearcore, can detect plausible incorrect implementations, and can use it in contract-level proofs under an explicit adversary model.

That gives both humans and autonomous agents a concrete, hard-to-game definition of progress.
