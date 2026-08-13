#!/usr/bin/env python3
"""Validate, checkpoint, resume, and diagnose the M12 commitment replay."""

from __future__ import annotations

import argparse
import copy
import gzip
import hashlib
import json
import pathlib
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
CACHE = ROOT / "replay/current-era.json.gz"


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def corpus_digest(corpus: dict[str, object]) -> str:
    return hashlib.sha256(canonical(corpus)).hexdigest()


def load() -> dict[str, object]:
    return json.loads(gzip.decompress(CACHE.read_bytes()))


def diagnostic(
    scope: str, index: int, field: str, expected: object, actual: object, item: dict[str, object]
) -> dict[str, object]:
    identifiers = item.get("firstIdentifiers", {})
    return {
        "scope": scope,
        "index": index,
        "field": field,
        "expected": expected,
        "actual": actual,
        "blockHeight": item.get("blockHeight", item.get("height")),
        "chunk": item.get("chunkHash"),
        "transaction": identifiers.get("transaction"),
        "receipt": identifiers.get("receipt"),
        "account": identifiers.get("account"),
        "trieKey": identifiers.get("trieKey"),
    }


def compare(expected: dict[str, object], actual: dict[str, object]) -> dict[str, object] | None:
    expected_blocks = expected["blocks"]
    actual_blocks = actual.get("blocks", [])
    for index, block in enumerate(expected_blocks):
        if index >= len(actual_blocks):
            return diagnostic("block", index, "missing", block, None, block)
        for field in (
            "height",
            "hash",
            "prevHash",
            "prevHeight",
            "protocolVersion",
            "prevStateRoot",
            "outcomeRoot",
            "sourceSha256",
        ):
            if actual_blocks[index].get(field) != block.get(field):
                return diagnostic(
                    "block", index, field, block.get(field), actual_blocks[index].get(field), block
                )
    expected_chunks = expected["chunks"]
    actual_chunks = actual.get("chunks", [])
    for index, chunk in enumerate(expected_chunks):
        if index >= len(actual_chunks):
            return diagnostic("chunk", index, "missing", chunk, None, chunk)
        for field in (
            "blockHeight",
            "blockHash",
            "shardId",
            "chunkHash",
            "inputStateRoot",
            "outputStateRoot",
            "outcomeRoot",
            "transactionSha256",
            "receiptSha256",
            "outcomeSha256",
            "stateChangeSha256",
        ):
            if actual_chunks[index].get(field) != chunk.get(field):
                return diagnostic(
                    "chunk", index, field, chunk.get(field), actual_chunks[index].get(field), chunk
                )
    return None


def rolling(values: list[dict[str, object]], count: int) -> str:
    state = b""
    for value in values[:count]:
        state = hashlib.sha256(state + canonical(value)).digest()
    return state.hex()


def checkpoint(corpus: dict[str, object], block_count: int, chunk_count: int) -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "corpusSha256": corpus_digest(corpus),
        "nextBlock": block_count,
        "nextChunk": chunk_count,
        "blockRollingSha256": rolling(corpus["blocks"], block_count),
        "chunkRollingSha256": rolling(corpus["chunks"], chunk_count),
    }


def resume(corpus: dict[str, object], saved: dict[str, object]) -> dict[str, object]:
    if saved.get("corpusSha256") != corpus_digest(corpus):
        raise ValueError("checkpoint corpus digest differs")
    block_count = saved.get("nextBlock")
    chunk_count = saved.get("nextChunk")
    if not isinstance(block_count, int) or not isinstance(chunk_count, int):
        raise ValueError("checkpoint indices are invalid")
    if saved.get("blockRollingSha256") != rolling(corpus["blocks"], block_count):
        raise ValueError("checkpoint block prefix differs")
    if saved.get("chunkRollingSha256") != rolling(corpus["chunks"], chunk_count):
        raise ValueError("checkpoint chunk prefix differs")
    return checkpoint(corpus, len(corpus["blocks"]), len(corpus["chunks"]))


def self_test() -> None:
    corpus = load()
    with tempfile.TemporaryDirectory() as directory:
        path = pathlib.Path(directory) / "checkpoint.json"
        saved = checkpoint(corpus, 5_000, 5_000)
        path.write_text(json.dumps(saved), encoding="utf-8")
        completed = resume(corpus, json.loads(path.read_text(encoding="utf-8")))
        assert completed["nextBlock"] == 10_000 and completed["nextChunk"] == 10_000
    corrupted = copy.deepcopy(corpus)
    target = next(
        index
        for index, chunk in enumerate(corrupted["chunks"])
        if all(
            chunk.get("firstIdentifiers", {}).get(key)
            for key in ("transaction", "receipt", "account", "trieKey")
        )
    )
    corrupted["chunks"][target]["outputStateRoot"] = "corrupted"
    difference = compare(corpus, corrupted)
    assert difference is not None and difference["field"] == "outputStateRoot"
    assert all(difference.get(key) is not None for key in ("transaction", "receipt", "account", "trieKey"))
    bad_checkpoint = checkpoint(corpus, 5_000, 5_000)
    bad_checkpoint["chunkRollingSha256"] = "0" * 64
    try:
        resume(corpus, bad_checkpoint)
    except ValueError:
        pass
    else:
        raise AssertionError("corrupted checkpoint was accepted")
    print("historical first-difference and resume tests passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--checkpoint", type=pathlib.Path)
    parser.add_argument("--resume", type=pathlib.Path)
    parser.add_argument("--stop-after", type=int, default=5_000)
    arguments = parser.parse_args()
    corpus = load()
    if arguments.check:
        if compare(corpus, corpus) is not None:
            raise SystemExit("self replay differs")
        completed = checkpoint(corpus, len(corpus["blocks"]), len(corpus["chunks"]))
        print(json.dumps(completed, sort_keys=True))
    if arguments.checkpoint:
        value = checkpoint(corpus, arguments.stop_after, arguments.stop_after)
        arguments.checkpoint.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    if arguments.resume:
        value = resume(corpus, json.loads(arguments.resume.read_text(encoding="utf-8")))
        print(json.dumps(value, sort_keys=True))
    if arguments.self_test:
        self_test()


if __name__ == "__main__":
    main()
