# Known deviations

The pinned compatibility target is nearcore 2.13.3 at protocol version 86.

At Milestone 3, the repository implements a proof-friendly abstract sandbox. It
executes account creation, liquid-balance transfers, native-contract deployment,
and synchronous function calls. Failed calls restore the full abstract pre-state,
and views are pure. The native backend contains only counter and simple escrow
programs.

These definitions are not a general compatibility claim: identifiers use only
abstract length bounds, balances and gas are unbounded naturals, state uses
association lists, and successful calls use a flat gas marker.

The pinned nearcore oracle establishes L3 equivalence for the generated
basic-action corpus: account creation, transfer, counter deployment and calls, and
insufficient-balance failures. The canonicalizer waits for finality and adds gas
burn back to the payer before comparing abstract balances. This is intentional:
exact gas and fee comparison begins at Milestone 7.

The project does not yet:

- execute transactions, receipts, blocks, promises, host functions, or WASM;
- implement gas, deposits, storage staking, refunds, serialization, tries, or state roots;
- compare escrow release, receipt identity or order, exact gas, or state roots;
- claim equivalence above L3 or outside the recorded basic-action corpus;
- replay historical chain data; or
- prove compatibility of any abstract invariant with nearcore.

`protocol/features.json` is the exhaustive machine-readable deviation list. Its
Milestone 1 kernel, Milestone 2 sandbox, and Milestone 3 differential entries
record implementation, test, and proof evidence; later features remain
`unsupported`.

The project makes no compatibility claim for protocol versions other than 86.
