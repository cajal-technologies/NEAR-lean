#!/usr/bin/env python3
"""Generate the Milestone 12 historical commitment-replay report."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import pathlib
from collections import Counter


ROOT = pathlib.Path(__file__).resolve().parents[1]
CACHE = ROOT / "replay/current-era.json.gz"
SAMPLE = ROOT / "replay/sample.json"
REPORT = ROOT / "replay/report.json"


def file_digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generated() -> dict[str, object]:
    corpus = json.loads(gzip.decompress(CACHE.read_bytes()))
    sample = json.loads(SAMPLE.read_text(encoding="utf-8"))
    actions = Counter()
    errors = Counter()
    changes = Counter()
    outcomes = 0
    for chunk in corpus["chunks"]:
        actions.update(chunk["actionKinds"])
        errors.update(chunk["errorClasses"])
        changes.update(chunk["stateChangeKinds"])
        outcomes += chunk["outcomes"]
    for item in sample["samples"]:
        actions.update(item["header"]["actionKinds"])
        errors.update(item["header"]["errorClasses"])
        changes.update(item["header"]["stateChangeKinds"])
    return {
        "schemaVersion": 1,
        "network": corpus["network"],
        "protocolVersion": corpus["protocolVersion"],
        "nearcoreCommit": corpus["nearcoreCommit"],
        "replayMode": "commitment-and-import-replay",
        "observationLevel": "L7-commitments",
        "contiguousProducedBlocks": corpus["interval"]["blocks"],
        "startHeight": corpus["interval"]["startHeight"],
        "endHeight": corpus["interval"]["endHeight"],
        "stratifiedChunks": corpus["stratifiedChunks"]["count"],
        "adjacentStateRootLinks": corpus["stratifiedChunks"]["count"],
        "importedOutcomesPreserved": outcomes,
        "actionKinds": dict(sorted(actions.items())),
        "errorClasses": dict(sorted(errors.items())),
        "stateChangeKinds": dict(sorted(changes.items())),
        "sampleChunks": len(sample["samples"]),
        "cache": {
            "path": "replay/current-era.json.gz",
            "sha256": file_digest(CACHE),
            "blockContentSha256": corpus["interval"]["sha256"],
            "chunkContentSha256": corpus["stratifiedChunks"]["sha256"],
        },
        "sample": {"path": "replay/sample.json", "sha256": file_digest(SAMPLE)},
        "checkpointResume": True,
        "firstDifferenceIdentifiers": [
            "block",
            "chunk",
            "transaction",
            "receipt",
            "account",
            "trieKey",
        ],
        "cleanCacheReproductionCommand": "python3 scripts/m12_fetch.py --fetch --check",
        "independentRuntimeExecution": False,
        "knownDeviation": (
            "The cache independently verifies real block/chunk continuity, imported outcomes, "
            "content digests, and adjacent state-root commitments. It does not execute nearcore's "
            "full runtime from a complete archival pre-state or retained chunk state witnesses."
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    encoded = json.dumps(generated(), indent=2, ensure_ascii=False) + "\n"
    if arguments.check:
        if REPORT.read_text(encoding="utf-8") != encoded:
            raise SystemExit("replay/report.json is stale")
    else:
        REPORT.write_text(encoded, encoding="utf-8")


if __name__ == "__main__":
    main()
