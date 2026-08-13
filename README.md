# NEAR Protocol in Lean

NEAR Protocol semantics in Lean, with a proof-friendly abstract model and a
separate nearcore-compatible execution model.

The project is at **Milestone 0**: the reproducible project, protocol baseline,
feature scorecard, and quality gates are in place. Protocol behavior is not yet
implemented.

## Quick start

Install [elan](https://github.com/leanprover/elan), Python 3, and `make`, then run:

```sh
make ci
```

The checked-in `lean-toolchain` installs the exact Lean release. The command
checks formatting and policy, builds with warnings as errors, runs tests, audits
the transitive axioms of headline theorems, validates the protocol manifest,
checks the generated scorecard, and proves that each negative fixture is rejected.

Individual workflows are `make build`, `make test`, `make lint`, `make format`,
and `make scorecard`. Regenerate the scorecard after changing the manifest with:

```sh
python3 scripts/check.py scorecard --output scorecard.json
```

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
dashboard is [`scorecard.json`](scorecard.json).

## Design and trust

- [`docs/SEMANTICS.md`](docs/SEMANTICS.md) defines the abstract/concrete boundary.
- [`docs/TRUSTED_COMPUTING_BASE.md`](docs/TRUSTED_COMPUTING_BASE.md) records what is trusted.
- [`docs/KNOWN_DEVIATIONS.md`](docs/KNOWN_DEVIATIONS.md) records compatibility gaps.
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) documents the gates and update workflow.
- [`notes/MILESTONES.md`](notes/MILESTONES.md) is the development roadmap.
