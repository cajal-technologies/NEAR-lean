#!/usr/bin/env python3
"""Dependency-free Milestone 0 quality gates and scorecard generator."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys
import tempfile
from collections import Counter


ROOT = pathlib.Path(__file__).resolve().parents[1]
IGNORED_PARTS = {".git", ".lake", "build", "Negative", "__pycache__"}
FORMATTED_SUFFIXES = {".json", ".lean", ".md", ".py", ".sh", ".toml", ".yaml", ".yml"}
PROHIBITED_LEAN = {
    "admit": re.compile(r"\badmit\b"),
    "axiom": re.compile(r"^\s*axiom\b", re.MULTILINE),
    "opaque": re.compile(r"^\s*opaque\b", re.MULTILINE),
    "sorry": re.compile(r"\bsorry\b"),
    "unsafe": re.compile(r"\bunsafe\b"),
}


def load_json(path: pathlib.Path) -> object:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def repository_files() -> list[pathlib.Path]:
    files: list[pathlib.Path] = []
    for path in ROOT.rglob("*"):
        if not path.is_file() or any(part in IGNORED_PARTS for part in path.parts):
            continue
        if path.name == "AGENTS.md":
            continue
        if path.suffix in FORMATTED_SUFFIXES or path.name in {"Makefile", "lean-toolchain"}:
            files.append(path)
    return sorted(files)


def format_errors(paths: list[pathlib.Path]) -> list[str]:
    errors: list[str] = []
    for path in paths:
        raw = path.read_bytes()
        relative = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path
        if raw and not raw.endswith(b"\n"):
            errors.append(f"{relative}: missing final newline")
        if raw.endswith(b"\n\n"):
            errors.append(f"{relative}: extra blank line at end of file")
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            errors.append(f"{relative}: not UTF-8")
            continue
        for line_number, line in enumerate(text.splitlines(), 1):
            if line.rstrip(" \t") != line:
                errors.append(f"{relative}:{line_number}: trailing whitespace")
            if "\t" in line and path.name != "Makefile":
                errors.append(f"{relative}:{line_number}: tab character")
        if path.suffix == ".json" and path.name != "lake-manifest.json":
            try:
                parsed = json.loads(text)
            except json.JSONDecodeError as error:
                errors.append(f"{relative}:{error.lineno}: invalid JSON: {error.msg}")
            else:
                canonical = json.dumps(parsed, indent=2, ensure_ascii=False) + "\n"
                if text != canonical:
                    errors.append(f"{relative}: JSON is not in canonical two-space format")
    return errors


def policy_errors(paths: list[pathlib.Path]) -> list[str]:
    errors: list[str] = []
    for path in paths:
        if path.suffix != ".lean":
            continue
        text = path.read_text(encoding="utf-8")
        relative = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path
        for name, pattern in PROHIBITED_LEAN.items():
            match = pattern.search(text)
            if match:
                line = text.count("\n", 0, match.start()) + 1
                errors.append(f"{relative}:{line}: prohibited Lean construct `{name}`")
    return errors


def validate_manifest() -> list[str]:
    errors: list[str] = []
    baseline = load_json(ROOT / "protocol/baseline.json")
    manifest = load_json(ROOT / "protocol/features.json")
    if not isinstance(baseline, dict) or not isinstance(manifest, dict):
        return ["protocol manifests must be JSON objects"]
    toolchain = (ROOT / "lean-toolchain").read_text(encoding="utf-8").strip()
    if baseline.get("lean", {}).get("toolchain") != toolchain:
        errors.append("baseline Lean toolchain does not match lean-toolchain")
    commit = baseline.get("nearcore", {}).get("commit")
    if manifest.get("nearcoreCommit") != commit:
        errors.append("feature manifest nearcore commit does not match baseline")
    if manifest.get("protocolVersionRange") != baseline.get("protocolVersions"):
        errors.append("feature manifest protocol range does not match baseline")
    features = manifest.get("features")
    if not isinstance(features, list) or not features:
        return errors + ["feature manifest must contain a non-empty features array"]
    ids: list[str] = []
    valid_statuses = set(manifest.get("statusValues", []))
    required = {
        "executableSemantics",
        "group",
        "id",
        "knownDeviations",
        "milestone",
        "name",
        "nearcoreReference",
        "proofObligations",
        "status",
        "tests",
        "weight",
    }
    for index, feature in enumerate(features):
        if not isinstance(feature, dict):
            errors.append(f"feature {index} is not an object")
            continue
        missing = required - feature.keys()
        if missing:
            errors.append(f"feature {index} missing: {', '.join(sorted(missing))}")
        ids.append(str(feature.get("id", "")))
        if feature.get("status") not in valid_statuses:
            errors.append(f"feature {feature.get('id')} has invalid status")
        if not isinstance(feature.get("weight"), int) or feature.get("weight", 0) <= 0:
            errors.append(f"feature {feature.get('id')} must have positive integer weight")
        if not str(feature.get("nearcoreReference", "")).strip():
            errors.append(f"feature {feature.get('id')} lacks a nearcore source reference")
        tests = feature.get("tests")
        if not isinstance(tests, dict) or set(tests) != {"differential", "negative", "positive"}:
            errors.append(f"feature {feature.get('id')} needs all three test coverage fields")
        if not isinstance(feature.get("proofObligations"), list):
            errors.append(f"feature {feature.get('id')} proof obligations must be a list")
        if not isinstance(feature.get("knownDeviations"), list):
            errors.append(f"feature {feature.get('id')} known deviations must be a list")
    duplicates = sorted(item for item, count in Counter(ids).items() if count > 1)
    if duplicates:
        errors.append(f"duplicate feature ids: {', '.join(duplicates)}")
    milestones = {feature.get("milestone") for feature in features if isinstance(feature, dict)}
    if milestones != set(range(1, 15)):
        errors.append("manifest must contain at least one feature for every milestone 1-14")
    return errors


def audit_theorems(theorems: list[str], imports: list[str]) -> list[str]:
    allowed_data = load_json(ROOT / "audit/allowed_axioms.json")
    allowed = set(allowed_data.get("allowed", [])) if isinstance(allowed_data, dict) else set()
    errors: list[str] = []
    for theorem in theorems:
        source = "".join(f"import {module}\n" for module in imports)
        source += f"#print axioms {theorem}\n"
        with tempfile.NamedTemporaryFile(mode="w", suffix=".lean", encoding="utf-8") as handle:
            handle.write(source)
            handle.flush()
            result = subprocess.run(
                ["lake", "env", "lean", handle.name],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
        output = result.stdout + result.stderr
        if result.returncode != 0:
            errors.append(f"axiom audit could not inspect {theorem}: {output.strip()}")
            continue
        match = re.search(r"depends on axioms:\s*\[([^]]*)\]", output)
        used = set()
        if match:
            used = {item.strip() for item in match.group(1).split(",") if item.strip()}
        unexpected = sorted(used - allowed)
        if unexpected:
            errors.append(f"{theorem} uses prohibited axioms: {', '.join(unexpected)}")
    return errors


def production_theorems() -> list[str]:
    lines = (ROOT / "audit/theorems.txt").read_text(encoding="utf-8").splitlines()
    return [line.strip() for line in lines if line.strip() and not line.lstrip().startswith("#")]


def scorecard() -> dict[str, object]:
    manifest = load_json(ROOT / "protocol/features.json")
    baseline = load_json(ROOT / "protocol/baseline.json")
    features = manifest["features"]
    statuses = Counter(feature["status"] for feature in features)
    total_weight = sum(feature["weight"] for feature in features)
    completed_weight = sum(
        feature["weight"] for feature in features if feature["status"] == "verified"
    )
    coverage = {
        kind: sum(1 for feature in features if feature["tests"][kind])
        for kind in ("positive", "negative", "differential")
    }
    coverage["executableSemantics"] = sum(
        1 for feature in features if feature["executableSemantics"]
    )
    coverage["proofObligationsDischarged"] = sum(
        1
        for feature in features
        if feature["proofObligations"]
        and all(obligation.get("discharged", False) for obligation in feature["proofObligations"])
    )
    return {
        "axiomAudit": {"allowedAxioms": [], "headlineTheorems": len(production_theorems())},
        "baseline": {
            "leanToolchain": baseline["lean"]["toolchain"],
            "nearcoreCommit": baseline["nearcore"]["commit"],
            "nearcoreRelease": baseline["nearcore"]["release"],
            "protocolVersionRange": baseline["protocolVersions"],
        },
        "features": {
            "byStatus": {name: statuses.get(name, 0) for name in manifest["statusValues"]},
            "coverage": coverage,
            "total": len(features),
            "verifiedWeightPercent": round(100 * completed_weight / total_weight, 2),
        },
        "observationLevel": "L0",
        "schemaVersion": 1,
    }


def print_errors(errors: list[str]) -> int:
    if not errors:
        return 0
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    return 1


def expect_failure(name: str, errors: list[str]) -> bool:
    if errors:
        print(f"negative gate passed: {name}")
        return True
    print(f"error: negative fixture did not trip {name}", file=sys.stderr)
    return False


def run_negative_tests() -> int:
    negative = ROOT / "Tests/Negative"
    outcomes = [
        expect_failure("formatting", format_errors([negative / "BadFormat.lean"])),
        expect_failure("sorry", policy_errors([negative / "Sorry.lean"])),
        expect_failure("prohibited source axiom", policy_errors([negative / "Axiom.lean"])),
        expect_failure(
            "transitive axiom audit",
            audit_theorems(["NegativeAxiom.usesForbidden"], ["Tests.Negative.Axiom"]),
        ),
    ]
    warning = subprocess.run(
        ["lake", "env", "lean", "-DwarningAsError=true", "Tests/Negative/Warning.lean"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if warning.returncode != 0 and "warning" in (warning.stdout + warning.stderr).lower():
        print("negative gate passed: warning")
        outcomes.append(True)
    else:
        print("error: negative fixture did not trip warning gate", file=sys.stderr)
        outcomes.append(False)
    return 0 if all(outcomes) else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("format")
    subparsers.add_parser("lint")
    subparsers.add_parser("negative-tests")
    score = subparsers.add_parser("scorecard")
    score.add_argument("--output", type=pathlib.Path, required=True)
    score.add_argument("--check", action="store_true")
    args = parser.parse_args()

    if args.command == "format":
        return print_errors(format_errors(repository_files()))
    if args.command == "lint":
        lean_files = [path for path in repository_files() if path.suffix == ".lean"]
        errors = policy_errors(lean_files) + validate_manifest()
        errors += audit_theorems(production_theorems(), ["NEARLean"])
        return print_errors(errors)
    if args.command == "negative-tests":
        return run_negative_tests()
    if args.command == "scorecard":
        rendered = json.dumps(scorecard(), indent=2, ensure_ascii=False) + "\n"
        output = args.output if args.output.is_absolute() else ROOT / args.output
        if args.check:
            if not output.exists() or output.read_text(encoding="utf-8") != rendered:
                print(f"error: {output.relative_to(ROOT)} is stale; run without --check", file=sys.stderr)
                return 1
        else:
            output.write_text(rendered, encoding="utf-8")
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
