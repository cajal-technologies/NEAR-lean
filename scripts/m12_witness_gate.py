#!/usr/bin/env python3
"""Validate the acquisition contract for the exact Milestone 12 witness bundle."""

from __future__ import annotations

import argparse
import copy
import gzip
import hashlib
import json
import pathlib
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "replay/witness-contract.json"
CORPUS = ROOT / "replay/current-era.json.gz"
SHA256_LENGTH = 64


def load_json(path: pathlib.Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def contract_errors(contract: object) -> list[str]:
    if not isinstance(contract, dict):
        return ["witness acquisition contract must be an object"]
    errors: list[str] = []
    corpus = json.loads(gzip.decompress(CORPUS.read_bytes()))
    interval = contract.get("interval", {})
    expected_interval = {
        "startHeight": corpus["interval"]["startHeight"],
        "endHeight": corpus["interval"]["endHeight"],
        "blocks": len(corpus["blocks"]),
        "chunks": len(corpus["chunks"]),
    }
    if contract.get("schemaVersion") != 1 or contract.get("network") != "mainnet":
        errors.append("witness contract schema or network differs")
    if contract.get("protocolVersion") != corpus.get("protocolVersion"):
        errors.append("witness contract protocol version differs")
    if contract.get("nearcoreCommit") != corpus.get("nearcoreCommit"):
        errors.append("witness contract nearcore commit differs")
    if interval != expected_interval:
        errors.append("witness contract interval differs from the historical corpus")
    if contract.get("bundlePath") != "replay/witnesses/index.json":
        errors.append("witness contract bundle path differs")
    if contract.get("runnerPath") != "Oracle/m12_exact_replay":
        errors.append("witness contract runner path differs")
    for field in (
        "requiredEntryFields",
        "requiredResultFields",
        "requiredRunnerReportFields",
        "sourceRequirements",
    ):
        values = contract.get(field)
        if not isinstance(values, list) or not values or any(
            not isinstance(value, str) or not value for value in values
        ):
            errors.append(f"witness contract {field} must be a non-empty string list")
    return errors


def descriptor_errors(
    descriptor: object, required: set[str], label: str
) -> list[str]:
    if not isinstance(descriptor, dict):
        return [f"{label} must be an object"]
    missing = required - set(descriptor)
    return [f"{label} misses fields: {sorted(missing)}"] if missing else []


def exact_errors(contract: dict[str, object], bundle_path: pathlib.Path) -> list[str]:
    if not bundle_path.is_file():
        try:
            label = bundle_path.relative_to(ROOT)
        except ValueError:
            label = bundle_path
        return [f"exact M12 gate is open: missing {label}; v0.4 must remain withheld"]
    bundle = load_json(bundle_path)
    if not isinstance(bundle, dict):
        return ["witness bundle index must be an object"]
    errors: list[str] = []
    corpus = json.loads(gzip.decompress(CORPUS.read_bytes()))
    for field in ("schemaVersion", "network", "protocolVersion", "nearcoreCommit"):
        if bundle.get(field) != contract.get(field):
            errors.append(f"witness bundle {field} differs from its contract")
    source = bundle.get("source")
    if not isinstance(source, dict) or not {
        "uri",
        "acquiredAt",
        "nodeConfigSha256",
        "runnerSha256",
    } <= set(source):
        errors.append("witness bundle source provenance is incomplete")
    entries = bundle.get("entries")
    if not isinstance(entries, list) or len(entries) != len(corpus["chunks"]):
        return errors + ["witness bundle must contain exactly 10,000 entries"]
    required_entry = set(contract["requiredEntryFields"])
    required_result = set(contract["requiredResultFields"])
    seen: set[str] = set()
    for index, (entry, chunk) in enumerate(zip(entries, corpus["chunks"], strict=True)):
        label = f"witness entry {index}"
        entry_errors = descriptor_errors(entry, required_entry, label)
        errors += entry_errors
        if not isinstance(entry, dict) or entry_errors:
            if len(errors) >= 20:
                break
            continue
        expected = {
            "blockHeight": chunk["blockHeight"],
            "shardId": chunk["shardId"],
            "chunkHash": chunk["chunkHash"],
            "inputStateRoot": chunk["inputStateRoot"],
            "expectedOutputStateRoot": chunk["outputStateRoot"],
            "expectedOutcomeSha256": chunk["outcomeSha256"],
        }
        for field, value in expected.items():
            if entry.get(field) != value:
                errors.append(f"{label} {field} differs from the corpus")
        chunk_hash = entry.get("chunkHash")
        if not isinstance(chunk_hash, str) or chunk_hash in seen:
            errors.append(f"{label} has a missing or duplicate chunk hash")
        else:
            seen.add(chunk_hash)
        for prefix in ("witness", "result"):
            relative = entry.get(f"{prefix}Path")
            expected_digest = entry.get(f"{prefix}Sha256")
            path = ROOT / relative if isinstance(relative, str) else None
            if (
                path is None
                or not path.is_file()
                or not isinstance(expected_digest, str)
                or len(expected_digest) != SHA256_LENGTH
                or digest(path) != expected_digest
            ):
                errors.append(f"{label} {prefix} artifact or digest differs")
        result_path = entry.get("resultPath")
        if isinstance(result_path, str) and (ROOT / result_path).is_file():
            result = load_json(ROOT / result_path)
            errors += descriptor_errors(result, required_result, f"replay result {index}")
            if isinstance(result, dict) and (
                result.get("chunkHash") != entry.get("chunkHash")
                or result.get("outputStateRoot") != entry.get("expectedOutputStateRoot")
                or result.get("outcomeSha256") != entry.get("expectedOutcomeSha256")
                or result.get("independentRuntimeExecution") is not True
                or result.get("firstDifference") is not None
            ):
                errors.append(f"replay result {index} does not prove exact agreement")
        if len(errors) >= 20:
            break
    if errors:
        return errors
    runner_path = ROOT / contract["runnerPath"]
    runner_digest = source.get("runnerSha256") if isinstance(source, dict) else None
    if not runner_path.is_file() or not (runner_path.stat().st_mode & 0o111):
        return ["exact M12 gate is open: pinned independent replay runner is missing"]
    if not isinstance(runner_digest, str) or digest(runner_path) != runner_digest:
        return ["independent replay runner digest differs from bundle provenance"]
    completed = subprocess.run(
        [
            str(runner_path),
            "--bundle",
            str(bundle_path),
            "--corpus",
            str(CORPUS),
        ],
        cwd=ROOT,
        capture_output=True,
        check=False,
        text=True,
    )
    if completed.returncode != 0:
        return [f"independent replay runner failed: {completed.stderr.strip()}"]
    try:
        runner_report = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        return [f"independent replay runner emitted invalid JSON: {error}"]
    errors += descriptor_errors(
        runner_report,
        set(contract["requiredRunnerReportFields"]),
        "independent replay report",
    )
    if isinstance(runner_report, dict) and (
        runner_report.get("schemaVersion") != 1
        or runner_report.get("chunks") != 10_000
        or runner_report.get("identicalOutcomes") != 10_000
        or runner_report.get("identicalRoots") != 10_000
        or runner_report.get("independentRuntimeExecution") is not True
        or runner_report.get("firstDifference") is not None
    ):
        errors.append("independent replay report does not satisfy the M12 exit gate")
    return errors


def self_test(contract: dict[str, object]) -> None:
    corrupted = copy.deepcopy(contract)
    corrupted["interval"]["chunks"] = 9_999
    assert contract_errors(corrupted)
    with tempfile.TemporaryDirectory() as directory:
        assert exact_errors(contract, pathlib.Path(directory) / "missing.json")
    print("historical witness acquisition contract tests passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check-contract", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--exact", action="store_true")
    parser.add_argument("--bundle", type=pathlib.Path)
    arguments = parser.parse_args()
    contract = load_json(CONTRACT)
    errors = contract_errors(contract)
    if arguments.self_test and not errors:
        self_test(contract)
    if arguments.exact and not errors:
        configured = ROOT / contract["bundlePath"]
        errors += exact_errors(contract, arguments.bundle or configured)
    if errors:
        raise SystemExit("\n".join(errors))


if __name__ == "__main__":
    main()
