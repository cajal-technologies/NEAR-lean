#!/usr/bin/env python3
"""Measure and summarize the bounded latest-window stabilization campaign."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import pathlib
import re
import resource
import sys
import time

from m12_fetch import NEARCORE_COMMIT, PROTOCOL_VERSION
from m12_latest import DEFAULT_COUNT, MAX_COUNT, latest_streams, report_errors as commitment_errors
from m12_latest import report_from_streams
from m13_latest import report_errors as sharding_errors
from m13_latest import report_from_inputs as sharding_report_from_inputs
from m13_latest import rpc


ROOT = pathlib.Path(__file__).resolve().parents[1]
REPORT = ROOT / "replay/latest-stabilization-report.json"
BASE58 = re.compile(r"[1-9A-HJ-NP-Za-km-z]{32,64}")
SHA256 = re.compile(r"[0-9a-f]{64}")
TRUSTED_ASSUMPTION_SUMMARY = [
    "NEAR Data and mainnet RPC responses faithfully expose finalized consensus data",
    "the Python projection and comparison scripts are trusted adapters",
    "Python wall-clock, getrusage, operating-system, and hardware measurements are accurate",
    "validation/report.json faithfully records the repository semantic mutation campaign",
    "missing pre-state witnesses prevent independent runtime execution and root recomputation",
]
SCOPE_EXCLUSIONS = [
    "genesis-to-checkpoint replay",
    "historical protocol transitions and runtime migrations",
    "upgrade-boundary and resharding replay",
    "independent current-runtime execution from complete state witnesses",
    "reproducibility from archived latest-window inputs",
    "stratified historical sampled-block replay",
]


def peak_rss_mib() -> float:
    raw = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    divisor = 1024 * 1024 if sys.platform == "darwin" else 1024
    return raw / divisor


def aggregate_report(
    commitment: dict[str, object],
    sharding: dict[str, object],
    elapsed_seconds: float,
    peak_memory_mib: float,
    mutation_score: float,
    mutation_report_sha256: str,
) -> dict[str, object]:
    if commitment["latestHeight"] != sharding["window"]["latestHeight"]:
        raise ValueError("latest stabilization inputs end at different heights")
    if commitment["latestBlockHash"] != sharding["window"]["latestBlockHash"]:
        raise ValueError("latest stabilization inputs end at different blocks")
    blocks = commitment["producedBlocks"]
    chunks = commitment["includedChunks"]
    routing = sharding["receiptRouting"]
    validated_sources = routing["routedReceipts"] - routing["systemReceipts"]
    if validated_sources <= 0:
        raise ValueError("latest stabilization has no non-system receipt sources")
    routing_pass_rate = 100 * (validated_sources - routing["routeMismatches"]) / validated_sources
    first_difference = commitment.get("firstDifference") or sharding.get("firstDifference")
    observed_mismatches = routing["routeMismatches"] + routing["unroutableReceipts"]
    if first_difference is not None:
        observed_mismatches += 1
    return {
        "schemaVersion": 1,
        "network": "mainnet",
        "referenceNearcoreCommit": NEARCORE_COMMIT,
        "protocolVersion": PROTOCOL_VERSION,
        "scope": "bounded-latest-finalized-window",
        "replayMode": "latest-window-stabilization",
        "sources": {
            "finalizedHead": "https://mainnet.neardata.xyz/v0/last_block/final",
            "commitmentStreamer": commitment["source"],
            "protocolRpc": sharding["sources"]["protocolRpc"],
            "shardingStreamer": sharding["sources"]["streamer"],
        },
        "window": {
            "producedBlocks": blocks,
            "oldestHeight": commitment["oldestHeight"],
            "latestHeight": commitment["latestHeight"],
            "latestBlockHash": commitment["latestBlockHash"],
            "largestContiguousLatestWindow": blocks,
            "blockProjectionSha256": commitment["blockProjectionSha256"],
            "chunkProjectionSha256": commitment["chunkProjectionSha256"],
            "latestTimestampNanosec": commitment["latestTimestampNanosec"],
        },
        "compatibility": {
            "observedProtocolEras": 1,
            "exactlyReplayedProtocolEras": 0,
            "observedUpgradeBoundaries": 0,
            "exactlyReplayedUpgradeBoundaries": 0,
            "includedChunks": chunks,
            "importedOutcomes": commitment["importedOutcomes"],
            "routedReceipts": routing["routedReceipts"],
            "validatedSourceReceipts": validated_sources,
            "systemReceipts": routing["systemReceipts"],
            "crossShardReceipts": routing["crossShardReceipts"],
            "routeMismatches": routing["routeMismatches"],
            "unroutableReceipts": routing["unroutableReceipts"],
            "observedProjectionMismatches": observed_mismatches,
            "independentRuntimeExecution": False,
        },
        "performance": {
            "elapsedSeconds": round(elapsed_seconds, 6),
            "blocksPerSecond": round(blocks / elapsed_seconds, 3),
            "chunksPerSecond": round(chunks / elapsed_seconds, 3),
            "peakRssMiB": round(peak_memory_mib, 3),
        },
        "quality": {
            "repositoryValidationMutationScore": mutation_score,
            "repositoryValidationReportSha256": mutation_report_sha256,
            "latestWindowMutationScore": None,
            "routingPassRatePercent": round(routing_pass_rate, 3),
        },
        "trustedAssumptionSummary": TRUSTED_ASSUMPTION_SUMMARY,
        "intentionalScopeExclusions": SCOPE_EXCLUSIONS,
        "firstDifference": first_difference,
    }


def live_report(count: int, workers: int) -> dict[str, object]:
    if count < 2 or count > MAX_COUNT:
        raise ValueError(f"latest stabilization count must be between 2 and {MAX_COUNT}")
    started = time.perf_counter()
    streams = latest_streams(count, workers)
    commitment = report_from_streams(streams.copy(), count)
    head_hash = streams[-1]["block"]["header"]["hash"]
    protocol_config = rpc("EXPERIMENTAL_protocol_config", {"block_id": head_hash})
    validator_info = rpc("validators", [None])
    sharding = sharding_report_from_inputs(
        streams.copy(), count, protocol_config, validator_info
    )
    failures = commitment_errors(commitment) + sharding_errors(sharding, count)
    if failures:
        raise ValueError("; ".join(failures))
    elapsed = time.perf_counter() - started
    validation_path = ROOT / "validation/report.json"
    validation_bytes = validation_path.read_bytes()
    validation = json.loads(validation_bytes)
    return aggregate_report(
        commitment,
        sharding,
        elapsed,
        peak_rss_mib(),
        validation["mutationScore"],
        hashlib.sha256(validation_bytes).hexdigest(),
    )


def report_errors(report: object, expected_count: int = DEFAULT_COUNT) -> list[str]:
    if not isinstance(report, dict):
        return ["latest stabilization report must be an object"]
    errors: list[str] = []
    if report.get("schemaVersion") != 1 or report.get("network") != "mainnet":
        errors.append("latest stabilization schema or network differs")
    if report.get("protocolVersion") != PROTOCOL_VERSION:
        errors.append("latest stabilization protocol version differs")
    if report.get("referenceNearcoreCommit") != NEARCORE_COMMIT:
        errors.append("latest stabilization reference nearcore commit differs")
    if report.get("scope") != "bounded-latest-finalized-window":
        errors.append("latest stabilization scope must remain bounded")
    if report.get("replayMode") != "latest-window-stabilization":
        errors.append("latest stabilization replay mode differs")
    sources = report.get("sources")
    if sources != {
        "finalizedHead": "https://mainnet.neardata.xyz/v0/last_block/final",
        "commitmentStreamer": "https://mainnet.neardata.xyz/v0/block/{height}",
        "protocolRpc": "https://rpc.mainnet.near.org",
        "shardingStreamer": "https://mainnet.neardata.xyz/v0/block/{height}",
    }:
        errors.append("latest stabilization source provenance differs")
    window = report.get("window")
    if not isinstance(window, dict):
        errors.append("latest stabilization window must be an object")
        window = {}
    if window.get("producedBlocks") != expected_count:
        errors.append("latest stabilization block count differs")
    if window.get("largestContiguousLatestWindow") != expected_count:
        errors.append("latest stabilization contiguous-window count differs")
    oldest = window.get("oldestHeight")
    latest = window.get("latestHeight")
    if (
        not isinstance(oldest, int)
        or isinstance(oldest, bool)
        or not isinstance(latest, int)
        or isinstance(latest, bool)
        or latest < oldest + expected_count - 1
    ):
        errors.append("latest stabilization height window is invalid")
    if not isinstance(window.get("latestBlockHash"), str) or not BASE58.fullmatch(
        window["latestBlockHash"]
    ):
        errors.append("latest stabilization block hash is invalid")
    for field in ("blockProjectionSha256", "chunkProjectionSha256"):
        if not isinstance(window.get(field), str) or not SHA256.fullmatch(window[field]):
            errors.append(f"latest stabilization {field} is invalid")
    timestamp = window.get("latestTimestampNanosec")
    if not isinstance(timestamp, str) or not timestamp.isdigit() or int(timestamp) <= 0:
        errors.append("latest stabilization timestamp is invalid")
    compatibility = report.get("compatibility")
    if not isinstance(compatibility, dict):
        errors.append("latest stabilization compatibility must be an object")
        compatibility = {}
    if compatibility.get("observedProtocolEras") != 1:
        errors.append("latest stabilization must record one observed protocol era")
    if compatibility.get("exactlyReplayedProtocolEras") != 0:
        errors.append("latest stabilization must not claim an exactly replayed protocol era")
    if compatibility.get("observedUpgradeBoundaries") != 0:
        errors.append("latest stabilization latest window must not cross an upgrade boundary")
    if compatibility.get("exactlyReplayedUpgradeBoundaries") != 0:
        errors.append("latest stabilization must not claim exact upgrade replay")
    for field in (
        "includedChunks",
        "importedOutcomes",
        "routedReceipts",
        "validatedSourceReceipts",
        "crossShardReceipts",
    ):
        if (
            not isinstance(compatibility.get(field), int)
            or isinstance(compatibility[field], bool)
            or compatibility[field] <= 0
        ):
            errors.append(f"latest stabilization {field} is missing")
    if compatibility.get("routeMismatches") != 0:
        errors.append("latest stabilization contains a receipt-routing mismatch")
    if compatibility.get("unroutableReceipts") != 0:
        errors.append("latest stabilization contains unroutable receipts")
    if compatibility.get("observedProjectionMismatches") != 0:
        errors.append("latest stabilization contains an observed projection mismatch")
    system_receipts = compatibility.get("systemReceipts")
    routed_receipts = compatibility.get("routedReceipts")
    validated_sources = compatibility.get("validatedSourceReceipts")
    counts_valid = (
        isinstance(system_receipts, int)
        and not isinstance(system_receipts, bool)
        and system_receipts >= 0
        and isinstance(routed_receipts, int)
        and not isinstance(routed_receipts, bool)
        and isinstance(validated_sources, int)
        and not isinstance(validated_sources, bool)
    )
    if not counts_valid or validated_sources != routed_receipts - system_receipts:
        errors.append("latest stabilization source-validation counts differ")
    if compatibility.get("independentRuntimeExecution") is not False:
        errors.append("latest stabilization must not overclaim independent execution")
    performance = report.get("performance")
    if not isinstance(performance, dict):
        errors.append("latest stabilization performance must be an object")
        performance = {}
    for field in ("elapsedSeconds", "blocksPerSecond", "chunksPerSecond", "peakRssMiB"):
        value = performance.get(field)
        if (
            not isinstance(value, (int, float))
            or isinstance(value, bool)
            or not math.isfinite(value)
            or value <= 0
        ):
            errors.append(f"latest stabilization {field} is invalid")
    elapsed = performance.get("elapsedSeconds")
    blocks_per_second = performance.get("blocksPerSecond")
    chunks_per_second = performance.get("chunksPerSecond")
    chunks = compatibility.get("includedChunks")
    if all(
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and math.isfinite(value)
        and value > 0
        for value in (elapsed, blocks_per_second, chunks_per_second)
    ) and isinstance(chunks, int) and not isinstance(chunks, bool):
        if abs(blocks_per_second - round(expected_count / elapsed, 3)) > 0.001:
            errors.append("latest stabilization block throughput is inconsistent")
        if abs(chunks_per_second - round(chunks / elapsed, 3)) > 0.001:
            errors.append("latest stabilization chunk throughput is inconsistent")
    quality = report.get("quality")
    if not isinstance(quality, dict):
        errors.append("latest stabilization quality must be an object")
        quality = {}
    if quality.get("repositoryValidationMutationScore") != 100.0:
        errors.append("latest stabilization repository mutation score differs")
    mutation_digest = quality.get("repositoryValidationReportSha256")
    expected_mutation_digest = hashlib.sha256(
        (ROOT / "validation/report.json").read_bytes()
    ).hexdigest()
    if mutation_digest != expected_mutation_digest:
        errors.append("latest stabilization validation-report digest is invalid")
    if quality.get("latestWindowMutationScore") is not None:
        errors.append("latest stabilization must not claim a latest-window mutation score")
    if quality.get("routingPassRatePercent") != 100.0:
        errors.append("latest stabilization routing pass rate differs")
    if report.get("trustedAssumptionSummary") != TRUSTED_ASSUMPTION_SUMMARY:
        errors.append("latest stabilization trusted-assumption summary differs")
    if report.get("intentionalScopeExclusions") != SCOPE_EXCLUSIONS:
        errors.append("latest stabilization scope exclusions differ")
    if report.get("firstDifference") is not None:
        errors.append("latest stabilization report contains a first difference")
    return errors


def self_test() -> None:
    commitment = {
        "producedBlocks": 2,
        "oldestHeight": 10,
        "latestHeight": 11,
        "latestBlockHash": "1" * 44,
        "blockProjectionSha256": "a" * 64,
        "chunkProjectionSha256": "b" * 64,
        "latestTimestampNanosec": "1",
        "source": "https://mainnet.neardata.xyz/v0/block/{height}",
        "includedChunks": 20,
        "importedOutcomes": 5,
    }
    sharding = {
        "window": {"latestHeight": 11, "latestBlockHash": "1" * 44},
        "sources": {
            "protocolRpc": "https://rpc.mainnet.near.org",
            "streamer": "https://mainnet.neardata.xyz/v0/block/{height}",
        },
        "receiptRouting": {
            "routedReceipts": 4,
            "systemReceipts": 1,
            "crossShardReceipts": 2,
            "routeMismatches": 0,
            "unroutableReceipts": 0,
        },
    }
    mutation_digest = hashlib.sha256((ROOT / "validation/report.json").read_bytes()).hexdigest()
    report = aggregate_report(commitment, sharding, 1.0, 10.0, 100.0, mutation_digest)
    assert not report_errors(report, 2)
    corruptions = [
        ("referenceNearcoreCommit", "bad"),
        ("window.latestBlockHash", None),
        ("window.blockProjectionSha256", "bad"),
        ("compatibility.observedProjectionMismatches", 1),
        ("compatibility.includedChunks", True),
        ("performance.blocksPerSecond", 0.001),
        ("quality.repositoryValidationReportSha256", "d" * 64),
    ]
    for path, value in corruptions:
        corrupted = copy.deepcopy(report)
        target = corrupted
        parts = path.split(".")
        for part in parts[:-1]:
            target = target[part]
        target[parts[-1]] = value
        assert report_errors(corrupted, 2), f"corruption was accepted: {path}"
    malformed = copy.deepcopy(report)
    malformed["window"] = []
    assert report_errors(malformed, 2)
    print("latest stabilization aggregation and corruption tests passed")


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
        errors = report_errors(report, arguments.count)
        if errors:
            raise SystemExit("\n".join(errors))
        if arguments.output:
            output = arguments.output if arguments.output.is_absolute() else ROOT / arguments.output
            output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
