# Trusted computing base

This document inventories what must currently be trusted and what is checked.
The list is expected to become more precise as executable semantics are added.

## Trusted

- The Lean 4 kernel from the pinned `v4.33.0` toolchain.
- The native code, operating system, and hardware used to execute Lean.
- Lake and elan as distributed with, or used to install, the pinned toolchain.
- Python 3.11 or newer and the dependency-free gate program in `scripts/check.py`.
- GitHub Actions and the three commit-pinned actions in the CI workflow.
- Humans reviewing changes to the allowed-axiom policy, protocol baseline, feature
  manifest, and this document.

## Oracle boundary

nearcore is an external compatibility oracle, not part of the logical proof
kernel. Its source is pinned to commit
`5af9ca74631e6cf0dae33e77d1a632e94d2952ce`. Future runners, fixture importers,
canonicalizers, and comparison code will be trusted adapters until independently
validated; every such adapter must be added here. Source references are backed by
checked-in Git object IDs, and hosted CI compares those IDs with the pinned
nearcore tree.

## Axiom policy

Proposition extensionality (`propext`) is approved because Lean's generated
equality and representation declarations for Milestone 1 structures depend on
it. `Classical.choice`, `Quot.sound`, and nonstandard axioms remain prohibited.
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

There is no WASM decoder, interpreter, cryptographic implementation, fixture
importer, serialization layer, trie implementation, or nearcore runner yet. Those
are unsupported features rather than silently trusted components.
