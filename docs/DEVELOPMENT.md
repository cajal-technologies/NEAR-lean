# Development workflow

## Reproducible command

A fresh checkout must pass:

```sh
make ci
```

Python 3.11 or newer is required. No network access is required after elan has
installed the toolchain named by `lean-toolchain`; the project currently has no
third-party Lake dependencies. Hosted CI additionally verifies nearcore path
provenance against GitHub. Online oracle checks require Node.js 22.22.2 or newer;
`npm ci --prefix Oracle --ignore-scripts` installs the exact lockfile.

The command runs these gates:

1. `make format-check` checks UTF-8, final newlines, trailing whitespace, tabs,
   and canonical two-space JSON. `make format` is an alias. This is a
   source-hygiene policy, not a canonical Lean layout formatter.
2. `make build` builds every default target with warnings treated as errors.
3. `make lint` rejects proof holes and unsafe/prohibited declarations, validates
   manifests, enforces feature lifecycle and history ratchets, and audits every
   declaration from every production `NEARLean.*` module through Lean's elaborated
   environment. It also checks the generated `audit/report.json` artifact.
4. `make test` runs the configured Lake test driver with warnings as errors.
5. `make nearcore-references` checks every feature reference against the pinned
   Git-object provenance snapshot.
6. `make scorecard` proves that `scorecard.json` matches the feature manifest and
   audited declaration evidence.
7. `make negative-tests` exercises source hygiene, comments and strings, `sorry`,
   warnings, direct/private/transitive axioms, manifest evidence, reference
   provenance, and history ratchets.
8. `make differential-self-test` corrupts outcome, error, balance, and storage
   observations, receipt order, and checks action minimization without requiring
   nearcore.

CI runs `make ci-online`, which adds a one-request verification of every stored
nearcore Git object against the pinned upstream tree plus real L3 and L4 sandbox
smoke traces. `make differential-campaign` regenerates the ratcheted 1,000-trace
report.
`make receipt-smoke` checks the real L4 cross-contract fixture, and
`make receipt-campaign` regenerates the ratcheted 10,000-trace receipt report.
CI uploads `scorecard.json` as a machine-readable artifact even when another gate
fails.

## Adding Lean declarations

- Put library declarations below `NEARLean/` and expose public modules through
  `NEARLean.lean`.
- Put executable tests below `Test/`.
- Keep proofs free of `sorry`, `admit`, `unsafe`, local axioms, and opaque escape
  hatches.
- Add release-significant theorem names to `audit/theorems.txt` so they are
  highlighted in the dashboard. All declarations are audited regardless of that
  list.
- Run `make ci` before submitting a change.

## Updating protocol coverage

Every planned feature has a stable ID in `protocol/features.json`. Status values
ratchet in this order: `unsupported`, `partial`, `implemented`, `verified`.
Implemented features require executable semantics plus positive and negative
tests. Verified features additionally require differential coverage and at least
one discharged proof obligation. CI rejects feature removal, status/evidence
regression, weight or identity changes, and narrowing a supported protocol range.
Changing a nearcore source path requires regenerating its Git-object provenance.

After editing proof or protocol evidence, regenerate deterministic artifacts:

```sh
python3 scripts/check.py audit
python3 scripts/check.py scorecard --output scorecard.json
```

Changes to the Lean toolchain, nearcore commit, protocol range, approved axioms,
or trusted computing base require explicit review because they change the meaning
or trustworthiness of all subsequent results.

## Codex worktrees

The shared local Codex environment is checked in at
`.codex/environments/environment.toml`. Select **Worktree** and the **NEAR Lean**
environment when starting a parallel Codex task. Setup runs automatically and the
Build, Test, and Full CI actions appear in the app toolbar.

Each worktree keeps its own `.lake/build`, so concurrent branches cannot overwrite
one another's project artifacts. Dependency checkouts and their compiled caches
live under the repository's shared Git directory, keyed by the SHA-256 of
`lake-manifest.json`:

```text
.git/codex-cache/lake-packages/<manifest-hash>/packages
```

Worktrees with the same dependency lock share that cache; a dependency change
gets a separate cache automatically. The setup lock serializes first-time cache
population, while subsequent worktrees only create a symlink and perform the
small project build.
