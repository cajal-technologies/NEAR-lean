#!/usr/bin/env python3
"""Fetch and reproduce the pinned Milestone 12 mainnet replay corpus."""

from __future__ import annotations

import argparse
import concurrent.futures
import gzip
import hashlib
import json
import pathlib
import time
import urllib.error
import urllib.request
from collections import Counter


ROOT = pathlib.Path(__file__).resolve().parents[1]
CACHE = ROOT / "replay/current-era.json.gz"
SAMPLE = ROOT / "replay/sample.json"
DOWNLOAD_CACHE = ROOT / ".lake/m12-downloads"
START_HEIGHT = 211_150_000
SCAN_END_HEIGHT = START_HEIGHT + 10_199
STREAM_SCAN_END_HEIGHT = START_HEIGHT + 1_199
SUPPLEMENTAL_HEIGHTS = [211_142_327]
PROTOCOL_VERSION = 86
NEARCORE_COMMIT = "5af9ca74631e6cf0dae33e77d1a632e94d2952ce"
RPC_URLS = [
    "https://free.rpc.fastnear.com",
    "https://rpc.mainnet.fastnear.com",
    "https://near.lava.build",
]
STREAM_URL = "https://mainnet.neardata.xyz/v0/block/{height}"
STREAM_FETCH_URL = "https://a3.mainnet.neardata.xyz/v0/block/{height}"


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def digest(value: object) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def request_json(
    request: urllib.request.Request,
    attempts: int = 12,
    missing_statuses: set[int] | None = None,
) -> object | None:
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if missing_statuses and error.code in missing_statuses:
                return None
            if attempt + 1 == attempts:
                raise
            stagger = int(hashlib.sha256(request.full_url.encode()).hexdigest()[:2], 16) / 255
            time.sleep(min(2**attempt, 30) + stagger)
        except (OSError, urllib.error.URLError, json.JSONDecodeError):
            if attempt + 1 == attempts:
                raise
            stagger = int(hashlib.sha256(request.full_url.encode()).hexdigest()[:2], 16) / 255
            time.sleep(min(2**attempt, 30) + stagger)
    raise AssertionError("unreachable")


def fetch_block(height: int) -> dict[str, object] | None:
    cached = DOWNLOAD_CACHE / "blocks" / f"{height}.json"
    if cached.exists():
        summary = json.loads(cached.read_text(encoding="utf-8"))
        summary["sourceSha256"] = digest(
            {key: value for key, value in summary.items() if key != "sourceSha256"}
        )
        return summary
    rpc_url = RPC_URLS[height % len(RPC_URLS)]
    payload = canonical(
        {
            "jsonrpc": "2.0",
            "id": height,
            "method": "block",
            "params": {"block_id": height},
        }
    )
    request = urllib.request.Request(
        rpc_url,
        data=payload,
        headers={"content-type": "application/json", "user-agent": "NEAR-Lean-M12"},
    )
    response = request_json(request, missing_statuses={422})
    if response is None:
        return None
    if (
        isinstance(response, dict)
        and (
            response.get("error", {}).get("cause", {}).get("name") == "UNKNOWN_BLOCK"
            or "Cause: Unknown" in response.get("error", {}).get("data", "")
        )
    ):
        return None
    if not isinstance(response, dict) or not isinstance(response.get("result"), dict):
        raise RuntimeError(f"block RPC failed at {height}: {response}")
    block = response["result"]
    header = block["header"]
    if header["height"] != height:
        raise RuntimeError(f"block RPC returned height {header['height']} for {height}")
    summary = {
        "height": height,
        "hash": header["hash"],
        "prevHash": header["prev_hash"],
        "prevHeight": header["prev_height"],
        "protocolVersion": header["latest_protocol_version"],
        "prevStateRoot": header["prev_state_root"],
        "outcomeRoot": header["outcome_root"],
        "chunksIncluded": header["chunks_included"],
        "chunkMask": header["chunk_mask"],
    }
    summary["sourceSha256"] = digest(summary)
    cached.parent.mkdir(parents=True, exist_ok=True)
    cached.write_text(json.dumps(summary), encoding="utf-8")
    return summary


def fetch_stream(height: int) -> dict[str, object] | None:
    cached = DOWNLOAD_CACHE / "streams" / f"{height}.json.gz"
    if cached.exists():
        return json.loads(gzip.decompress(cached.read_bytes()))
    request = urllib.request.Request(
        STREAM_FETCH_URL.format(height=height), headers={"user-agent": "NEAR-Lean-M12"}
    )
    response = request_json(request, missing_statuses={404})
    if response is None or not isinstance(response, dict) or response.get("block") is None:
        return None
    if response.get("block", {}).get("header", {}).get("height") != height:
        raise RuntimeError(f"streamer response is invalid at {height}")
    cached.parent.mkdir(parents=True, exist_ok=True)
    cached.write_bytes(gzip.compress(canonical(response), compresslevel=6, mtime=0))
    return response


def parallel_fetch(function, values: range, workers: int) -> list[object]:
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        results = []
        for index, result in enumerate(executor.map(function, values), 1):
            results.append(result)
            if index % 500 == 0 or index == len(values):
                print(f"fetched {index}/{len(values)}", flush=True)
        return results


def discriminants(value: object, prefix: str = "") -> list[str]:
    if not isinstance(value, dict) or not value:
        return []
    if isinstance(value.get("kind"), dict):
        return discriminants(value["kind"], prefix)
    keys = [key for key in value if key not in {"index", "error_message"}]
    if not keys:
        return []
    key = keys[0]
    path = f"{prefix}.{key}" if prefix else key
    child = value[key]
    nested = discriminants(child, path)
    return nested or [path]


def action_kinds(actions: object) -> list[str]:
    if not isinstance(actions, list):
        return []
    result: list[str] = []
    for action in actions:
        if isinstance(action, str):
            result.append(action)
            continue
        if not isinstance(action, dict) or not action:
            continue
        kind = next(iter(action))
        result.append(kind)
        if kind == "Delegate":
            nested = action[kind].get("delegate_action", {}).get("actions", [])
            result.extend(f"Delegate.{item}" for item in action_kinds(nested))
    return result


def summarize_shard(
    height: int, block_hash: str, shard: dict[str, object]
) -> tuple[dict[str, object], dict[str, object]]:
    chunk = shard["chunk"]
    header = chunk["header"]
    transactions = chunk.get("transactions", [])
    receipts = (
        chunk.get("receipts", [])
        + chunk.get("local_receipts", [])
        + chunk.get("instant_receipts", [])
    )
    outcomes = shard.get("receipt_execution_outcomes", [])
    state_changes = shard.get("state_changes", [])
    actions = Counter()
    errors = Counter()
    state_kinds = Counter()
    for transaction in transactions:
        actions.update(action_kinds(transaction.get("transaction", {}).get("actions", [])))
        status = (
            transaction.get("outcome", {})
            .get("execution_outcome", {})
            .get("outcome", {})
            .get("status", {})
        )
        if isinstance(status, dict) and "Failure" in status:
            errors.update(discriminants(status["Failure"]))
    for receipt in receipts:
        payload = receipt.get("receipt", {})
        if isinstance(payload, dict) and "Action" in payload:
            actions.update(action_kinds(payload["Action"].get("actions", [])))
    for item in outcomes:
        status = item.get("execution_outcome", {}).get("outcome", {}).get("status", {})
        if isinstance(status, dict) and "Failure" in status:
            errors.update(discriminants(status["Failure"]))
    for change in state_changes:
        state_kinds.update([change.get("type", "unknown")])
    identifiers: dict[str, str] = {}
    if transactions:
        identifiers["transaction"] = transactions[0].get("transaction", {}).get("hash", "")
    if receipts:
        identifiers["receipt"] = receipts[0].get("receipt_id", "")
    for state_change in state_changes:
        change = state_change.get("change", {})
        if not identifiers.get("account") and change.get("account_id"):
            identifiers["account"] = change["account_id"]
        if not identifiers.get("trieKey") and change.get("key_base64"):
            identifiers["trieKey"] = change["key_base64"]
    summary = {
        "blockHeight": height,
        "blockHash": block_hash,
        "shardId": shard["shard_id"],
        "chunkHash": header["chunk_hash"],
        "heightCreated": header["height_created"],
        "heightIncluded": header["height_included"],
        "inputStateRoot": header["prev_state_root"],
        "outcomeRoot": header["outcome_root"],
        "transactionRoot": header["tx_root"],
        "gasUsed": header["gas_used"],
        "transactions": len(transactions),
        "receipts": len(receipts),
        "outcomes": len(outcomes),
        "stateChanges": len(state_changes),
        "transactionSha256": digest(transactions),
        "receiptSha256": digest(receipts),
        "outcomeSha256": digest(outcomes),
        "stateChangeSha256": digest(state_changes),
        "actionKinds": dict(sorted(actions.items())),
        "errorClasses": dict(sorted(errors.items())),
        "stateChangeKinds": dict(sorted(state_kinds.items())),
        "firstIdentifiers": identifiers,
    }
    sample = {
        "header": summary,
        "transactions": transactions[:2],
        "receipts": receipts[:2],
        "outcomes": outcomes[:2],
        "stateChanges": state_changes[:2],
    }
    return summary, sample


def build_corpus(workers: int) -> tuple[dict[str, object], dict[str, object]]:
    candidates = parallel_fetch(
        fetch_block, range(START_HEIGHT, SCAN_END_HEIGHT + 1), workers
    )
    blocks = [block for block in candidates if block is not None][:10_000]
    if len(blocks) != 10_000:
        raise RuntimeError(f"height scan contains only {len(blocks)} produced blocks")
    for index, block in enumerate(blocks):
        if block["protocolVersion"] != PROTOCOL_VERSION:
            raise RuntimeError(f"block interval leaves protocol 86 at {block['height']}")
        if index and (
            block["prevHeight"] != blocks[index - 1]["height"]
            or block["prevHash"] != blocks[index - 1]["hash"]
        ):
            raise RuntimeError(f"block hash chain differs at {block['height']}")

    stream_candidates = parallel_fetch(
        fetch_stream, range(START_HEIGHT, STREAM_SCAN_END_HEIGHT + 1), workers
    )
    stream_candidates += parallel_fetch(
        fetch_stream, range(STREAM_SCAN_END_HEIGHT + 1, SCAN_END_HEIGHT + 1, 9), workers
    )
    stream_candidates += [fetch_stream(height) for height in SUPPLEMENTAL_HEIGHTS]
    streams = [stream for stream in stream_candidates if stream is not None]
    streams.sort(key=lambda stream: stream["block"]["header"]["height"])
    selected: list[dict[str, object]] = []
    pending: dict[int, dict[str, object]] = {}
    samples: list[dict[str, object]] = []
    covered_actions: set[str] = set()
    covered_errors: set[str] = set()
    covered_changes: set[str] = set()
    for stream in streams:
        block = stream["block"]
        height = block["header"]["height"]
        block_hash = block["header"]["hash"]
        root_replay = START_HEIGHT <= height <= STREAM_SCAN_END_HEIGHT
        for shard in sorted(stream["shards"], key=lambda value: value["shard_id"]):
            if shard.get("chunk") is None:
                continue
            header = shard["chunk"]["header"]
            if header["height_included"] != height:
                continue
            summary, sample = summarize_shard(height, block_hash, shard)
            shard_id = summary["shardId"]
            if root_replay and shard_id in pending:
                previous = pending[shard_id]
                previous["outputStateRoot"] = summary["inputStateRoot"]
                if len(selected) < 10_000:
                    selected.append(previous)
            if root_replay:
                pending[shard_id] = summary
            action_set = set(summary["actionKinds"])
            error_set = set(summary["errorClasses"])
            change_set = set(summary["stateChangeKinds"])
            if (
                action_set - covered_actions
                or error_set - covered_errors
                or change_set - covered_changes
                or not samples
            ):
                samples.append(sample)
                covered_actions |= action_set
                covered_errors |= error_set
                covered_changes |= change_set
    if len(selected) != 10_000:
        raise RuntimeError(f"stream corpus contains only {len(selected)} finalized chunks")

    block_digest = hashlib.sha256(b"".join(canonical(block) for block in blocks)).hexdigest()
    chunk_digest = hashlib.sha256(b"".join(canonical(chunk) for chunk in selected)).hexdigest()
    corpus = {
        "schemaVersion": 1,
        "network": "mainnet",
        "protocolVersion": PROTOCOL_VERSION,
        "nearcoreCommit": NEARCORE_COMMIT,
        "sources": {
            "blockRpc": RPC_URLS,
            "streamer": STREAM_URL,
        },
        "interval": {
            "startHeight": START_HEIGHT,
            "endHeight": blocks[-1]["height"],
            "blocks": len(blocks),
            "sha256": block_digest,
        },
        "stratifiedChunks": {
            "count": len(selected),
            "sha256": chunk_digest,
            "supplementalHeights": SUPPLEMENTAL_HEIGHTS,
        },
        "blocks": blocks,
        "chunks": selected,
    }
    sample_file = {
        "schemaVersion": 1,
        "network": "mainnet",
        "protocolVersion": PROTOCOL_VERSION,
        "preStateKind": "committed-root-and-state-changes",
        "blocks": blocks[:2],
        "samples": samples,
    }
    return corpus, sample_file


def encode_cache(corpus: dict[str, object]) -> bytes:
    return gzip.compress(canonical(corpus) + b"\n", compresslevel=9, mtime=0)


def local_errors() -> list[str]:
    errors: list[str] = []
    try:
        corpus = json.loads(gzip.decompress(CACHE.read_bytes()))
        sample = json.loads(SAMPLE.read_text(encoding="utf-8"))
    except (OSError, EOFError, json.JSONDecodeError) as error:
        return [f"historical replay cache is unreadable: {error}"]
    interval = corpus.get("interval", {})
    chunks = corpus.get("chunks", [])
    blocks = corpus.get("blocks", [])
    if corpus.get("schemaVersion") != 1 or corpus.get("protocolVersion") != PROTOCOL_VERSION:
        errors.append("historical replay schema or protocol version differs")
    if interval.get("startHeight") != START_HEIGHT:
        errors.append("historical replay interval differs")
    if len(blocks) != 10_000 or interval.get("blocks") != 10_000:
        errors.append("historical replay needs 10,000 contiguous blocks")
    if len(chunks) != 10_000 or corpus.get("stratifiedChunks", {}).get("count") != 10_000:
        errors.append("historical replay needs 10,000 stratified chunks")
    if blocks and any(block.get("protocolVersion") != PROTOCOL_VERSION for block in blocks):
        errors.append("historical replay crosses the pinned protocol era")
    if blocks and interval.get("endHeight") != blocks[-1].get("height"):
        errors.append("historical replay end height differs")
    if any(
        blocks[index].get("prevHash") != blocks[index - 1].get("hash")
        or blocks[index].get("prevHeight") != blocks[index - 1].get("height")
        for index in range(1, len(blocks))
    ):
        errors.append("historical block hash chain is discontinuous")
    actual_block_digest = hashlib.sha256(
        b"".join(canonical(block) for block in blocks)
    ).hexdigest()
    actual_chunk_digest = hashlib.sha256(
        b"".join(canonical(chunk) for chunk in chunks)
    ).hexdigest()
    if interval.get("sha256") != actual_block_digest:
        errors.append("historical block digest differs")
    if corpus.get("stratifiedChunks", {}).get("sha256") != actual_chunk_digest:
        errors.append("historical chunk digest differs")
    if any(not chunk.get("outputStateRoot") for chunk in chunks):
        errors.append("historical chunk is missing its next committed state root")
    required_actions = {"CreateAccount", "DeployContract", "FunctionCall", "Transfer"}
    actions = {kind for chunk in chunks for kind in chunk.get("actionKinds", {})}
    actions |= {
        kind
        for item in sample.get("samples", [])
        for kind in item.get("header", {}).get("actionKinds", {})
    }
    if not required_actions <= actions:
        errors.append(f"historical action coverage is incomplete: {sorted(required_actions - actions)}")
    failures = sum(sum(chunk.get("errorClasses", {}).values()) for chunk in chunks)
    if failures == 0:
        errors.append("historical corpus has no failed outcomes")
    if sample.get("schemaVersion") != 1 or not sample.get("samples"):
        errors.append("historical importer sample is empty")
    return errors


def main() -> None:
    global DOWNLOAD_CACHE
    parser = argparse.ArgumentParser()
    parser.add_argument("--fetch", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--workers", type=int, default=32)
    parser.add_argument("--download-cache", type=pathlib.Path)
    arguments = parser.parse_args()
    if arguments.download_cache:
        DOWNLOAD_CACHE = arguments.download_cache
    if arguments.fetch:
        corpus, sample = build_corpus(arguments.workers)
        cache_bytes = encode_cache(corpus)
        sample_text = json.dumps(sample, indent=2, ensure_ascii=False) + "\n"
        if arguments.check:
            if CACHE.read_bytes() != cache_bytes or SAMPLE.read_text(encoding="utf-8") != sample_text:
                raise SystemExit("historical replay corpus is not reproducible")
        else:
            CACHE.parent.mkdir(parents=True, exist_ok=True)
            CACHE.write_bytes(cache_bytes)
            SAMPLE.write_text(sample_text, encoding="utf-8")
    errors = local_errors()
    if errors:
        raise SystemExit("\n".join(errors))


if __name__ == "__main__":
    main()
