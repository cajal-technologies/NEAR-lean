# Metric dashboard

The authoritative dashboard is the generated `scorecard.json` artifact. It is
kept deliberately multidimensional rather than collapsed into one completion
percentage.

At Milestone 2 it reports:

- the exact Lean, nearcore, and protocol baseline;
- feature counts by lifecycle status and verified weighted coverage;
- the strongest differential observation level reached;
- the number of project declarations under transitive axiom audit;
- declarations with approved axiom dependencies; and
- the names and number of headline theorems contained in that complete audit.

The six abstract-kernel and seven sandbox features record executable positive and
negative tests. Their proof obligations cover initialization, invariant
preservation, deterministic execution, failed-call rollback, view purity, and
unrelated-account noninterference. The test driver runs 100 parameterized transfer
scenarios in addition to counter, escrow, failure, and boundary cases. Features
remain below `verified` because no differential nearcore coverage or
abstract-to-concrete refinement exists yet.

Future milestones will extend the schema with positive, negative, differential,
proof-obligation, mutation, replay, performance, and trusted-adapter metrics. New
metrics must be derived from durable manifests or test artifacts rather than
manually asserted numbers.
