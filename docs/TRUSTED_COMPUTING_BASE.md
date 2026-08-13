# Trusted computing base

This document inventories what must currently be trusted and what is checked.
The list is expected to become more precise as executable semantics are added.

## Trusted

- The Lean 4 kernel from the pinned `v4.32.2` toolchain, aligned with Talos.
- The native code, operating system, and hardware used to execute Lean.
- Lake and elan as distributed with, or used to install, the pinned toolchain.
- Talos commit `87336df09b41d819c670be99860481573fd00055`, including its decoder,
  validator, deterministic small-step machine, and standard-axiom dependencies.
- Python 3.11 or newer and the dependency-free gate program in `scripts/check.py`.
- The differential campaign and minimization adapter in `scripts/differential.py`.
- Node.js 22.22.2 or newer and the exact packages locked in
  `Oracle/package-lock.json`: `near-sandbox`, `near-api-js`, and `wabt`. The
  sandbox archive reader is overridden to patched `tar` 7.5.22.
- GitHub Actions and the three commit-pinned actions in the CI workflow.
- Humans reviewing changes to the allowed-axiom policy, protocol baseline, feature
  manifest, and this document.

## Oracle boundary

nearcore is an external compatibility oracle, not part of the logical proof
kernel. Its source is pinned to commit
`5af9ca74631e6cf0dae33e77d1a632e94d2952ce`. The runner in `Oracle/run.mjs`, WAT
compilation, finality handling, gas projection, canonicalizer, generator, and
comparison code are trusted adapters rather than Lean proofs. Comparator
corruption tests independently perturb outcome, balance, storage, and error data,
but do not remove that trust. Source references are backed by
checked-in Git object IDs, and hosted CI compares those IDs with the pinned
nearcore tree.

`Oracle/Differential.lean` deliberately lives outside the audited `NEARLean`
library. The Talos-backed production adapter is audited inside `NEARLean`, so
its transitive standard axioms are visible rather than hidden at the executable
boundary.

The L4 adapter additionally trusts the small `Oracle/contracts/async.wat` fixture
and its projection of opaque nearcore receipt hashes to creation-order identities.
The projection excludes economic refund receipts and retains semantic action
receipt outcomes. Its order sensitivity is exercised by deliberate corruption in
the offline comparator test.

## Axiom policy

Proposition extensionality (`propext`) is approved because Lean's generated
equality and representation declarations for Milestone 1 structures depend on
it. `Classical.choice` and `Quot.sound` are approved for the pinned Talos
decoder/executor dependency. Nonstandard and all other unlisted axioms remain
prohibited.
The lint gate imports every production module, enumerates every declaration
originating in `NEARLean.*` modules, and uses Lean's transitive axiom collector on
each declaration. `audit/theorems.txt` only marks headline theorems for dashboard
reporting; it does not determine audit coverage. The full result is checked in as
`audit/report.json`. The allowed set and rationale are machine-readable in
`audit/allowed_axioms.json`.

Source policy also rejects `sorry`, `admit`, `axiom`, `opaque`, and `unsafe` in
production Lean code after removing nested comments and string literals. This
lexical gate supplements, but does not replace, the environment-level audit.

## Not yet in the trusted base

There is no concrete serialization layer, trie implementation, state-root
computation, or historical fixture importer yet. Those are unsupported features
rather than silently trusted components.
