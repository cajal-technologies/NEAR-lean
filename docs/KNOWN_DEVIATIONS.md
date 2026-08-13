# Known deviations

The pinned compatibility target is nearcore 2.13.3 at protocol version 86.

At Milestone 2, the repository implements a proof-friendly abstract sandbox. It
executes account creation, liquid-balance transfers, native-contract deployment,
and synchronous function calls. Failed calls restore the full abstract pre-state,
and views are pure. The native backend contains only counter and simple escrow
programs.

These definitions are not a compatibility claim: identifiers use only abstract
length bounds, balances and gas are unbounded naturals, state uses association
lists, and successful calls use a flat gas marker. In particular, the project does
not yet:

- execute transactions, receipts, blocks, promises, host functions, or WASM;
- implement gas, deposits, storage staking, refunds, serialization, tries, or state roots;
- run a nearcore differential oracle or replay historical chain data;
- claim equivalence at any comparison level L1-L7; or
- prove compatibility of any abstract invariant with nearcore.

`protocol/features.json` is the exhaustive machine-readable deviation list. Its
Milestone 1 kernel and Milestone 2 sandbox entries record implementation, tests,
and proof evidence; later compatibility features remain `unsupported`.

The project makes no compatibility claim for protocol versions other than 86.
