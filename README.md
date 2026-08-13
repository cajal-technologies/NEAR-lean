# NEAR Protocol in Lean

NEAR Protocol semantics in Lean, with a proof-friendly abstract model and a
separate nearcore-compatible execution model.

The project is at **Milestone 0**: the reproducible project, protocol baseline,
feature scorecard, and quality gates are in place. Protocol behavior is not yet
implemented.

## Quick start

Install [elan](https://github.com/leanprover/elan), Python 3.11 or newer, and
`make`, then run:

```sh
make ci
```

The checked-in `lean-toolchain` installs the exact Lean release. The command
checks source hygiene, builds with warnings as errors, runs tests, audits every
project declaration transitively for axioms, validates feature evidence and
ratchets, checks pinned nearcore-reference provenance, verifies generated
artifacts, and proves that each negative fixture is rejected.

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

- Lean: `v4.33.0` (`d8b18978322de05a8f3dba51ef03cf5461676c17`)
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
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) documents the gates and update workflow.
- [`notes/MILESTONES.md`](notes/MILESTONES.md) is the development roadmap.
- [`notes/EVALUATION.md`](notes/EVALUATION.md) defines the correctness signals and metrics.
