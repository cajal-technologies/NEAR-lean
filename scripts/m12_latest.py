#!/usr/bin/env python3
"""Replay a bounded rolling window at the finalized mainnet head."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import urllib.request
from collections import Counter

from m12_fetch import (
    PROTOCOL_VERSION,
    STREAM_URL,
    canonical,
    fetch_stream,
    parallel_fetch,
    request_json,
    summarize_shard,
)


ROOT = pathlib.Path(__file__).resolve().parents[1]
REPORT = ROOT / "replay/latest-report.json"
LATEST_FINAL_URL = "https://mainnet.neardata.xyz/v0/last_block/final"
DEFAULT_COUNT = 100
MAX_COUNT = 1_000


def counter_add(target: Counter[str], values: object) -> None:
    if isinstance(values, dict):
        target.update(
            {key: value for key, value in values.items() if isinstance(key, str) and isinstance(value, int)}
        )


def report_from_streams(streams: list[dict[str, object]], requested: int) -> dict[str, object]:
    if len(streams) != requested:
        raise ValueError(f"latest replay expected {requested} produced blocks, got {len(streams)}")
    streams.sort(key=lambda stream: stream["block"]["header"]["height"])
    blocks: list[dict[str, object]] = []
    chunks: list[dict[str, object]] = []
    actions: Counter[str] = Counter()
    errors: Counter[str] = Counter()
    changes: Counter[str] = Counter()
    outcomes = 0
    pending_shards: set[int] = set()
    root_links = 0
    for stream_index, stream in enumerate(streams):
        block = stream["block"]
        header = block["header"]
        if header["latest_protocol_version"] != PROTOCOL_VERSION:
            raise ValueError(
                f"latest replay left protocol {PROTOCOL_VERSION} at {header['height']}"
            )
        summary = {
            "height": header["height"],
            "hash": header["hash"],
            "prevHash": header["prev_hash"],
            "prevHeight": header["prev_height"],
            "protocolVersion": header["latest_protocol_version"],
            "prevStateRoot": header["prev_state_root"],
            "outcomeRoot": header["outcome_root"],
            "chunksIncluded": header["chunks_included"],
            "chunkMask": header["chunk_mask"],
        }
        if stream_index and (
            summary["prevHeight"] != blocks[-1]["height"]
            or summary["prevHash"] != blocks[-1]["hash"]
        ):
            raise ValueError(f"latest block chain differs at {summary['height']}")
        blocks.append(summary)
        for shard in sorted(stream["shards"], key=lambda value: value["shard_id"]):
            if shard.get("chunk") is None:
                continue
            chunk_header = shard["chunk"]["header"]
            if chunk_header["height_included"] != header["height"]:
                continue
            chunk, _ = summarize_shard(header["height"], header["hash"], shard)
            shard_id = chunk["shardId"]
            if shard_id in pending_shards:
                root_links += 1
            pending_shards.add(shard_id)
            chunks.append(chunk)
            outcomes += chunk["outcomes"]
            counter_add(actions, chunk["actionKinds"])
            counter_add(errors, chunk["errorClasses"])
            counter_add(changes, chunk["stateChangeKinds"])
    block_digest = hashlib.sha256(b"".join(canonical(block) for block in blocks)).hexdigest()
    chunk_digest = hashlib.sha256(b"".join(canonical(chunk) for chunk in chunks)).hexdigest()
    head = streams[-1]["block"]["header"]
    return {
        "schemaVersion": 1,
        "network": "mainnet",
        "protocolVersion": PROTOCOL_VERSION,
        "scope": "bounded-latest-finalized-window",
        "replayMode": "commitment-and-import-replay",
        "source": STREAM_URL,
        "requestedProducedBlocks": requested,
        "producedBlocks": len(blocks),
        "oldestHeight": blocks[0]["height"],
        "latestHeight": blocks[-1]["height"],
        "latestBlockHash": blocks[-1]["hash"],
        "latestTimestampNanosec": head["timestamp_nanosec"],
        "includedChunks": len(chunks),
        "adjacentInputRootLinks": root_links,
        "importedOutcomes": outcomes,
        "actionKinds": dict(sorted(actions.items())),
        "errorClasses": dict(sorted(errors.items())),
        "stateChangeKinds": dict(sorted(changes.items())),
        "blockProjectionSha256": block_digest,
        "chunkProjectionSha256": chunk_digest,
        "independentRuntimeExecution": False,
        "firstDifference": None,
    }


def latest_stream() -> dict[str, object]:
    request = urllib.request.Request(
        LATEST_FINAL_URL, headers={"user-agent": "NEAR-Lean-M12-latest"}
    )
    value = request_json(request)
    if not isinstance(value, dict) or value.get("block") is None:
        raise ValueError("latest finalized NEAR Data response is invalid")
    return value


def latest_streams(count: int, workers: int) -> list[dict[str, object]]:
    if count < 2 or count > MAX_COUNT:
        raise ValueError(f"latest replay count must be between 2 and {MAX_COUNT}")
    latest = latest_stream()
    latest_height = latest["block"]["header"]["height"]
    slack = max(64, count // 10)
    candidates = parallel_fetch(
        fetch_stream, range(latest_height - count - slack + 1, latest_height + 1), workers
    )
    streams = [stream for stream in candidates if stream is not None]
    if not any(
        stream["block"]["header"]["hash"] == latest["block"]["header"]["hash"]
        for stream in streams
    ):
        streams.append(latest)
    streams.sort(key=lambda stream: stream["block"]["header"]["height"])
    return streams[-count:]


def live_report(count: int, workers: int) -> dict[str, object]:
    return report_from_streams(latest_streams(count, workers), count)


def report_errors(report: object) -> list[str]:
    if not isinstance(report, dict):
        return ["latest replay report must be an object"]
    errors: list[str] = []
    if report.get("schemaVersion") != 1 or report.get("network") != "mainnet":
        errors.append("latest replay schema or network differs")
    if report.get("protocolVersion") != PROTOCOL_VERSION:
        errors.append("latest replay protocol version differs")
    if report.get("scope") != "bounded-latest-finalized-window":
        errors.append("latest replay scope must be explicit")
    if report.get("replayMode") != "commitment-and-import-replay":
        errors.append("latest replay mode must remain explicit")
    blocks = report.get("producedBlocks")
    if not isinstance(blocks, int) or blocks < 2 or blocks > MAX_COUNT:
        errors.append("latest replay produced-block count is outside its bounded scope")
    if report.get("requestedProducedBlocks") != blocks:
        errors.append("latest replay produced-block count differs from its request")
    if not isinstance(report.get("includedChunks"), int) or report["includedChunks"] < 0:
        errors.append("latest replay included-chunk count is invalid")
    if report.get("independentRuntimeExecution") is not False:
        errors.append("latest replay must not overclaim independent runtime execution")
    for field in ("blockProjectionSha256", "chunkProjectionSha256"):
        value = report.get(field)
        if not isinstance(value, str) or len(value) != 64:
            errors.append(f"latest replay {field} is invalid")
    return errors


def self_test() -> None:
    streams: list[dict[str, object]] = []
    previous_hash = "genesis"
    for height in range(2):
        block_hash = f"block-{height}"
        streams.append(
            {
                "block": {
                    "header": {
                        "height": height,
                        "hash": block_hash,
                        "prev_hash": previous_hash,
                        "prev_height": height - 1 if height else 0,
                        "latest_protocol_version": PROTOCOL_VERSION,
                        "prev_state_root": f"state-{height}",
                        "outcome_root": f"outcomes-{height}",
                        "chunks_included": 0,
                        "chunk_mask": [],
                        "timestamp_nanosec": str(height),
                    }
                },
                "shards": [],
            }
        )
        previous_hash = block_hash
    report = report_from_streams(streams, 2)
    assert report["producedBlocks"] == 2 and not report_errors(report)
    streams[1]["block"]["header"]["prev_hash"] = "wrong"
    try:
        report_from_streams(streams, 2)
    except ValueError:
        pass
    else:
        raise AssertionError("discontinuous latest block window was accepted")
    print("bounded latest replay tests passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=DEFAULT_COUNT)
    parser.add_argument("--workers", type=int, default=16)
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--check-report", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
    if arguments.check_report:
        errors = report_errors(json.loads(REPORT.read_text(encoding="utf-8")))
        if errors:
            raise SystemExit("\n".join(errors))
    if arguments.output or arguments.live:
        report = live_report(arguments.count, arguments.workers)
        if arguments.output:
            output = arguments.output if arguments.output.is_absolute() else ROOT / arguments.output
            output.write_text(
                json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
            )
        print(json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
