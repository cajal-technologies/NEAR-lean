# AGENTS.md

This repository implements the NEAR Protocol chain and smart-contract runtime in Lean 4, with the goal of executable compatibility with nearcore and formal verification of contract behavior.

Before developing here, consult `notes/milestones.html` for the current scope and completion criteria, and `notes/evaluation.html` for the correctness signals and metrics that changes should satisfy.
Keep implementation, tests, proofs, and documentation aligned with those plans.


## Development guidelines

General principles:
- Be concise while writing code, only write comments if they are not going to be obsolete soon, keep comments concise and useful, no overbloated comments.
- Test driven development is always encouraged, new features should have tests and examples that makes them easy to understand and to review.

LEAN:
- When working with LEAN always use lean-lsp-mcp skill and lean-lcp since it is few order of magnitudes faster than using lake build every time.
