# Concrete encoding and state-root semantics

Milestone 11 adds a compatibility layer under `NEARLean.Concrete` without
changing the proof-oriented contract API. The layer implements little-endian
Borsh primitives, protocol-86 account/data-receipt/success-outcome encodings,
receipt-ID derivation, trie keys, and the nearcore Patricia-trie root algorithm.

Trie nodes use nearcore's hex-prefix nibble encoding, Borsh discriminants,
16-bit child mask, SHA-256 value references, and subtree memory accounting
(`byte_of_key = 2`, `byte_of_value = 1`, `node_cost = 50`). Account, contract
code, and contract-data records use the exact nearcore key prefixes.

`Oracle/nearcore/m11_oracle.rs` is compiled as an example inside nearcore commit
`5af9ca74631e6cf0dae33e77d1a632e94d2952ce`. It generated the checked-in Borsh
vectors and 1,000 synthetic chunk roots with near-store itself. The Lean gate
independently replays every transfer and counter increment, checks raw state
changes, serialized success outcomes, receipt IDs, and rebuilds every root.

The refinement boundary is executable and proved for the whole current abstract
`Input` type:

```lean
observe (concreteStep config state input) =
  NEARLean.step config state.abstract input
```

The concrete transition intentionally reuses the proved abstract action
transition, then projects the result to exact state records and roots. This keeps
Borsh and trie details out of ordinary contract proofs. It is not yet an
independent reimplementation of nearcore's full action processor.

The L7 claim is scoped to the synthetic record corpus. It does not cover access
keys, action receipts, failure payloads, metadata versions after V1, delayed or
buffered receipt records, migrations, shard layout, or historical state. Those
surfaces are explicit trusted/deviation entries and are exercised by current-era
chunk replay in Milestone 12.
