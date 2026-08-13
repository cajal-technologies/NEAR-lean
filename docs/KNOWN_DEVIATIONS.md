# Known deviations

The pinned compatibility target is nearcore 2.13.3 at protocol version 86.

At Milestone 0, **all protocol semantics are unsupported**. The repository only
contains the build skeleton, semantic-layer boundary, manifests, policy gates,
tests for those gates, and scorecard machinery. In particular, it does not yet:

- execute accounts, actions, transactions, receipts, blocks, promises, or WASM;
- implement gas, deposits, storage staking, refunds, serialization, tries, or state roots;
- run a nearcore differential oracle or replay historical chain data;
- claim equivalence at any comparison level L1-L7; or
- prove any NEAR runtime or contract invariant.

`protocol/features.json` is the exhaustive machine-readable deviation list: every
planned feature is currently marked `unsupported`. A feature may move to `partial`
or beyond only when its implementation PR also updates its tests, proof
obligations, nearcore reference, this document where relevant, and the scorecard.

The project makes no compatibility claim for protocol versions other than 86.
