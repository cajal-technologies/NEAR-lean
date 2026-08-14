# Current-era historical replay

Milestone 12 pins mainnet protocol 86 and a chain of 10,000 consecutive
produced blocks beginning at height `211150000` and ending at `211160021`.
NEAR can skip integer heights, so continuity is checked with both `prev_height`
and `prev_hash`, not by assuming that every integer is a produced block.

`scripts/m12_fetch.py` imports fixed-height block responses and NEAR Data
streamer responses. The deterministic gzip cache stores canonical block
projections, 10,000 included chunk projections, transaction/receipt/outcome/
state-change digests, action and error distributions, and canonical-projection
hashes. The projection avoids non-consensus JSON decorations that differ across
RPC providers while preserving every imported commitment and comparison field.
`replay/sample.json` retains typed examples for the Lean importer. Sparse
samples inside the interval and a protocol-86 deployment at height `211142327`
cover rare action kinds that do not occur in the contiguous chunk slice.

The imported corpus contains all four abstract action kinds, real failed
outcomes, and account, access-key, contract-code, and contract-data changes.
Each selected chunk's input state root is linked to the next included chunk's
committed input root for that shard. The collector rejects a protocol-version
change, broken block chain, missing action class, empty failure corpus, changed
content digest, or incomplete root link.

`scripts/m12_replay.py` provides rolling-digest checkpoints and resume
validation. Its corruption tests require the first difference to name the
block/chunk and the available transaction, receipt, account, and trie-key
identifiers. A checkpoint is bound to the complete corpus digest and both
verified prefixes.

## Compatibility boundary

This is a commitment-and-import replay, not independent full-runtime replay.
The public archive supplies post-execution outcomes, state changes, and state
root commitments, but not the complete archival pre-state or retained chunk
state witnesses required to execute every real chunk from first principles.
The Lean layer imports a committed pre-state root rather than every trie record.

Consequently, M12's provenance, importer, diagnostics, and resumability
deliverables are executable, while historical importer and corpus features stay
`partial`. The v0.4 "exact current-era runtime replayer" release is intentionally
withheld. Closing that gate requires a pinned archival snapshot or state-witness
archive and independent outcome/root recomputation.

`replay/witness-contract.json` makes that missing input boundary executable.
It pins the required nearcore commit, interval, one-to-one chunk fields,
artifact hashes, replay-result fields, and source provenance. `make
m12-exact-gate` validates a supplied `replay/witnesses/index.json`, then executes
its digest-pinned repository runner and requires 10,000 independently matching
outcomes and roots. It remains red while either input is absent. Public FastNEAR
RPC and archival nodes report
`save_latest_witnesses: false`; pinned nearcore only persists the latest 1,800
witnesses, up to 4 GiB, when that non-default debug option is enabled. The
published archival mainnet snapshot is approximately 60 TB, and a regular RPC
node requires at least 2.5 TB of storage, so neither is silently substituted by
an incomplete local snapshot.

The resource bounds come from FastNEAR's [mainnet snapshot
documentation](https://docs.fastnear.com/snapshots/mainnet) and the NEAR node
[RPC hardware requirements](https://near-nodes.io/rpc/hardware-rpc). The witness
retention limits and opt-in behavior are pinned to nearcore's
[`latest_witnesses.rs`](https://github.com/near/nearcore/blob/5af9ca74631e6cf0dae33e77d1a632e94d2952ce/chain/chain/src/store/latest_witnesses.rs).

Run `make m12-validation` for the offline gate. On a clean machine,
`python3 scripts/m12_fetch.py --fetch --check` re-fetches the fixed sources and
requires byte-identical generated artifacts.

## Rolling latest scope

The active scope is a bounded window at the finalized mainnet head, not full
history. `make m12-latest` replaces `replay/latest-report.json` with the newest
100 produced blocks. It verifies the block predecessor/hash chain, protocol 86,
included chunks, imported outcomes and state changes, canonical projection
digests, and adjacent per-shard input-root commitments. The command is capped at
1,000 blocks so it cannot silently become an archival ingestion job.

`make m12-latest-smoke` performs the same checks over the newest 10 finalized
produced blocks without updating tracked artifacts. This workflow remains
`commitment-and-import-replay`; the report fixes
`independentRuntimeExecution` to `false`. The exact witness gate and its
repository-owned runner remain available as an optional stronger mode, but the
latest-only workflow does not depend on archival state.
