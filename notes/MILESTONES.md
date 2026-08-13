
-- Codex output verbatim below

I’d organize the project into 14 milestones, with useful releases after milestones 3, 6, 10, and 12. Each milestone ends with an objective exit gate, not a subjective “looks done.”

The numeric targets below are initial ratchets: after establishing baseline performance, they may be raised but should not silently be lowered.

## Rules applying to every milestone

A feature only counts as complete when, where applicable, it has:

1. A pinned nearcore source reference and protocol-version range.
2. Executable semantics.
3. Positive and negative tests.
4. Differential tests against nearcore.
5. Relevant invariant-preservation proofs.
6. Updated documentation and feature matrix.
7. No unexplained warnings, `sorry`, `unsafe`, or unapproved axioms.

CI should publish a machine-readable scorecard after every merge.

---

## Milestone 0 — Reproducible project and scorecard

**Goal:** Make the empty repository safe for autonomous development.

**Deliverables:**

- Lean project skeleton and pinned Lean toolchain.
- Pinned nearcore commit and initial protocol version.
- One-command build, test, lint, and format workflows.
- CI gates for warnings, formatting, `sorry`, and prohibited axioms.
- Machine-readable protocol feature matrix.
- Trusted-computing-base and known-deviations documents.
- Initial metric dashboard.
- Clear distinction between abstract semantics and concrete compatibility semantics.

**Exit gate:**

- Fresh checkout passes CI with one documented command.
- CI deliberately fails on an inserted `sorry`, warning, formatting error, and prohibited axiom.
- Every planned feature has a manifest entry, even if marked unsupported.
- Builds and tests are reproducible from pinned dependencies.

Lean can report transitive axiom dependencies through `#print axioms`, including uses of `sorryAx`, so axiom auditing should be automated from the beginning. [Lean axiom auditing](https://lean-lang.org/doc/reference/latest/Axioms/).

---

## Milestone 1 — Abstract state-transition kernel

**Goal:** Define the proof-friendly mathematical core without WASM, tries, signatures, or networking.

**Deliverables:**

- `AccountId`, `Balance`, `Gas`, `BlockContext`, storage keys and values.
- Accounts, contract identifiers, world state, errors, and outcomes.
- `WorldState.WellFormed`.
- Pure transition interface:

```lean
step :
  RuntimeConfig →
  WorldState →
  Input →
  Except RuntimeError (WorldState × Output)
```

- Explicit account, balance, storage, and identifier invariants.

**Exit gate:**

- Determinism theorem for `step`.
- All initial constructors produce well-formed states.
- No partial functions or `unsafe` definitions in the semantic kernel.
- A small executable trace can be evaluated with `#eval`.
- Axiom audit passes for all headline theorems.

---

## Milestone 2 — Basic sandbox and Workspaces-style API

**Goal:** Obtain the first usable vertical slice.

**Deliverables:**

- `CreateAccount`, `Transfer`, `DeployContract`, and `FunctionCall`.
- Native Lean contracts as the temporary execution backend.
- Contract storage, logs, return values, and failures.
- Atomic rollback for failed calls.
- `NearChain.init`, `deploy`, `call`, `view`, and state queries.
- Counter and simple escrow examples.

**Exit gate:**

- A counter can be deployed, incremented, and viewed through the public API.
- An escrow can receive and release funds.
- Proved:

  - View purity.
  - Failed-call rollback.
  - Runtime determinism.
  - Unrelated-account noninterference for basic actions.

- At least 100 scenario tests, including failures and boundary values.

**Release:** `v0.1` — executable logical NEAR sandbox.

---

## Milestone 3 — nearcore oracle and differential infrastructure

**Goal:** Establish an independent behavioral correctness signal before implementing more semantics.

**Deliverables:**

- Canonical JSON or binary trace format.
- Pinned nearcore runner that consumes the same genesis and inputs.
- Result canonicalizer and structured comparison report.
- Deterministic random trace generator.
- Automatic failing-trace minimizer.
- Permanent regression corpus.

**Exit gate:**

- 1,000 generated basic-action traces pass through comparison level L3:

  - Same success or error category.
  - Same return values and logs.
  - Same balances and contract storage.

- Every failure produces a reproducible seed and minimized fixture.
- The comparator detects deliberately corrupted balance, storage, outcome, and error values.
- nearcore version and protocol configuration appear in every fixture.

This is the first major stop/go checkpoint: if the basic abstract model cannot align cleanly with nearcore, its boundaries should be revised before receipts and WASM are added.

---

## Milestone 4 — Transactions, receipts, and promises

**Goal:** Model NEAR’s asynchronous execution structure.

**Deliverables:**

- Transaction-to-receipt conversion.
- Action receipts and data receipts.
- Input-data dependencies.
- Promise results and callbacks.
- Receipt identifiers and output-data receivers.
- Cross-contract calls.
- Receipt queues and bounded execution.

Receipts are the central mechanism for cross-contract execution, and callbacks must wait until their input data receipts are satisfied. [NEAR receipt semantics](https://nomicon.io/RuntimeSpec/Receipts).

**Exit gate:**

- Cross-contract call and callback examples execute correctly.
- 10,000 generated receipt traces pass through L4, including receipt identity and order.
- Proved:

  - Receipt-ID uniqueness.
  - A callback cannot execute before its dependencies arrive.
  - Processing preserves state well-formedness.
  - Fixed inputs and scheduling are deterministic.
  - Every created receipt is either queued, executed, or explicitly discarded by a modeled rule.

---

## Milestone 5 — Single-shard block scheduler

**Goal:** Turn the runtime into a small but genuine chain simulator.

**Deliverables:**

- Block production and block context advancement.
- Local, incoming, delayed, and postponed receipts.
- Protocol processing order.
- Per-block execution bound.
- `produceBlock` and `runUntil`.
- Execution outcome lookup.

NEAR applies transactions and different receipt classes in a defined order, delaying work when a block’s gas capacity is exhausted. [Chunk application order](https://nomicon.io/RuntimeSpec/ApplyingChunk).

**Exit gate:**

- 1,000-block generated chains replay deterministically.
- Processing-order tests agree with nearcore.
- L4 differential comparison passes for at least 10,000 blocks.
- `runUntil` always terminates because it requires explicit fuel or a block bound.
- Delayed and postponed receipt invariants are proved.

---

## Milestone 6 — Contract specification framework

**Goal:** Make the project useful for proving contract correctness before exact nearcore compatibility is complete.

**Deliverables:**

- Reachability over arbitrary valid traces.
- Explicit adversary and environment model.
- Reusable definitions for:

  - State invariants.
  - Call preconditions and postconditions.
  - Authorization.
  - Conservation.
  - Noninterference.
  - Conditional liveness.

A typical statement should look conceptually like:

```lean
theorem escrow_safe :
  ∀ trace,
    ValidTrace config initialState trace →
    EscrowInvariant trace.last
```

**Exit gate:**

- Counter, escrow, and abstract fungible-token benchmarks.
- At least one arbitrary-trace invariant for each benchmark.
- Proofs quantify over arbitrary valid traces rather than bounded enumeration.
- Contract proofs use the public verification API and do not import runtime implementation internals.
- Threat model explicitly documents which inputs the adversary controls.
- A new benchmark contract can be specified without modifying the core runtime.

**Release:** `v0.2` — native-contract verification sandbox.

This is the second stop/go checkpoint: have someone unfamiliar with the internals specify one small contract. If that requires understanding receipt implementation details, the verification API needs redesign.

---

## Milestone 7 — Deposits, gas, storage, and refunds

**Goal:** Implement exact economic semantics for the pinned protocol version.

**Deliverables:**

- Attached deposits.
- Prepaid, burnt, and used gas.
- Gas schedules and action fees.
- Storage usage and storage staking.
- Gas and deposit refunds.
- Out-of-gas and insufficient-balance behavior.
- Balance carried by queued and postponed receipts.

**Exit gate:**

- Differential comparison reaches L5.
- 10,000 targeted economic traces agree with nearcore.
- Token conservation is proved across every implemented transition.
- Gas never exceeds the relevant configured limits.
- Failure-path tests cover every economic error category.
- At least 90% of an initial economics mutation set is detected.

---

## Milestone 8 — Fuzzing, coverage, and mutation infrastructure

**Goal:** Measure whether the validation system catches plausible implementation errors.

**Deliverables:**

- Grammar-aware generators for states, actions, receipts, and blocks.
- Feature-aware coverage reporting.
- Automatic shrinking.
- Metamorphic tests.
- Semantic mutation framework.
- Visible and held-out differential corpora.
- Scheduled long-running CI jobs.

**Exit gate:**

- One million model-only actions per nightly campaign.
- At least 10,000 nearcore differential traces per nightly campaign.
- Every supported manifest feature has positive, negative, and differential coverage.
- At least 90% overall semantic mutation score.
- Every discovered bug becomes a minimized permanent fixture.
- Fixed random seeds reproduce bit-for-bit.

Important mutations should include wrong receipt order, skipped rollback, incorrect signer/predecessor use, missing refunds, premature callbacks, and gas off-by-one errors.

---

## Milestone 9 — WASM execution MVP

**Goal:** Execute real compiled contracts instead of native Lean substitutes.

**Deliverables:**

- Pinned WASM version and supported instruction manifest.
- Module decoding and validation.
- Deterministic interpreter or other explicitly documented execution strategy.
- Memory, globals, tables, calls, traps, and exported method resolution.
- Minimal host functions needed by a compiled counter.
- Separation between WASM semantics and NEAR host semantics.

**Exit gate:**

- The same compiled counter WASM runs in Lean and nearcore.
- No native Lean implementation is substituted during the test.
- Success, return value, storage, logs, and traps match through L4.
- Instruction coverage is reported.
- Unsupported modules fail explicitly, never silently.
- WASM parser and interpreter mutation suites meet a 90% target.

---

## Milestone 10 — Contract-relevant NEAR host environment

**Goal:** Support realistic compiled NEAR contracts.

**Deliverables:**

- Registers and memory interfaces.
- Context functions.
- Storage functions.
- Logging and return values.
- Promise creation and callbacks.
- Crypto functions used by contracts.
- Exact host errors and gas charging.
- Compiled counter, escrow, fungible-token, NFT, and callback-heavy contracts.

**Exit gate:**

- All benchmark contracts execute from their actual WASM artifacts.
- Differential comparison reaches L5 for the benchmark corpus.
- At least 10,000 generated compiled-contract calls pass.
- Every host function used by the benchmark corpus has:

  - Boundary tests.
  - Error tests.
  - Gas tests.
  - Differential tests.

- Native and WASM executions refine to the same abstract contract observations where both are defined.

**Release:** `v0.3` — real-WASM verification sandbox.

---

## Milestone 11 — Concrete encoding and abstract refinement

**Goal:** Connect proof-friendly semantics to nearcore-compatible bytes and state representation.

**Deliverables:**

- Exact serialization.
- Hash and identifier derivation.
- Concrete receipt and outcome encodings.
- Trie keys and state roots.
- Concrete runtime transition.
- Abstraction function from concrete to abstract state.
- Refinement theorems.

**Exit gate:**

- Differential comparison reaches L7 for synthetic chunks.
- At least 1,000 generated chunks produce identical state roots.
- Proved, for supported inputs:

```lean
observe (concreteStep s input) =
  abstractStep (abstract s) input
```

- All remaining unproved adapters and cryptographic assumptions are listed in the trusted-base report.
- Concrete compatibility details do not leak into ordinary contract proofs.

---

## Milestone 12 — Current-era chunk replay

**Goal:** Replay real NEAR data for one pinned protocol era.

**Deliverables:**

- Importers for real pre-state, blocks, chunks, transactions, and receipts.
- Historical fixture cache with provenance and hashes.
- Stratified historical corpus.
- First-difference diagnostics.
- Replay checkpointing and resumability.

**Exit gate:**

- 10,000 stratified real chunks replay with identical outcomes and roots.
- One contiguous 10,000-block interval replays successfully.
- Corpus includes every supported action and major error class.
- Replaying the same interval on a fresh machine gives identical results.
- Failures identify the first differing transaction, receipt, account, or trie key.

**Release:** `v0.4` — exact current-era runtime replayer.

---

## Milestone 13 — Protocol versions, upgrades, and multiple shards

**Goal:** Move from a pinned runtime to a historical chain model.

**Deliverables:**

- Protocol-version-indexed configuration.
- Feature activation gates.
- Runtime migrations.
- Shard layout and receipt routing.
- Cross-shard receipt delays.
- Validator and epoch inputs needed for state transitions.
- Upgrade-boundary fixtures.

**Exit gate:**

- At least two real protocol upgrade boundaries replay exactly.
- Synthetic multi-shard scenarios agree with nearcore.
- One real interval containing cross-shard traffic replays exactly.
- Each protocol-gated feature has tests immediately before and after activation.
- Contracts can be verified against either one fixed version or an explicit range of versions.

---

## Milestone 14 — Historical replay and stabilization campaign

**Goal:** Expand exact compatibility toward full NEAR history.

This is an ongoing compatibility campaign rather than one implementation feature.

**Measurements:**

- Earliest and latest exactly replayed heights.
- Largest contiguous replay interval.
- Percentage of stratified sampled blocks passing.
- Number of protocol eras supported.
- Number of upgrade boundaries crossed.
- Number of unexplained divergences.
- Replay throughput and peak memory.
- Semantic mutation score.
- Trusted assumptions remaining.

**Final exit target:**

- Genesis-to-checkpoint replay produces the same roots and outcomes.
- All historical protocol transitions in that interval are supported.
- Every divergence is either fixed or documented as an intentional scope exclusion.
- Replay is reproducible from archived inputs and pinned toolchains.

**Release:** `v1.0` when the exact supported historical range and verification guarantees are documented and reproducible.

## Recommended release checkpoints

| Release | Milestone | What it proves |
|---|---:|---|
| `v0.1` | 3 | Basic sandbox semantics align with nearcore |
| `v0.2` | 6 | Useful arbitrary-trace contract proofs are possible |
| `v0.3` | 10 | Real compiled WASM contracts can be verified |
| `v0.4` | 12 | Current-era real chunks replay exactly |
| `v1.0` | 14 | A documented historical range is exactly supported |

This sequence deliberately brings differential testing online early, contract verification before WASM completeness, and historical replay only after exact encoding and refinement are established. That gives agents a strong correctness signal throughout development rather than only at the very end.
