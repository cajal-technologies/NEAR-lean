# Known deviations

The pinned compatibility target is nearcore 2.13.3 at protocol version 86.

At Milestone 12, the repository implements a proof-friendly abstract sandbox. It
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

The concrete layer now matches pinned near-store state roots for 1,000 synthetic
chunks and exact nearcore vectors for AccountV1, data receipts, successful V1
outcomes, and transaction receipt IDs. Its state records cover accounts, local
contract code, and contract data. The synthetic transition reuses the abstract
action transition before exact record/root projection; it is not evidence that a
second independent action processor matches nearcore. Access keys, action
receipts, serialized failures, newer outcome metadata, delayed/buffered records,
migrations, and real shard state remain outside this scoped L7 corpus.

The historical cache covers 10,000 consecutive produced protocol-86 mainnet
blocks and 10,000 real included chunks. It imports and hashes transactions,
receipts, outcomes, state changes, and adjacent root commitments, but public
fixed-height APIs do not provide a complete pre-state or retained state witness.
Accordingly, it does not independently execute the full nearcore runtime or
recompute historical roots. The M12 exact-runtime exit gate and v0.4 release are
intentionally withheld; the report labels this mode `commitment-and-import-replay`.
The active operational replay is intentionally limited to a rolling latest
window of at most 1,000 finalized produced blocks. It does not attempt
genesis-to-head replay or ingest a full archival database.

The project does not yet:

- validate signatures, nonces, access keys, or transaction fees;
- execute shards, promise-and, promise yield/resume, or arbitrary unsupported WASM modules;
- implement complete transaction gas economics, storage staking, refunds,
  every protocol serialization variant, or migration-aware historical roots;
- compare escrow release, refund receipts, exact transaction gas, or independently
  recomputed state roots outside the scoped synthetic corpus;
- claim equivalence outside the recorded L3/L4 corpora and the scoped M10 L5
  compiled-contract projection;
- independently execute historical chunks; or
- prove compatibility of any abstract invariant with nearcore;
- replay historical chunks from a complete archival trie snapshot or state witness.

`protocol/features.json` is the exhaustive machine-readable deviation list.

## Current protocol and sharding

The active Milestone 13 workflow supports only protocol 86 and the current
mainnet V3 shard layout. Feature activation versions 83 through 86 are gate
metadata and boundary tests, not historical runtime support. Runtime migrations,
upgrade fixtures, resharding state migration, and historical layouts are excluded
by the latest-block-only scope.

Receipt routing is checked against outgoing receipts in the newest finalized
window. The model gives cross-shard receipts a one-block minimum eligibility
delay, but does not model congestion, bandwidth allocation, missed chunks, or an
exact delivery height. Epoch IDs and validator inputs are imported; validator
selection, stake transitions, rewards, and kickouts are not executed.

## Latest stabilization

Milestone 14 measures only the bounded finalized-head import and routing pipeline.
Genesis replay, historical protocol transitions, runtime migrations, resharding,
and independent execution from complete state witnesses remain unsupported.
Throughput and peak RSS are environment-dependent observations, not ratcheted
performance guarantees. The latest provider responses are not a complete archived
input corpus, and neither v0.4 nor v1.0 is claimed.
Milestones 1 through 11 and the non-runtime M12 infrastructure record implementation,
test, proof, and mutation evidence. Scoped latest-window features in M12 through
M14 are implemented or partial as recorded in `protocol/features.json`; the
original exact-runtime and historical exit features remain unsupported.

The project makes no compatibility claim for protocol versions other than 86.
