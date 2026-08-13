# Metric dashboard

The authoritative dashboard is the generated `scorecard.json` artifact. It is
kept deliberately multidimensional rather than collapsed into one completion
percentage.

At Milestone 0 it reports:

- the exact Lean, nearcore, and protocol baseline;
- feature counts by lifecycle status and verified weighted coverage;
- the strongest differential observation level reached;
- the number of project declarations under transitive axiom audit;
- declarations with approved axiom dependencies; and
- the names and number of headline theorems contained in that complete audit.

Future milestones will extend the schema with positive, negative, differential,
proof-obligation, mutation, replay, performance, and trusted-adapter metrics. New
metrics must be derived from durable manifests or test artifacts rather than
manually asserted numbers.
