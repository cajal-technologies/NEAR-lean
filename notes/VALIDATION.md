# Validation campaigns

Milestone 8 adds a deterministic model campaign and two scheduled nearcore
corpora. `make validation-campaign` executes one million generated actions over
states, actions, receipts, and block groupings. Its checked-in report records
grammar and manifest coverage, five metamorphic relations, full-seed replay, and
the semantic mutation score.

`make differential-nightly` executes 5,000 visible and 5,000 held-out L4 receipt
traces. The two descriptors in `differential/corpora` use disjoint seed ranges.
The held-out range is operationally isolated from the visible corpus, although
its descriptor is necessarily public in this repository.

Every supported manifest feature must record positive, negative, and
differential evidence. For protocol features, differential evidence means an
observation compared with the pinned nearcore oracle. Proof and validation
features have no independent nearcore result; for those features, differential
evidence means executable participation in the same pinned generation,
comparison, minimization, or reporting stack. This distinction is intentional
and is also recorded in the feature manifest.

The differential driver minimizes failing action sequences and writes the result
under `differential/failures`. These files are permanent regression fixtures.
Field-level and receipt-graph shrinking are deferred until later milestones add
richer action grammars.

Milestone 12 adds `make m12-validation`. Its checked-in protocol-86 mainnet cache
contains 10,000 consecutive produced blocks and 10,000 real included chunks.
The gate checks canonical source hashes, predecessor continuity, typed sample
imports, action/error strata, adjacent state-root commitments, checkpoint/resume,
and first-difference mutations. It deliberately reports
`commitment-and-import-replay`: complete pre-state/state witnesses are absent, so
historical outcomes and roots are preserved and linked rather than independently
recomputed by the Lean runtime.

The intentionally bounded live workflow uses `make m12-latest` to refresh a
checked 100-block finalized-head artifact and `make m12-latest-smoke` for a
read-only 10-block online check. Both reject broken predecessor continuity or a
protocol-version change and retain the explicit non-independent replay label.

Milestone 13 adds `make m13-validation` for the protocol-86 feature gates,
current V3 shard layout, receipt routing, minimum cross-shard delay, epoch input
validation, and checked 100-block sharding report. `make m13-latest` refreshes
that artifact, while `make m13-latest-smoke` repeats the RPC configuration and
routing checks over the newest 10 finalized produced blocks. Any non-system
predecessor whose routed shard differs from the producing shard is a hard failure.
