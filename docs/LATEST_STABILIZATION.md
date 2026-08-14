# Latest-window stabilization

Milestone 14 is scoped to stabilizing the rolling finalized-head workflow. It
does not expand compatibility toward genesis or historical protocol eras.

`make m14-latest` acquires one 100-produced-block window and feeds the same block
objects to the M12 commitment importer and M13 sharding validator. The combined
report rejects different ending heights or hashes, broken continuity, protocol
or shard-layout changes, receipt-routing mismatches, and any observed projection
first difference.

The report records the finalized-head discovery endpoint as well as both block
and RPC sources. `referenceNearcoreCommit` identifies the repository's pinned
compatibility reference; it does not claim that either live provider runs that
nearcore commit.

The checked `replay/latest-stabilization-report.json` records:

- the latest contiguous window, one observed protocol era, and zero exactly
  replayed protocol eras;
- included chunks, outcomes, routed receipts, and cross-shard receipts;
- observed projection-mismatch and upgrade-boundary counts;
- elapsed wall time, blocks and chunks per second, and process peak RSS;
- the repository-wide validation mutation score and the latest routing pass
  score; and
- a trusted-assumption summary plus the complete intentional-exclusion list for
  this scope. The full trust inventory remains in `TRUSTED_COMPUTING_BASE.md`.

`make m14-latest-smoke` repeats the campaign over the newest 10 finalized
produced blocks in online CI. Performance numbers are observations of the
machine, network, provider caches, and process lifetime used for a run. They are
required to be present, positive, and internally consistent, but are not
performance ratchets. Peak RSS supports the macOS and Linux environments used by
the project; other operating systems are not claimed.

## Scoped exit decision

The bounded latest-window stabilization gate is complete when offline CI, online
CI, the checked 100-block report, the live 10-block smoke, and corruption tests
all pass with zero observed projection mismatches. Exact-runtime divergences are
not measured because independent execution is excluded. Every non-current goal
is an explicit scope exclusion.

The original M14 exit target is not claimed: genesis-to-checkpoint roots and
outcomes are not replayed, historical transitions and stratified historical
sampling are not supported, and the latest inputs are fetched from live
providers rather than a reproducible archived corpus. `v1.0` is therefore
withheld.
