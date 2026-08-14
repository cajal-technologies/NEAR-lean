#!/usr/bin/env python3
"""Validate current mainnet protocol configuration and receipt routing."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import urllib.request
from collections import Counter

from m12_fetch import NEARCORE_COMMIT, PROTOCOL_VERSION, STREAM_URL, canonical, request_json
from m12_latest import DEFAULT_COUNT, MAX_COUNT, latest_streams


ROOT = pathlib.Path(__file__).resolve().parents[1]
REPORT = ROOT / "replay/latest-sharding-report.json"
RPC_URL = "https://rpc.mainnet.near.org"
EXPECTED_BOUNDARIES = [
    "650",
    "aurora",
    "aurora-0",
    "earn.kaiching",
    "game.hot.tg",
    "game.hot.tg-0",
    "kkuuue2akv_1630967379.near",
    "tge-lockup.sweat",
    "wallet.ka",
]
EXPECTED_SHARD_IDS = [10, 11, 1, 8, 9, 6, 7, 4, 12, 13]


def rpc(method: str, params: object) -> dict[str, object]:
    request = urllib.request.Request(
        RPC_URL,
        data=canonical({"jsonrpc": "2.0", "id": "near-lean-m13", "method": method, "params": params}),
        headers={"content-type": "application/json", "user-agent": "NEAR-Lean-M13"},
    )
    response = request_json(request)
    if not isinstance(response, dict) or not isinstance(response.get("result"), dict):
        raise RuntimeError(f"{method} RPC failed: {response}")
    return response["result"]


def shard_for_account(
    account_id: str, boundaries: list[str], shard_ids: list[int]
) -> int:
    if len(boundaries) + 1 != len(shard_ids):
        raise ValueError("shard layout boundary and shard counts differ")
    for index, boundary in enumerate(boundaries):
        if account_id < boundary:
            return shard_ids[index]
    return shard_ids[-1]


def included_receipts(shard: dict[str, object]) -> list[dict[str, object]]:
    chunk = shard.get("chunk")
    if not isinstance(chunk, dict):
        return []
    receipts: list[dict[str, object]] = []
    for field in ("receipts", "local_receipts", "instant_receipts"):
        values = chunk.get(field, [])
        if isinstance(values, list):
            receipts.extend(value for value in values if isinstance(value, dict))
    return receipts


def report_from_inputs(
    streams: list[dict[str, object]],
    requested: int,
    protocol_config: dict[str, object],
    validator_info: dict[str, object],
) -> dict[str, object]:
    if len(streams) != requested:
        raise ValueError(f"latest sharding validation expected {requested} blocks")
    streams.sort(key=lambda stream: stream["block"]["header"]["height"])
    layout_wrapper = protocol_config.get("shard_layout")
    if not isinstance(layout_wrapper, dict) or not isinstance(layout_wrapper.get("V3"), dict):
        raise ValueError("latest protocol configuration is not shard layout V3")
    layout = layout_wrapper["V3"]
    boundaries = layout.get("boundary_accounts")
    shard_ids = layout.get("shard_ids")
    if not isinstance(boundaries, list) or not all(isinstance(value, str) for value in boundaries):
        raise ValueError("latest shard boundary accounts are invalid")
    if not isinstance(shard_ids, list) or not all(isinstance(value, int) for value in shard_ids):
        raise ValueError("latest shard ids are invalid")
    routed = 0
    cross_shard = 0
    mismatches = 0
    unroutable = 0
    system_receipts = 0
    destinations: Counter[str] = Counter()
    first_difference: dict[str, object] | None = None
    epoch_ids: set[str] = set()
    next_epoch_ids: set[str] = set()
    for stream_index, stream in enumerate(streams):
        header = stream["block"]["header"]
        if header.get("latest_protocol_version") != PROTOCOL_VERSION:
            raise ValueError(f"latest sharding window left protocol {PROTOCOL_VERSION}")
        if stream_index:
            previous = streams[stream_index - 1]["block"]["header"]
            if header.get("prev_height") != previous.get("height") or header.get(
                "prev_hash"
            ) != previous.get("hash"):
                raise ValueError(f"latest sharding block chain differs at {header['height']}")
        observed_shards = sorted(
            shard.get("shard_id")
            for shard in stream.get("shards", [])
            if isinstance(shard, dict) and isinstance(shard.get("shard_id"), int)
        )
        if observed_shards != sorted(shard_ids):
            raise ValueError(f"latest shard set differs at {header['height']}")
        if isinstance(header.get("epoch_id"), str):
            epoch_ids.add(header["epoch_id"])
        if isinstance(header.get("next_epoch_id"), str):
            next_epoch_ids.add(header["next_epoch_id"])
        for shard in stream.get("shards", []):
            if not isinstance(shard, dict) or not isinstance(shard.get("chunk"), dict):
                continue
            if shard["chunk"].get("header", {}).get("height_included") != header["height"]:
                continue
            destination = shard.get("shard_id")
            if not isinstance(destination, int):
                continue
            for receipt in included_receipts(shard):
                predecessor = receipt.get("predecessor_id")
                receiver = receipt.get("receiver_id")
                if not isinstance(predecessor, str) or not isinstance(receiver, str):
                    unroutable += 1
                    continue
                target = shard_for_account(receiver, boundaries, shard_ids)
                routed += 1
                destinations[str(target)] += 1
                if predecessor == "system":
                    system_receipts += 1
                elif shard_for_account(predecessor, boundaries, shard_ids) != destination:
                    mismatches += 1
                    if first_difference is None:
                        first_difference = {
                            "blockHeight": header["height"],
                            "receiptId": receipt.get("receipt_id"),
                            "predecessorId": predecessor,
                            "observedSourceShard": destination,
                            "routedSourceShard": shard_for_account(
                                predecessor, boundaries, shard_ids
                            ),
                        }
                if destination != target:
                    cross_shard += 1
    first_header = streams[0]["block"]["header"]
    last_header = streams[-1]["block"]["header"]
    config_projection = {
        "protocolVersion": protocol_config.get("protocol_version"),
        "epochLength": protocol_config.get("epoch_length"),
        "boundaryAccounts": boundaries,
        "shardIds": shard_ids,
    }
    return {
        "schemaVersion": 1,
        "network": "mainnet",
        "nearcoreCommit": NEARCORE_COMMIT,
        "protocolVersion": PROTOCOL_VERSION,
        "scope": "bounded-latest-finalized-window",
        "replayMode": "current-config-and-receipt-routing-import",
        "sources": {"protocolRpc": RPC_URL, "streamer": STREAM_URL},
        "window": {
            "requestedProducedBlocks": requested,
            "producedBlocks": len(streams),
            "oldestHeight": first_header["height"],
            "latestHeight": last_header["height"],
            "latestBlockHash": last_header["hash"],
        },
        "protocolConfig": {
            "protocolVersion": protocol_config.get("protocol_version"),
            "shardLayoutVersion": 3,
            "boundaryAccounts": boundaries,
            "shardIds": shard_ids,
            "epochLength": protocol_config.get("epoch_length"),
            "projectionSha256": hashlib.sha256(canonical(config_projection)).hexdigest(),
        },
        "epochInputs": {
            "epochIds": sorted(epoch_ids),
            "nextEpochIds": sorted(next_epoch_ids),
            "epochHeight": validator_info.get("epoch_height"),
            "epochStartHeight": validator_info.get("epoch_start_height"),
            "currentValidators": len(validator_info.get("current_validators", [])),
            "currentProposals": len(validator_info.get("current_proposals", [])),
            "validatorProjectionSha256": hashlib.sha256(
                canonical(validator_info.get("current_validators", []))
            ).hexdigest(),
        },
        "receiptRouting": {
            "routedReceipts": routed,
            "crossShardReceipts": cross_shard,
            "routeMismatches": mismatches,
            "unroutableReceipts": unroutable,
            "systemReceipts": system_receipts,
            "destinationShardCounts": dict(sorted(destinations.items(), key=lambda item: int(item[0]))),
        },
        "independentRuntimeExecution": False,
        "firstDifference": first_difference,
    }


def live_report(count: int, workers: int) -> dict[str, object]:
    if count < 2 or count > MAX_COUNT:
        raise ValueError(f"latest sharding count must be between 2 and {MAX_COUNT}")
    streams = latest_streams(count, workers)
    head_hash = streams[-1]["block"]["header"]["hash"]
    protocol_config = rpc("EXPERIMENTAL_protocol_config", {"block_id": head_hash})
    validator_info = rpc("validators", [None])
    return report_from_inputs(streams, count, protocol_config, validator_info)


def report_errors(report: object, expected_count: int = DEFAULT_COUNT) -> list[str]:
    if not isinstance(report, dict):
        return ["latest sharding report must be an object"]
    errors: list[str] = []
    if report.get("schemaVersion") != 1 or report.get("network") != "mainnet":
        errors.append("latest sharding schema or network differs")
    if report.get("protocolVersion") != PROTOCOL_VERSION:
        errors.append("latest sharding protocol version differs")
    if report.get("scope") != "bounded-latest-finalized-window":
        errors.append("latest sharding scope must remain bounded")
    if report.get("replayMode") != "current-config-and-receipt-routing-import":
        errors.append("latest sharding replay mode differs")
    window = report.get("window", {})
    if window.get("requestedProducedBlocks") != expected_count or window.get("producedBlocks") != expected_count:
        errors.append("latest sharding block count differs")
    config = report.get("protocolConfig", {})
    if config.get("protocolVersion") != PROTOCOL_VERSION:
        errors.append("latest sharding RPC protocol version differs")
    if config.get("shardLayoutVersion") != 3:
        errors.append("latest sharding layout version differs")
    if config.get("boundaryAccounts") != EXPECTED_BOUNDARIES:
        errors.append("latest sharding boundary accounts differ")
    if config.get("shardIds") != EXPECTED_SHARD_IDS:
        errors.append("latest sharding shard ids differ")
    if config.get("epochLength") != 43200:
        errors.append("latest sharding epoch length differs")
    projection = config.get("projectionSha256")
    if not isinstance(projection, str) or len(projection) != 64:
        errors.append("latest sharding protocol projection digest is invalid")
    epoch = report.get("epochInputs", {})
    if not epoch.get("epochIds") or not epoch.get("nextEpochIds"):
        errors.append("latest sharding epoch ids are missing")
    if not isinstance(epoch.get("currentValidators"), int) or epoch["currentValidators"] <= 0:
        errors.append("latest sharding validator inputs are missing")
    validator_projection = epoch.get("validatorProjectionSha256")
    if not isinstance(validator_projection, str) or len(validator_projection) != 64:
        errors.append("latest sharding validator projection digest is invalid")
    routing = report.get("receiptRouting", {})
    if not isinstance(routing.get("routedReceipts"), int) or routing["routedReceipts"] <= 0:
        errors.append("latest sharding report contains no routed receipts")
    if not isinstance(routing.get("crossShardReceipts"), int) or routing["crossShardReceipts"] <= 0:
        errors.append("latest sharding report contains no cross-shard traffic")
    if routing.get("routeMismatches") != 0 or routing.get("unroutableReceipts") != 0:
        errors.append("latest sharding receipt routing differs from the observed chunks")
    if report.get("independentRuntimeExecution") is not False:
        errors.append("latest sharding report must not overclaim independent execution")
    if report.get("firstDifference") is not None:
        errors.append("latest sharding report contains a first difference")
    return errors


def self_test() -> None:
    assert shard_for_account("000", EXPECTED_BOUNDARIES, EXPECTED_SHARD_IDS) == 10
    assert shard_for_account("650", EXPECTED_BOUNDARIES, EXPECTED_SHARD_IDS) == 11
    assert shard_for_account("aurora", EXPECTED_BOUNDARIES, EXPECTED_SHARD_IDS) == 1
    assert shard_for_account("token.sweat", EXPECTED_BOUNDARIES, EXPECTED_SHARD_IDS) == 12
    assert shard_for_account("z", EXPECTED_BOUNDARIES, EXPECTED_SHARD_IDS) == 13
    try:
        shard_for_account("invalid", ["boundary"], [1])
    except ValueError:
        pass
    else:
        raise AssertionError("invalid shard layout was accepted")
    print("current protocol and shard-routing tests passed")


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
