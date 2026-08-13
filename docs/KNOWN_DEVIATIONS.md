# Known deviations

The pinned compatibility target is nearcore 2.13.3 at protocol version 86.

At Milestone 10, the repository implements a proof-friendly abstract sandbox. It
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

The concrete execution layer runs checked-in counter, escrow, fungible-token,
NFT, and callback-heavy binaries through the pinned Talos decoder, validator,
small-step interpreter, and `CodeLib.Near.Env` host semantics. Lean and nearcore
consume the same WASM bytes. The benchmark contracts are compact WAT-authored ABI
fixtures, not claims of full NEP-141 or NEP-171 application compatibility.

`NEARLean.WasmHost` adds protocol-86 limits, persistent storage projection,
deterministic SHA-256, and exact external host-cost charging for every import used
by the corpus. Its promise resolver executes callbacks through the same compiled
module, but does not yet route calls between arbitrary deployed WASM modules or
charge trie-node accesses. The M10 L5 comparison deliberately leaves transaction
economics and receipt graphs empty; those surfaces retain their independent M7
and M6 campaigns and are not evidence from the compiled-contract corpus.

The project does not yet:

- validate signatures, nonces, access keys, exact receipt hashes, or transaction fees;
- execute shards, promise-and, promise yield/resume, or arbitrary unsupported WASM modules;
- implement complete transaction gas economics, storage staking, refunds,
  serialization, tries, or state roots;
- compare escrow release, refund receipts, exact gas, or state roots;
- claim equivalence outside the recorded L3/L4 corpora and the scoped M10 L5
  compiled-contract projection;
- replay historical chain data; or
- prove compatibility of any abstract invariant with nearcore.

`protocol/features.json` is the exhaustive machine-readable deviation list.
Milestones 1 through 10 record implementation, test, proof, and mutation evidence;
later features remain `unsupported`.

The project makes no compatibility claim for protocol versions other than 86.
