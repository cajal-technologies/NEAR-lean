# Trusted computing base

This document inventories what must currently be trusted and what is checked.
The list is expected to become more precise as executable semantics are added.

## Trusted

- The Lean 4 kernel from the pinned `v4.33.0` toolchain.
- The native code, operating system, and hardware used to execute Lean.
- Lake and elan as distributed with, or used to install, the pinned toolchain.
- Python 3 and the small dependency-free gate program in `scripts/check.py`.
- GitHub Actions and the three commit-pinned actions in the CI workflow.
- Humans reviewing changes to the allowed-axiom policy, protocol baseline, feature
  manifest, and this document.

## Oracle boundary

nearcore is an external compatibility oracle, not part of the logical proof
kernel. Its source is pinned to commit
`5af9ca74631e6cf0dae33e77d1a632e94d2952ce`. Future runners, fixture importers,
canonicalizers, and comparison code will be trusted adapters until independently
validated; every such adapter must be added here.

## Axiom policy

No axioms are currently approved. `audit/theorems.txt` enumerates headline
theorems, and the lint gate runs Lean's `#print axioms` transitively for each one.
The allowed set is machine-readable in `audit/allowed_axioms.json`. Adding an
axiom requires a reviewed rationale in that file and in this document.

Source policy also rejects `sorry`, `admit`, `axiom`, `opaque`, and `unsafe` in
production Lean files. This lexical gate supplements, but does not replace, the
transitive kernel-level audit.

## Not yet in the trusted base

There is no WASM decoder, interpreter, cryptographic implementation, fixture
importer, serialization layer, trie implementation, or nearcore runner yet. Those
are unsupported features rather than silently trusted components.
