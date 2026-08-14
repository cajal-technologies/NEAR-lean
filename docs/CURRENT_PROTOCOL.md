# Current protocol and sharding

Milestone 13 is intentionally scoped to the latest finalized mainnet window. The
project does not replay historical upgrades, migrations, or shard-layout changes.

`NEARLean/Protocol.lean` selects exactly protocol 86 and provides activation
metadata for representative stable features at versions 83 through 86. The
immediately-before and at-activation cases are executable tests and a checked Lean
theorem. A runtime configuration is returned only for version 86; the earlier
numbers are feature-gate metadata, not supported historical runtimes.

The current mainnet shard layout is V3 with account boundaries
`650`, `aurora`, `aurora-0`, `earn.kaiching`, `game.hot.tg`,
`game.hot.tg-0`, `kkuuue2akv_1630967379.near`, `tge-lockup.sweat`, and
`wallet.ka`. Their shard IDs are `[10, 11, 1, 8, 9, 6, 7, 4, 12, 13]`.
The layout is read from `EXPERIMENTAL_protocol_config` and matches the pinned
nearcore V3 account-range algorithm. Lean proves that the checked layout is well
formed and that routing is deterministic.

## Latest-window evidence

`make m13-latest` refreshes `replay/latest-sharding-report.json` from the newest
100 finalized produced blocks. For every outgoing receipt, the collector:

1. checks a non-system predecessor against the shard that produced the receipt;
2. routes the receiver through the current account boundaries;
3. classifies the receipt as cross-shard when source and target differ; and
4. rejects missing fields or any source-route mismatch.

The report also imports current and next epoch IDs, epoch height and start height,
epoch length, validator count, and proposal count. The validator snapshot is
explicitly scoped to the replay head's epoch, and the report checks that the head
height falls inside that epoch; it does not claim validator coverage for an older
epoch if the rolling window crosses an epoch boundary. `make m13-latest-smoke`
repeats the checks over the newest 10 finalized produced blocks in online CI.

The Lean delay model states only minimum eligibility: a local receipt may be
eligible at the producing height, while a cross-shard receipt is eligible no
earlier than the following height. Congestion, bandwidth scheduling, missed
chunks, and exact delivery height are not modeled.

## Intentionally unsupported

- historical runtime configurations and migrations;
- upgrade-boundary fixtures and replay across protocol changes;
- resharding state migration;
- validator selection, rewards, stake changes, and kickouts; and
- independent runtime execution or state-root recomputation.

These omissions follow the selected latest-block-only operating scope. The report
is current configuration and receipt-routing import evidence, not an exact
historical or independent-runtime replay claim.

## Scoped exit decision

The current-version configuration, activation gates, V3 routing, contract version
policies, and latest-window receipt-routing gate are complete for protocol 86.
Cross-shard delivery and epoch transitions remain partial at their documented
boundaries. The original M13 gates for two historical upgrades, migrations, and
exact replay across an upgrade or cross-shard interval are intentionally not
claimed. No release tag is cut for this scoped checkpoint.
