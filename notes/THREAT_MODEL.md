# Milestone 6 threat model

Contract proofs quantify over arbitrary valid traces. The adversary may choose caller identities,
arguments, transaction order, attached deposits, prepaid gas, cross-contract responses, callback
success or failure, and block height or timestamp advances that satisfy the environment model.

The adversary cannot violate the selected transition system, forge a transition, or mutate state
outside a modeled action. Contract upgrades are forbidden at this milestone; later proofs must
either preserve that restriction, authorize upgrades explicitly, or include migration behavior in
their invariant.

`NEARLean.Verification` is the public proof boundary. Benchmark specifications import only that
module and define their own state, actions, transition system, and properties without changing the
runtime. Liveness claims are conditional on an enabled transition and an explicit progress relation;
fair scheduling assumptions belong in `EnvironmentModel.fair`.
