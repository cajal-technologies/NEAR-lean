#!/usr/bin/env python3
"""Reproduce the Milestone 11 concrete-semantics evidence report."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import subprocess


ROOT = pathlib.Path(__file__).resolve().parents[1]
CORPUS = ROOT / "concrete/synthetic-chunks.json"
ORACLE_SOURCE = ROOT / "Oracle/nearcore/m11_oracle.rs"
VALIDATOR = ROOT / ".lake/build/bin/m11Validation"
REPORT = ROOT / "concrete/report.json"


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generated() -> dict[str, object]:
    completed = subprocess.run(
        [str(VALIDATOR)], cwd=ROOT, check=True, text=True, capture_output=True
    )
    evidence = json.loads(completed.stdout.strip().splitlines()[-1])
    corpus = json.loads(CORPUS.read_text(encoding="utf-8"))
    return {
        "schemaVersion": 1,
        "protocolVersion": corpus["protocolVersion"],
        "nearcoreCommit": corpus["nearcoreCommit"],
        "observationLevel": evidence["observationLevel"],
        "syntheticChunks": evidence["chunks"],
        "identicalStateRoots": evidence["rootsMatched"],
        "serializationVectors": evidence["serializationVectors"],
        "negativeVectors": evidence["negativeVectors"],
        "refinementTheorems": [
            "NEARLean.Concrete.concreteStep_refines_abstract"
        ],
        "corpus": {
            "path": "concrete/synthetic-chunks.json",
            "sha256": digest(CORPUS),
            "seed": corpus["seed"],
        },
        "nearcoreOracle": {
            "path": "Oracle/nearcore/m11_oracle.rs",
            "sha256": digest(ORACLE_SOURCE),
            "execution": (
                "compiled as a near-store example in the pinned nearcore workspace"
            ),
        },
        "coverage": {
            "exactBorsh": [
                "AccountV1",
                "DataReceipt",
                "ExecutionOutcome::SuccessValue with ExecutionMetadata::V1",
                "raw state-change batches",
            ],
            "identifiers": ["transaction receipt IDs"],
            "trieRecords": ["account", "contract code", "contract data"],
            "transitions": ["transfer", "counter increment"],
        },
        "trustedAdapters": [
            "The checked-in corpus was emitted by the pinned near-store helper; CI checks its hash and independently replays it but does not rebuild nearcore.",
            "SHA-256 is an executable Lean implementation checked by known-answer and nearcore vectors, not a cryptographic security proof.",
            "The concrete transition deliberately reuses the proved abstract action transition and adds exact record/root projection; independent full runtime action execution begins with historical replay.",
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    encoded = json.dumps(generated(), indent=2) + "\n"
    if arguments.check:
        if REPORT.read_text(encoding="utf-8") != encoded:
            raise SystemExit("concrete/report.json is stale")
    else:
        REPORT.parent.mkdir(parents=True, exist_ok=True)
        REPORT.write_text(encoded, encoding="utf-8")


if __name__ == "__main__":
    main()
