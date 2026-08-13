#!/usr/bin/env python3
"""Reproduce the Milestone 10 compiled-contract and host-function evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import subprocess


ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTRACTS = ("counter", "escrow", "fungible_token", "nft", "async")
VALIDATOR = ROOT / ".lake/build/bin/m10Validation"
REPORT = ROOT / "host/report.json"


def validator_evidence() -> dict[str, object]:
    completed = subprocess.run(
        [str(VALIDATOR)], cwd=ROOT, check=True, text=True, capture_output=True
    )
    return json.loads(completed.stdout.strip().splitlines()[-1])


def imported_functions() -> list[str]:
    names: set[str] = set()
    pattern = re.compile(r'\(import\s+"env"\s+"([^"]+)"')
    for contract in CONTRACTS:
        source = (ROOT / f"Oracle/contracts/{contract}.wat").read_text(encoding="utf-8")
        names.update(pattern.findall(source))
    return sorted(names)


def generated() -> dict[str, object]:
    evidence = validator_evidence()
    benchmark = json.loads(
        (ROOT / "differential/wasm-benchmark-report.json").read_text(encoding="utf-8")
    )
    artifacts = []
    for contract in CONTRACTS:
        path = ROOT / f"Oracle/contracts/{contract}.wasm"
        artifacts.append(
            {
                "name": contract,
                "path": str(path.relative_to(ROOT)),
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            }
        )
    functions = imported_functions()
    if evidence["hostFunctionCount"] != len(functions):
        raise SystemExit("validator host-function coverage does not match the corpus")
    return {
        "schemaVersion": 1,
        "protocolVersion": 86,
        "nearcoreCommit": "5af9ca74631e6cf0dae33e77d1a632e94d2952ce",
        "talosCommit": "87336df09b41d819c670be99860481573fd00055",
        "generatedCompiledCalls": evidence["compiledCalls"],
        "benchmarkContracts": evidence["benchmarkContracts"],
        "validatedHostFunctions": evidence["hostFunctionCount"],
        "benchmarkArtifacts": artifacts,
        "differential": benchmark,
        "hostGasSchedule": {
            "exactProtocol86ExternalCosts": evidence["hostGasTests"],
            "source": (
                "nearcore core/parameters/src/snapshots/"
                "near_parameters__config_store__tests__85.json.snap"
            ),
            "transactionEnvelopeEconomics": "out of the M10 host-layer scope",
        },
        "nativeWasmRefinement": evidence["nativeWasmRefinement"],
        "promiseCallbacks": evidence["promiseCallbacks"],
        "sha256KnownAnswer": evidence["sha256KnownAnswer"],
        "hostFunctions": [
            {
                "name": name,
                "boundary": evidence["hostBoundaryTests"],
                "error": evidence["hostErrorTests"],
                "gas": evidence["hostGasTests"],
                "differential": benchmark["matched"],
            }
            for name in functions
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    encoded = json.dumps(generated(), indent=2) + "\n"
    if arguments.check:
        if REPORT.read_text(encoding="utf-8") != encoded:
            raise SystemExit("host/report.json is stale")
    else:
        REPORT.parent.mkdir(parents=True, exist_ok=True)
        REPORT.write_text(encoded, encoding="utf-8")


if __name__ == "__main__":
    main()
