# Development workflow

## Reproducible command

A fresh checkout must pass:

```sh
make ci
```

No network access is required after elan has installed the toolchain named by
`lean-toolchain`; the project currently has no third-party Lake dependencies.

The command runs these gates:

1. `make format` checks UTF-8, final newlines, trailing whitespace, tabs, and
   canonical two-space JSON.
2. `make build` builds every default target with warnings treated as errors.
3. `make lint` rejects proof holes and unsafe/prohibited declarations, validates
   manifests, and audits headline theorem axioms through Lean. It depends on the
   build so transitive `#print axioms` checks also work on a fresh checkout.
4. `make test` runs the configured Lake test driver with warnings as errors.
5. `make scorecard` proves that `scorecard.json` matches the feature manifest.
6. `make negative-tests` proves that deliberately bad formatting, `sorry`, a
   compiler warning, and both direct and transitive prohibited axioms are rejected.

CI runs the same command and uploads `scorecard.json` as a machine-readable
artifact even when another gate fails.

## Adding Lean declarations

- Put library declarations below `NEARLean/` and expose public modules through
  `NEARLean.lean`.
- Put executable tests below `Test/`.
- Keep proofs free of `sorry`, `admit`, `unsafe`, local axioms, and opaque escape
  hatches.
- Add every headline theorem to `audit/theorems.txt` so its transitive axioms are
  checked.
- Run `make ci` before submitting a change.

## Updating protocol coverage

Every planned feature has a stable ID in `protocol/features.json`. Status values
ratchet in this order: `unsupported`, `partial`, `implemented`, `verified`.
Changing a feature requires a pinned nearcore source path and must not silently
lower status or narrow an already supported protocol range.

After editing either protocol manifest, regenerate the deterministic dashboard:

```sh
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
