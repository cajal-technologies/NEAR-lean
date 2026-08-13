# Known deviations

The pinned compatibility target is nearcore 2.13.3 at protocol version 86.

At Milestone 9, the repository implements a proof-friendly abstract sandbox. It
executes account creation, liquid-balance transfers, native-contract deployment,
and synchronous function calls. Failed calls restore the full abstract pre-state,
and views are pure. The native backend contains counter, simple escrow, and a
stateless cross-contract callback fixture.

These definitions are not a general compatibility claim: identifiers use only
abstract length bounds, balances and gas are unbounded naturals, state uses
association lists, and successful calls use a flat gas marker.

The pinned nearcore oracle establishes L3 equivalence for the generated
basic-action corpus: account creation, transfer, counter deployment and calls, and
insufficient-balance failures. The canonicalizer waits for finality and adds gas
burn back to the payer before comparing abstract balances. This is intentional:
exact gas and fee comparison begins at Milestone 7.

The receipt layer represents receipt and data identifiers as fresh naturals and
canonicalizes nearcore hashes by semantic creation order. Transactions create a
root action receipt; action receipts can produce data dependencies and callbacks;
and missing inputs postpone callbacks until their data arrives. The L4 campaign
covers a successful echo call and callback across two contracts. Gas refunds are
projected out of its semantic graph and data-receipt delivery has no execution
outcome, matching the chosen comparison surface.

The concrete execution layer now runs the checked-in counter binary through the
pinned Talos decoder, validator, and small-step interpreter. Lean and nearcore
consume the same `counter.wasm` bytes. The Milestone 9 NEAR host is intentionally
limited to the six storage/register/return/log imports used by that counter;
richer context, promise, crypto, and exact host-gas behavior belongs to
Milestone 10.

The project does not yet:

- validate signatures, nonces, access keys, exact receipt hashes, or transaction fees;
- execute shards, promise-and, promise yield/resume, or arbitrary unsupported WASM modules;
- implement exact gas economics, storage staking, refunds, serialization, tries, or state roots;
- compare escrow release, refund receipts, exact gas, or state roots;
- claim equivalence above L4 or outside the recorded basic-action and callback corpora;
- replay historical chain data; or
- prove compatibility of any abstract invariant with nearcore.

`protocol/features.json` is the exhaustive machine-readable deviation list.
Milestones 1 through 9 record implementation, test, proof, and mutation evidence;
later features remain `unsupported`.

The project makes no compatibility claim for protocol versions other than 86.
