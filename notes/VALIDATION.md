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
