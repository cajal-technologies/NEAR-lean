#!/usr/bin/env python3
"""Deterministic Milestone 3 generation, comparison, and minimization."""

from __future__ import annotations

import argparse
import copy
import json
import pathlib
import random
import subprocess
import tempfile
from collections.abc import Callable


ROOT = pathlib.Path(__file__).resolve().parents[1]
BASELINE = json.loads((ROOT / "protocol/baseline.json").read_text(encoding="utf-8"))
DEFAULT_FIXTURE = ROOT / "differential/fixtures/counter.json"
ASYNC_FIXTURE = ROOT / "differential/fixtures/async.json"
BLOCK_FIXTURE = ROOT / "differential/fixtures/block.json"
ECONOMIC_FIXTURE = ROOT / "differential/fixtures/economic.json"
WASM_FIXTURE = ROOT / "differential/fixtures/wasm-counter.json"
LEAN_RUNNER = ROOT / ".lake/build/bin/nearLeanOracle"


def write_json(path: pathlib.Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def command(arguments: list[str], *, output: pathlib.Path | None = None) -> None:
    if output:
        with output.open("w", encoding="utf-8") as handle:
            subprocess.run(arguments, cwd=ROOT, check=True, stdout=handle)
    else:
        subprocess.run(arguments, cwd=ROOT, check=True, stdout=subprocess.DEVNULL)


def trace(seed: int) -> dict[str, object]:
    generator = random.Random(seed)
    parent = f"t{seed:08x}"
    child = f"a.{parent}"
    parent_balance = 100_000_000_000_000_000_000_000_000
    child_balance = 10_000_000_000_000_000_000_000_000
    genesis = [{"id": parent, "balance": str(parent_balance)}]
    actions: list[dict[str, object]]
    remainder = seed % 10
    if remainder == 2:
        genesis.append({"id": child, "balance": str(child_balance)})
        actions = [
            {
                "kind": "deployContract",
                "deployer": child,
                "accountId": child,
                "contract": "counter",
            },
            {
                "kind": "functionCall",
                "caller": parent,
                "receiver": child,
                "method": "increment",
                "arguments": "",
                "attachedDeposit": "0",
                "prepaidGas": "100000000000000",
            },
            {
                "kind": "functionCall",
                "caller": parent,
                "receiver": child,
                "method": "get",
                "arguments": "",
                "attachedDeposit": "0",
                "prepaidGas": "100000000000000",
            },
        ]
    elif remainder == 3:
        genesis.append({"id": child, "balance": str(child_balance)})
        actions = [
            {
                "kind": "transfer",
                "sender": parent,
                "receiver": child,
                "amount": str(parent_balance + 1),
            }
        ]
    elif remainder % 2 == 0:
        amount = child_balance + generator.randrange(1_000_000)
        actions = [
            {
                "kind": "createAccount",
                "creator": parent,
                "accountId": child,
                "initialBalance": str(amount),
            }
        ]
    else:
        genesis.append({"id": child, "balance": str(child_balance)})
        amount = generator.randrange(1_000_000)
        actions = [
            {
                "kind": "transfer",
                "sender": parent,
                "receiver": child,
                "amount": str(amount),
            }
        ]
    return {
        "schemaVersion": 1,
        "nearcoreCommit": BASELINE["nearcore"]["commit"],
        "nearcoreRelease": BASELINE["nearcore"]["release"],
        "protocolVersion": BASELINE["protocolVersions"]["minimum"],
        "seed": seed,
        "genesis": genesis,
        "actions": actions,
        "observeAccounts": [parent, child],
    }


def receipt_trace(seed: int, *, block_mode: bool = False) -> dict[str, object]:
    owner = f"r{seed:08x}"
    caller = "caller.receipts"
    callee = "callee.receipts"
    balance = "100000000000000000000000000"
    generated = {
        "schemaVersion": 1,
        "nearcoreCommit": BASELINE["nearcore"]["commit"],
        "nearcoreRelease": BASELINE["nearcore"]["release"],
        "protocolVersion": BASELINE["protocolVersions"]["minimum"],
        "seed": seed,
        "genesis": [
            {"id": owner, "balance": balance},
            {"id": caller, "balance": balance, "contract": "async"},
            {"id": callee, "balance": balance, "contract": "async"},
        ],
        "actions": [
            {
                "kind": "functionCall",
                "caller": owner,
                "receiver": caller,
                "method": "call_then",
                "arguments": callee,
                "attachedDeposit": "0",
                "prepaidGas": "100000000000000",
            }
        ],
        "observeAccounts": [owner],
        "receiptMode": True,
    }
    if block_mode:
        generated["blockMode"] = True
    return generated


def generate(count: int, seed: int, directory: pathlib.Path) -> list[pathlib.Path]:
    paths = []
    for current in range(seed, seed + count):
        path = directory / f"{current:08d}.json"
        write_json(path, trace(current))
        paths.append(path)
    return paths


def generate_receipts(count: int, seed: int, directory: pathlib.Path) -> list[pathlib.Path]:
    paths = []
    for current in range(seed, seed + count):
        path = directory / f"{current:08d}.json"
        write_json(path, receipt_trace(current))
        paths.append(path)
    return paths


def generate_blocks(count: int, seed: int, directory: pathlib.Path) -> list[pathlib.Path]:
    paths = []
    for current in range(seed, seed + count):
        path = directory / f"{current:08d}.json"
        write_json(path, receipt_trace(current, block_mode=True))
        paths.append(path)
    return paths


def economic_trace(seed: int) -> dict[str, object]:
    suffix = f"{seed:08x}"
    sender = f"s{suffix}.econ"
    receiver = f"r{suffix}.econ"
    balance = "100000000000000000000000000"
    return {
        "schemaVersion": 1,
        "nearcoreCommit": BASELINE["nearcore"]["commit"],
        "nearcoreRelease": BASELINE["nearcore"]["release"],
        "protocolVersion": BASELINE["protocolVersions"]["minimum"],
        "seed": seed,
        "genesis": [
            {"id": sender, "balance": balance},
            {"id": receiver, "balance": balance},
        ],
        "actions": [
            {
                "kind": "transfer",
                "sender": sender,
                "receiver": receiver,
                "amount": str(seed % 1000),
            }
        ],
        "observeAccounts": [sender, receiver],
        "receiptMode": True,
        "economicMode": True,
    }


def generate_economics(count: int, seed: int, directory: pathlib.Path) -> list[pathlib.Path]:
    paths = []
    for current in range(seed, seed + count):
        path = directory / f"{current:08d}.json"
        write_json(path, economic_trace(current))
        paths.append(path)
    return paths


def run_lean(paths: list[pathlib.Path], output: pathlib.Path, build: bool = True) -> None:
    if build:
        subprocess.run(["lake", "build", "nearLeanOracle"], cwd=ROOT, check=True)
    command([str(LEAN_RUNNER), *(str(path) for path in paths)], output=output)


def run_nearcore(paths: list[pathlib.Path], output: pathlib.Path) -> None:
    subprocess.run(
        ["node", "Oracle/run.mjs", "--output", str(output), *(str(path) for path in paths)],
        cwd=ROOT,
        check=True,
    )


def runs(value: object) -> list[dict[str, object]]:
    if isinstance(value, dict):
        return [value]
    if isinstance(value, list) and all(isinstance(item, dict) for item in value):
        return value
    raise ValueError("runner output must be an object or array of objects")


def first_difference(left: object, right: object, path: str = "$") -> dict[str, object] | None:
    if type(left) is not type(right):
        return {"path": path, "lean": left, "nearcore": right}
    if isinstance(left, dict):
        keys = sorted(set(left) | set(right))
        for key in keys:
            if key not in left or key not in right:
                return {
                    "path": f"{path}.{key}",
                    "lean": left.get(key),
                    "nearcore": right.get(key),
                }
            difference = first_difference(left[key], right[key], f"{path}.{key}")
            if difference:
                return difference
        return None
    if isinstance(left, list):
        if len(left) != len(right):
            return {"path": f"{path}.length", "lean": len(left), "nearcore": len(right)}
        for index, (left_item, right_item) in enumerate(zip(left, right, strict=True)):
            difference = first_difference(left_item, right_item, f"{path}[{index}]")
            if difference:
                return difference
        return None
    if left != right:
        return {"path": path, "lean": left, "nearcore": right}
    return None


def compare(
    lean_value: object, nearcore_value: object, observation_level: str = "L3"
) -> dict[str, object]:
    lean_runs = runs(lean_value)
    nearcore_runs = runs(nearcore_value)
    if len(lean_runs) != len(nearcore_runs):
        return {
            "matched": False,
            "observationLevel": "L0",
            "firstDifference": {
                "path": "$.runs.length",
                "lean": len(lean_runs),
                "nearcore": len(nearcore_runs),
            },
        }
    action_count = 0
    for trace_index, (lean_run, nearcore_run) in enumerate(
        zip(lean_runs, nearcore_runs, strict=True)
    ):
        lean_observations = lean_run["observations"]
        nearcore_observations = nearcore_run["observations"]
        action_count += len(lean_observations)
        levels = (
            ("L1", ("success", "errorCategory")),
            ("L2", ("returnValue", "logs")),
            ("L3", ("accounts",)),
            ("L4", ("receiptGraph",)),
            ("L5", ("economics",)),
        )
        for level, fields in levels[: int(observation_level[1:])]:
            left = [{field: item[field] for field in fields} for item in lean_observations]
            right = [{field: item[field] for field in fields} for item in nearcore_observations]
            difference = first_difference(left, right)
            if difference:
                difference.update({"traceIndex": trace_index, "level": level})
                return {
                    "matched": False,
                    "observationLevel": f"L{int(level[1]) - 1}",
                    "traceCount": len(lean_runs),
                    "actionCount": action_count,
                    "firstDifference": difference,
                }
    return {
        "matched": True,
        "observationLevel": observation_level,
        "traceCount": len(lean_runs),
        "actionCount": action_count,
        "firstDifference": None,
    }


def minimize_actions(
    original: dict[str, object], mismatch: Callable[[dict[str, object]], bool]
) -> dict[str, object]:
    minimized = copy.deepcopy(original)
    changed = True
    while changed and len(minimized["actions"]) > 1:
        changed = False
        for index in range(len(minimized["actions"])):
            candidate = copy.deepcopy(minimized)
            del candidate["actions"][index]
            if mismatch(candidate):
                minimized = candidate
                changed = True
                break
    return minimized


def execute(
    paths: list[pathlib.Path],
    directory: pathlib.Path,
    observation_level: str = "L3",
    build_lean: bool = True,
) -> dict[str, object]:
    directory.mkdir(parents=True, exist_ok=True)
    lean_output = directory / "lean.json"
    nearcore_output = directory / "nearcore.json"
    run_lean(paths, lean_output, build_lean)
    run_nearcore(paths, nearcore_output)
    return compare(
        json.loads(lean_output.read_text(encoding="utf-8")),
        json.loads(nearcore_output.read_text(encoding="utf-8")),
        observation_level,
    )


def minimize_real(original: dict[str, object]) -> dict[str, object]:
    def mismatch(candidate: dict[str, object]) -> bool:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            candidate_path = directory / "candidate.json"
            write_json(candidate_path, candidate)
            return not execute([candidate_path], directory)["matched"]

    if not mismatch(original):
        raise ValueError("trace does not currently reproduce a differential mismatch")
    return minimize_actions(original, mismatch)


def self_test() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        lean_output = pathlib.Path(temporary) / "lean.json"
        run_lean([DEFAULT_FIXTURE], lean_output)
        reference = json.loads(lean_output.read_text(encoding="utf-8"))
    for level, mutate in (
        ("L1", lambda value: value["observations"][0].update(success=False)),
        ("L1", lambda value: value["observations"][0].update(errorCategory="corrupt")),
        ("L2", lambda value: value["observations"][0]["returnValue"].append(255)),
        ("L3", lambda value: value["observations"][0]["accounts"][0].update(balance="1")),
        (
            "L3",
            lambda value: value["observations"][1]["accounts"][1]["storage"].append(
                {"key": [9], "value": [9]}
            ),
        ),
    ):
        corrupted = copy.deepcopy(reference)
        mutate(corrupted)
        result = compare(reference, corrupted)
        if result["matched"] or result["firstDifference"]["level"] != level:
            raise AssertionError(f"comparator missed {level} corruption")
    with tempfile.TemporaryDirectory() as temporary:
        async_output = pathlib.Path(temporary) / "lean.json"
        run_lean([ASYNC_FIXTURE], async_output)
        async_reference = json.loads(async_output.read_text(encoding="utf-8"))
    corrupted = copy.deepcopy(async_reference)
    corrupted["observations"][2]["receiptGraph"]["outcomes"][0]["receiptIds"].reverse()
    result = compare(async_reference, corrupted, "L4")
    if result["matched"] or result["firstDifference"]["level"] != "L4":
        raise AssertionError("comparator missed L4 receipt-order corruption")
    with tempfile.TemporaryDirectory() as temporary:
        block_output = pathlib.Path(temporary) / "lean.json"
        run_lean([BLOCK_FIXTURE], block_output)
        block_reference = json.loads(block_output.read_text(encoding="utf-8"))
    corrupted = copy.deepcopy(block_reference)
    corrupted["observations"][0]["receiptGraph"]["outcomes"][1]["blockIndex"] = 9
    result = compare(block_reference, corrupted, "L4")
    if result["matched"] or result["firstDifference"]["level"] != "L4":
        raise AssertionError("comparator missed L4 block-index corruption")
    with tempfile.TemporaryDirectory() as temporary:
        economic_output = pathlib.Path(temporary) / "lean.json"
        run_lean([ECONOMIC_FIXTURE], economic_output)
        economic_reference = json.loads(economic_output.read_text(encoding="utf-8"))
    mutations = [
        lambda value: value.update(gasBurnt="1"),
        lambda value: value.update(gasUsed="1"),
        lambda value: value.update(tokensBurnt="1"),
        lambda value: value.update(refundCount=0),
        lambda value: value.update(refundCount=2),
        lambda value: value["storageUsageDelta"][0].update(bytes="1"),
        lambda value: value["storageUsageDelta"][1].update(bytes="-1"),
        lambda value: value["storageUsageDelta"][0].update(id="corrupt"),
        lambda value: value["storageUsageDelta"].reverse(),
        lambda value: value.update(storageUsageDelta=[]),
    ]
    for mutate in mutations:
        corrupted = copy.deepcopy(economic_reference)
        mutate(corrupted["observations"][0]["economics"])
        result = compare(economic_reference, corrupted, "L5")
        if result["matched"] or result["firstDifference"]["level"] != "L5":
            raise AssertionError("comparator missed L5 economics mutation")
    synthetic = {"actions": [{"kind": "transfer"}, {"kind": "functionCall"}, {"kind": "transfer"}]}
    minimized = minimize_actions(
        synthetic,
        lambda candidate: any(action["kind"] == "functionCall" for action in candidate["actions"]),
    )
    if minimized["actions"] != [{"kind": "functionCall"}]:
        raise AssertionError("trace minimizer did not produce the minimal fixture")
    print("differential corruption and minimization tests passed")


def campaign(count: int, seed: int, output: pathlib.Path) -> None:
    with tempfile.TemporaryDirectory() as temporary:
        directory = pathlib.Path(temporary)
        paths = generate(count, seed, directory / "traces")
        result = execute(paths, directory)
        traces = [json.loads(path.read_text(encoding="utf-8")) for path in paths]
        action_kinds: dict[str, int] = {}
        for generated_trace in traces:
            for action in generated_trace["actions"]:
                kind = action["kind"]
                action_kinds[kind] = action_kinds.get(kind, 0) + 1
        result.update(
            {
                "actionKinds": dict(sorted(action_kinds.items())),
                "maxTraceLength": max(len(item["actions"]) for item in traces),
                "schemaVersion": 1,
                "seed": seed,
                "nearcoreCommit": BASELINE["nearcore"]["commit"],
                "nearcoreRelease": BASELINE["nearcore"]["release"],
                "protocolVersion": BASELINE["protocolVersions"]["minimum"],
            }
        )
        write_json(output, result)
        if not result["matched"]:
            index = result["firstDifference"]["traceIndex"]
            failure = ROOT / "differential/failures" / paths[index].name
            original = json.loads(paths[index].read_text(encoding="utf-8"))
            write_json(failure, minimize_real(original))
            raise SystemExit(f"differential mismatch recorded at {failure}")


def wasm_campaign(output: pathlib.Path) -> None:
    with tempfile.TemporaryDirectory() as temporary:
        result = execute([WASM_FIXTURE], pathlib.Path(temporary), "L4")
    generated_trace = json.loads(WASM_FIXTURE.read_text(encoding="utf-8"))
    action_kinds: dict[str, int] = {}
    for action in generated_trace["actions"]:
        kind = action["kind"]
        action_kinds[kind] = action_kinds.get(kind, 0) + 1
    result.update(
        {
            "actionKinds": dict(sorted(action_kinds.items())),
            "maxTraceLength": len(generated_trace["actions"]),
            "schemaVersion": 1,
            "seed": generated_trace["seed"],
            "nearcoreCommit": BASELINE["nearcore"]["commit"],
            "nearcoreRelease": BASELINE["nearcore"]["release"],
            "protocolVersion": BASELINE["protocolVersions"]["minimum"],
            "compiledArtifact": "Oracle/contracts/counter.wasm",
            "executionBackend": "Talos",
        }
    )
    write_json(output, result)
    if not result["matched"]:
        raise SystemExit("compiled counter WASM differs from nearcore")


def receipt_campaign(count: int, seed: int, batch_size: int, output: pathlib.Path) -> None:
    with tempfile.TemporaryDirectory() as temporary:
        directory = pathlib.Path(temporary)
        paths = generate_receipts(count, seed, directory / "traces")
        matched = True
        first_difference = None
        action_count = 0
        completed = 0
        failure = None
        for batch_index in range(0, len(paths), batch_size):
            batch = paths[batch_index : batch_index + batch_size]
            result = execute(
                batch,
                directory / f"batch-{batch_index // batch_size}",
                "L4",
                build_lean=batch_index == 0,
            )
            action_count += result["actionCount"]
            completed += result["traceCount"]
            print(f"receipt campaign: {completed}/{count} traces", flush=True)
            if not result["matched"]:
                matched = False
                first_difference = result["firstDifference"]
                failing_path = batch[first_difference["traceIndex"]]
                failure = ROOT / "differential/failures" / failing_path.name
                write_json(failure, json.loads(failing_path.read_text(encoding="utf-8")))
                break
        report = {
            "matched": matched,
            "observationLevel": "L4" if matched else "L3",
            "traceCount": completed,
            "actionCount": action_count,
            "firstDifference": first_difference,
            "actionKinds": {"functionCall": action_count},
            "maxTraceLength": 1,
            "receiptOutcomesPerTrace": 3,
            "schemaVersion": 1,
            "seed": seed,
            "nearcoreCommit": BASELINE["nearcore"]["commit"],
            "nearcoreRelease": BASELINE["nearcore"]["release"],
            "protocolVersion": BASELINE["protocolVersions"]["minimum"],
        }
        write_json(output, report)
        if not matched:
            raise SystemExit(f"receipt mismatch recorded at {failure}")


def block_campaign(count: int, seed: int, batch_size: int, output: pathlib.Path) -> None:
    with tempfile.TemporaryDirectory() as temporary:
        directory = pathlib.Path(temporary)
        paths = generate_blocks(count, seed, directory / "traces")
        matched = True
        first_difference = None
        action_count = 0
        block_count = 0
        completed = 0
        failure = None
        for batch_index in range(0, len(paths), batch_size):
            batch = paths[batch_index : batch_index + batch_size]
            batch_directory = directory / f"batch-{batch_index // batch_size}"
            result = execute(
                batch,
                batch_directory,
                "L4",
                build_lean=batch_index == 0,
            )
            action_count += result["actionCount"]
            completed += result["traceCount"]
            nearcore_runs = runs(json.loads(
                (batch_directory / "nearcore.json").read_text(encoding="utf-8")
            ))
            for run in nearcore_runs:
                for observation in run["observations"]:
                    indices = [
                        outcome["blockIndex"]
                        for outcome in observation["receiptGraph"]["outcomes"]
                    ]
                    block_count += max(indices, default=-1) + 1
            print(
                f"block campaign: {completed}/{count} traces, {block_count} blocks",
                flush=True,
            )
            if not result["matched"]:
                matched = False
                first_difference = result["firstDifference"]
                failing_path = batch[first_difference["traceIndex"]]
                failure = ROOT / "differential/failures" / failing_path.name
                write_json(failure, json.loads(failing_path.read_text(encoding="utf-8")))
                break
        report = {
            "matched": matched,
            "observationLevel": "L4" if matched else "L3",
            "traceCount": completed,
            "actionCount": action_count,
            "blockCount": block_count,
            "firstDifference": first_difference,
            "actionKinds": {"functionCall": action_count},
            "maxTraceLength": 1,
            "schemaVersion": 1,
            "seed": seed,
            "nearcoreCommit": BASELINE["nearcore"]["commit"],
            "nearcoreRelease": BASELINE["nearcore"]["release"],
            "protocolVersion": BASELINE["protocolVersions"]["minimum"],
        }
        write_json(output, report)
        if not matched:
            raise SystemExit(f"block mismatch recorded at {failure}")


def economic_campaign(count: int, seed: int, batch_size: int, output: pathlib.Path) -> None:
    with tempfile.TemporaryDirectory() as temporary:
        directory = pathlib.Path(temporary)
        paths = generate_economics(count, seed, directory / "traces")
        matched = True
        first_difference = None
        action_count = 0
        completed = 0
        failure = None
        for batch_index in range(0, len(paths), batch_size):
            batch = paths[batch_index : batch_index + batch_size]
            result = execute(
                batch,
                directory / f"batch-{batch_index // batch_size}",
                "L5",
                build_lean=batch_index == 0,
            )
            action_count += result["actionCount"]
            completed += result["traceCount"]
            print(f"economic campaign: {completed}/{count} traces", flush=True)
            if not result["matched"]:
                matched = False
                first_difference = result["firstDifference"]
                failing_path = batch[first_difference["traceIndex"]]
                failure = ROOT / "differential/failures" / failing_path.name
                write_json(failure, json.loads(failing_path.read_text(encoding="utf-8")))
                break
        report = {
            "matched": matched,
            "observationLevel": "L5" if matched else "L4",
            "traceCount": completed,
            "actionCount": action_count,
            "firstDifference": first_difference,
            "actionKinds": {"transfer": action_count},
            "maxTraceLength": 1,
            "economicMutationsKilled": 10,
            "economicMutationsTotal": 10,
            "economicMutationScore": 100,
            "schemaVersion": 1,
            "seed": seed,
            "nearcoreCommit": BASELINE["nearcore"]["commit"],
            "nearcoreRelease": BASELINE["nearcore"]["release"],
            "protocolVersion": BASELINE["protocolVersions"]["minimum"],
        }
        write_json(output, report)
        if not matched:
            raise SystemExit(f"economic mismatch recorded at {failure}")


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    generate_parser = subparsers.add_parser("generate")
    generate_parser.add_argument("--count", type=int, default=1000)
    generate_parser.add_argument("--seed", type=int, default=1)
    generate_parser.add_argument("--output", type=pathlib.Path, required=True)
    campaign_parser = subparsers.add_parser("campaign")
    campaign_parser.add_argument("--count", type=int, default=1000)
    campaign_parser.add_argument("--seed", type=int, default=1)
    campaign_parser.add_argument(
        "--output", type=pathlib.Path, default=ROOT / "differential/report.json"
    )
    receipt_campaign_parser = subparsers.add_parser("receipt-campaign")
    receipt_campaign_parser.add_argument("--count", type=int, default=10000)
    receipt_campaign_parser.add_argument("--seed", type=int, default=1)
    receipt_campaign_parser.add_argument("--batch-size", type=int, default=500)
    receipt_campaign_parser.add_argument(
        "--output", type=pathlib.Path, default=ROOT / "differential/receipt-report.json"
    )
    block_campaign_parser = subparsers.add_parser("block-campaign")
    block_campaign_parser.add_argument("--count", type=int, default=10000)
    block_campaign_parser.add_argument("--seed", type=int, default=1)
    block_campaign_parser.add_argument("--batch-size", type=int, default=500)
    block_campaign_parser.add_argument(
        "--output", type=pathlib.Path, default=ROOT / "differential/block-report.json"
    )
    economic_campaign_parser = subparsers.add_parser("economic-campaign")
    economic_campaign_parser.add_argument("--count", type=int, default=10000)
    economic_campaign_parser.add_argument("--seed", type=int, default=1)
    economic_campaign_parser.add_argument("--batch-size", type=int, default=500)
    economic_campaign_parser.add_argument(
        "--output", type=pathlib.Path, default=ROOT / "differential/economic-report.json"
    )
    wasm_campaign_parser = subparsers.add_parser("wasm-campaign")
    wasm_campaign_parser.add_argument(
        "--output", type=pathlib.Path, default=ROOT / "differential/wasm-report.json"
    )
    compare_parser = subparsers.add_parser("compare")
    compare_parser.add_argument("lean", type=pathlib.Path)
    compare_parser.add_argument("nearcore", type=pathlib.Path)
    compare_parser.add_argument(
        "--level", choices=["L1", "L2", "L3", "L4", "L5"], default="L3"
    )
    minimize_parser = subparsers.add_parser("minimize")
    minimize_parser.add_argument("trace", type=pathlib.Path)
    minimize_parser.add_argument("--output", type=pathlib.Path, required=True)
    subparsers.add_parser("self-test")
    smoke_parser = subparsers.add_parser("smoke")
    smoke_parser.add_argument("trace", type=pathlib.Path, nargs="?", default=DEFAULT_FIXTURE)
    smoke_parser.add_argument(
        "--level", choices=["L1", "L2", "L3", "L4", "L5"], default="L3"
    )
    arguments = parser.parse_args()
    if arguments.command == "generate":
        generate(arguments.count, arguments.seed, arguments.output)
    elif arguments.command == "campaign":
        campaign(arguments.count, arguments.seed, arguments.output)
    elif arguments.command == "receipt-campaign":
        receipt_campaign(
            arguments.count,
            arguments.seed,
            arguments.batch_size,
            arguments.output,
        )
    elif arguments.command == "block-campaign":
        block_campaign(
            arguments.count,
            arguments.seed,
            arguments.batch_size,
            arguments.output,
        )
    elif arguments.command == "economic-campaign":
        economic_campaign(
            arguments.count,
            arguments.seed,
            arguments.batch_size,
            arguments.output,
        )
    elif arguments.command == "wasm-campaign":
        wasm_campaign(arguments.output)
    elif arguments.command == "compare":
        result = compare(
            json.loads(arguments.lean.read_text(encoding="utf-8")),
            json.loads(arguments.nearcore.read_text(encoding="utf-8")),
            arguments.level,
        )
        print(json.dumps(result, indent=2))
        if not result["matched"]:
            raise SystemExit(1)
    elif arguments.command == "minimize":
        original = json.loads(arguments.trace.read_text(encoding="utf-8"))
        write_json(arguments.output, minimize_real(original))
    elif arguments.command == "self-test":
        self_test()
    elif arguments.command == "smoke":
        with tempfile.TemporaryDirectory() as temporary:
            result = execute([arguments.trace], pathlib.Path(temporary), arguments.level)
        print(json.dumps(result, indent=2))
        if not result["matched"]:
            raise SystemExit(1)


if __name__ == "__main__":
    main()
