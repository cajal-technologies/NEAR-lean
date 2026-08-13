# Metric dashboard

The authoritative dashboard is the generated `scorecard.json` artifact. It is
kept deliberately multidimensional rather than collapsed into one completion
percentage.

At Milestone 9 it reports:

- the exact Lean, nearcore, and protocol baseline;
- feature counts by lifecycle status and verified weighted coverage;
- the strongest differential observation level reached;
- the number of project declarations under transitive axiom audit;
- declarations with approved axiom dependencies;
- the names and number of headline theorems contained in that complete audit;
- the deterministic differential seed, trace count, action count, and first
  difference;
- the receipt, block, and economics campaign results; and
- the million-action validation seed, mutation score, supported-feature coverage,
  and bit-for-bit replay digest; and
- the pinned Talos commit, WebAssembly instruction coverage, and parser/interpreter
  mutation score.

The six abstract-kernel and seven sandbox features record executable positive and
negative tests. Their proof obligations cover initialization, invariant
preservation, deterministic execution, failed-call rollback, view purity, and
unrelated-account noninterference. The test driver runs 100 parameterized transfer
scenarios in addition to counter, escrow, failure, and boundary cases.

The checked-in differential report records 1,000 passing traces and 1,200 actions
at L3 against nearcore 2.13.3. The permanent counter fixture covers return bytes,
logs, balance, and raw storage, while generated failures cover error categories
and rollback. Features remain below `verified` where differential coverage or
relevant proof obligations are incomplete.

The receipt report records 10,000 passing cross-contract traces at L4. It compares
the transaction root, target and callback receipt identities, child order,
executor accounts, statuses, and return values. The receipt-machine proofs cover
fresh-ID uniqueness, dependency safety, well-formedness preservation,
determinism, and lifecycle accounting.

The scheduled validation suite runs one million model actions and two disjoint
5,000-trace nearcore corpora. New metrics must be derived from durable manifests
or test artifacts rather than manually asserted numbers.
