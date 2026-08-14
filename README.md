# NEAR Protocol in Lean

NEAR Protocol semantics in Lean, with a proof-friendly abstract model and a
separate nearcore-compatible execution model.

The project is at **Milestone 14 (latest-window scope)**. The proof-friendly kernel covers transactions,
receipts, block scheduling, verification APIs, and aggregate economics. Generated
campaigns compare the model with the pinned nearcore 2.13.3 sandbox through L5.
A scheduled validation suite executes one million model actions and 10,000
disjoint visible and held-out nearcore traces, with deterministic replay,
metamorphic checks, shrinking, coverage ratchets, and semantic mutations.
The concrete layer runs five compiled contracts through pinned Talos semantics
and matches the scoped host corpus through L5. It also implements exact Borsh,
identifier, trie-key, and state-root projection, with 1,000 synthetic chunks
matching pinned near-store through L7.
The historical layer also imports a protocol-86 mainnet corpus with 10,000
consecutive produced blocks and 10,000 included chunks, with provenance,
checkpoint/resume, and first-difference diagnostics. This is commitment replay,
not independent full-state runtime execution, so the v0.4 release is withheld.
The active replay workflow is intentionally bounded to the latest finalized
window: `make m12-latest` refreshes a 100-block report, and the online smoke gate
checks the newest 10 blocks without requiring an archival node.
The current-protocol layer selects exactly protocol 86, implements the active
10-shard V3 account-range layout, proves routing determinism and minimum
cross-shard delay, and imports current epoch and validator inputs. Historical
migrations and upgrade boundaries remain intentionally unsupported under the
latest-block-only scope.
The final scoped stabilization gate combines one latest window across commitment,
sharding, epoch, throughput, and peak-memory evidence, and carries the separately
generated repository mutation score with a pinned artifact digest. Genesis and
historical protocol support remain explicit exclusions, so v1.0 is withheld.

## Quick start

Install [elan](https://github.com/leanprover/elan), Python 3.11 or newer,
`wasm-tools` 1.248.0, Node.js 22.22.2 or newer, and `make`, then run the offline
gates:

```sh
make ci
```

The checked-in `lean-toolchain` installs the exact Lean release. The command
checks source hygiene, builds with warnings as errors, runs tests, audits every
project declaration transitively for axioms, validates feature evidence and
ratchets, checks pinned nearcore-reference provenance, verifies generated
artifacts, and proves that each negative fixture is rejected.

Run the pinned nearcore smoke comparison with `make differential-smoke`; regenerate the 1,000-trace report
with `make differential-campaign`. `make receipt-smoke` runs the cross-contract L4
fixture, while `make receipt-campaign` regenerates its 10,000-trace exit report.
`make validation-campaign` regenerates the million-action model report, and
`make differential-nightly` runs the two 5,000-trace L4 corpora.
`make wasm-campaign` regenerates the compiled-counter L4 report, while
`make wasm-validation` verifies Talos instruction and mutation evidence.

`make m10-validation` executes the five-contract host-environment gate and its
10,000 generated compiled calls. `make m10-smoke` compares the benchmark corpus
with the pinned nearcore oracle. See [docs/HOST_ENVIRONMENT.md](docs/HOST_ENVIRONMENT.md)
for the protocol-86 gas scope and intentional projection limits.

`make m11-validation` checks exact nearcore serialization vectors, the concrete
refinement theorem, state-change encodings, and all 1,000 synthetic L7 roots. See
[docs/CONCRETE_SEMANTICS.md](docs/CONCRETE_SEMANTICS.md) for scope and trusted
adapters.

`make m12-validation` checks the typed historical importer, fixed-source hashes,
block/chunk continuity, action and failure strata, root links, checkpoint resume,
and diagnostic mutations. See [docs/HISTORICAL_REPLAY.md](docs/HISTORICAL_REPLAY.md)
for the exact compatibility boundary.
`make m12-latest` refreshes the checked 100-block latest-window artifact;
`make m12-latest-smoke` performs a read-only live 10-block check.
`make m13-validation` checks the protocol-86 Lean model and the checked current
sharding artifact. `make m13-latest` refreshes 100 finalized blocks of receipt
routing and epoch evidence; `make m13-latest-smoke` validates the newest 10. See
[docs/CURRENT_PROTOCOL.md](docs/CURRENT_PROTOCOL.md) for the exact scope.
`make m14-validation` checks the latest stabilization artifact and corruption
tests. `make m14-latest` refreshes its 100-block performance and compatibility
measurements; `make m14-latest-smoke` repeats the campaign over the newest 10.
See [docs/LATEST_STABILIZATION.md](docs/LATEST_STABILIZATION.md).

Individual workflows include `make build`, `make test`, `make lint`, `make audit`,
`make format-check`, and `make scorecard`. `make format` remains an alias for the
documented source-hygiene check; the project does not currently claim canonical
Lean layout formatting. Regenerate audit evidence and the scorecard with:

```sh
python3 scripts/check.py audit
python3 scripts/check.py scorecard --output scorecard.json
```

Browse the project roadmap and evaluation framework locally with `make notes`,
then open <http://localhost:8000>.

For parallel Codex tasks, choose the checked-in **NEAR Lean** local environment
when creating a worktree. It shares manifest-keyed Lake dependency caches while
keeping project build outputs isolated. See
[`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md#codex-worktrees).

## Pinned baseline

- Lean: `v4.32.2` (`f3b06c705e6c85f5314019d5d3baab0fec5b580c`), aligned with pinned Talos
- nearcore: `2.13.3` (`5af9ca74631e6cf0dae33e77d1a632e94d2952ce`)
- NEAR protocol version: exactly `86`

The authoritative machine-readable values are in
[`protocol/baseline.json`](protocol/baseline.json). The planned semantic surface
is tracked in [`protocol/features.json`](protocol/features.json), and the current
dashboard is [`scorecard.json`](scorecard.json). Every nearcore source path is
tied to an immutable Git object in
[`protocol/nearcore-references.json`](protocol/nearcore-references.json); hosted
CI verifies that snapshot against the pinned upstream commit.

## Design and trust

- [`docs/SEMANTICS.md`](docs/SEMANTICS.md) defines the abstract/concrete boundary.
- [`docs/TRUSTED_COMPUTING_BASE.md`](docs/TRUSTED_COMPUTING_BASE.md) records what is trusted.
- [`docs/KNOWN_DEVIATIONS.md`](docs/KNOWN_DEVIATIONS.md) records compatibility gaps.
- [`docs/CURRENT_PROTOCOL.md`](docs/CURRENT_PROTOCOL.md) defines the latest-only protocol and sharding scope.
- [`docs/LATEST_STABILIZATION.md`](docs/LATEST_STABILIZATION.md) records the final scoped campaign and withheld historical release.
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) documents the gates and update workflow.
- [`notes/milestones.html`](notes/milestones.html) is the development roadmap.
- [`notes/evaluation.html`](notes/evaluation.html) defines the correctness signals and metrics.
- [`notes/VALIDATION.md`](notes/VALIDATION.md) documents the long-running validation design.
