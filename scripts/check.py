#!/usr/bin/env python3
"""Dependency-free Milestone 0 quality gates and scorecard generator."""

from __future__ import annotations

import argparse
import copy
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from collections import Counter


ROOT = pathlib.Path(__file__).resolve().parents[1]
IGNORED_PARTS = {".git", ".lake", "build", "Negative", "__pycache__"}
FORMATTED_SUFFIXES = {
    ".css",
    ".html",
    ".json",
    ".lean",
    ".md",
    ".py",
    ".sh",
    ".toml",
    ".yaml",
    ".yml",
}
PROHIBITED_LEAN = {
    name: re.compile(rf"\b{name}\b") for name in ("admit", "axiom", "opaque", "sorry", "unsafe")
}
STATUS_VALUES = ["unsupported", "partial", "implemented", "verified"]
STATUS_RANK = {status: rank for rank, status in enumerate(STATUS_VALUES)}
TEST_KINDS = {"differential", "negative", "positive"}
SHA1 = re.compile(r"[0-9a-f]{40}")
AUDIT_MARKER = "AXIOM_AUDIT\t"


def load_json(path: pathlib.Path) -> object:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def repository_files() -> list[pathlib.Path]:
    files: list[pathlib.Path] = []
    for path in ROOT.rglob("*"):
        if not path.is_file() or any(part in IGNORED_PARTS for part in path.parts):
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


def lean_code_only(text: str) -> str:
    """Blank comments and strings while preserving offsets and line numbers."""
    output = list(text)
    index = 0
    block_depth = 0
    in_string = False
    while index < len(text):
        if block_depth:
            if text.startswith("/-", index):
                output[index : index + 2] = "  "
                block_depth += 1
                index += 2
            elif text.startswith("-/", index):
                output[index : index + 2] = "  "
                block_depth -= 1
                index += 2
            else:
                if text[index] != "\n":
                    output[index] = " "
                index += 1
        elif in_string:
            if text[index] == "\\" and index + 1 < len(text):
                output[index : index + 2] = "  "
                index += 2
            else:
                if text[index] != "\n":
                    output[index] = " "
                if text[index] == '"':
                    in_string = False
                index += 1
        elif text.startswith("--", index):
            while index < len(text) and text[index] != "\n":
                output[index] = " "
                index += 1
        elif text.startswith("/-", index):
            output[index : index + 2] = "  "
            block_depth = 1
            index += 2
        elif text[index] == '"':
            output[index] = " "
            in_string = True
            index += 1
        else:
            index += 1
    return "".join(output)


def policy_errors(paths: list[pathlib.Path]) -> list[str]:
    errors: list[str] = []
    for path in paths:
        if path.suffix != ".lean":
            continue
        text = path.read_text(encoding="utf-8")
        code = lean_code_only(text)
        relative = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path
        for name, pattern in PROHIBITED_LEAN.items():
            match = pattern.search(code)
            if match:
                line = text.count("\n", 0, match.start()) + 1
                errors.append(f"{relative}:{line}: prohibited Lean construct `{name}`")
    return errors


def is_integer(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def feature_errors(feature: object, index: int, valid_statuses: set[str]) -> list[str]:
    if not isinstance(feature, dict):
        return [f"feature {index} is not an object"]
    errors: list[str] = []
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
    missing = required - feature.keys()
    if missing:
        errors.append(f"feature {index} missing: {', '.join(sorted(missing))}")
    feature_id = feature.get("id")
    label = feature_id if isinstance(feature_id, str) and feature_id else index
    for field in ("id", "name", "group", "nearcoreReference"):
        value = feature.get(field)
        if not isinstance(value, str) or not value.strip():
            errors.append(f"feature {label} field `{field}` must be a non-empty string")
    milestone = feature.get("milestone")
    if not is_integer(milestone) or not 1 <= milestone <= 14:
        errors.append(f"feature {label} milestone must be an integer from 1 through 14")
    weight = feature.get("weight")
    if not is_integer(weight) or weight <= 0:
        errors.append(f"feature {label} must have positive integer weight")
    status = feature.get("status")
    if status not in valid_statuses:
        errors.append(f"feature {label} has invalid status")
    executable = feature.get("executableSemantics")
    if not isinstance(executable, bool):
        errors.append(f"feature {label} executableSemantics must be boolean")
    tests = feature.get("tests")
    tests_valid = isinstance(tests, dict) and set(tests) == TEST_KINDS
    if not tests_valid:
        errors.append(f"feature {label} needs exactly all three test coverage fields")
    elif any(not isinstance(tests[kind], bool) for kind in TEST_KINDS):
        errors.append(f"feature {label} test coverage fields must be boolean")
        tests_valid = False
    deviations = feature.get("knownDeviations")
    if not isinstance(deviations, list) or any(
        not isinstance(item, str) or not item.strip() for item in deviations
    ):
        errors.append(f"feature {label} known deviations must be a list of non-empty strings")
    obligations = feature.get("proofObligations")
    obligations_valid = isinstance(obligations, list)
    if not obligations_valid:
        errors.append(f"feature {label} proof obligations must be a list")
        obligations = []
    else:
        obligation_ids: list[str] = []
        for obligation_index, obligation in enumerate(obligations):
            if not isinstance(obligation, dict):
                errors.append(f"feature {label} proof obligation {obligation_index} is not an object")
                obligations_valid = False
                continue
            obligation_id = obligation.get("id")
            if not isinstance(obligation_id, str) or not obligation_id.strip():
                errors.append(f"feature {label} proof obligation {obligation_index} needs an id")
                obligations_valid = False
            else:
                obligation_ids.append(obligation_id)
            if not isinstance(obligation.get("discharged"), bool):
                errors.append(
                    f"feature {label} proof obligation {obligation_index} needs boolean discharged"
                )
                obligations_valid = False
        duplicates = sorted(item for item, count in Counter(obligation_ids).items() if count > 1)
        if duplicates:
            errors.append(f"feature {label} has duplicate proof obligations: {', '.join(duplicates)}")
            obligations_valid = False
    if status in valid_statuses and isinstance(executable, bool) and tests_valid:
        evidence = executable or any(tests.values()) or bool(obligations)
        if status == "unsupported" and evidence:
            errors.append(f"feature {label} is unsupported but claims implementation evidence")
        elif status == "partial" and not evidence:
            errors.append(f"feature {label} is partial but records no implementation evidence")
        elif status == "implemented" and not (
            executable and tests["positive"] and tests["negative"]
        ):
            errors.append(
                f"feature {label} is implemented without executable, positive, and negative evidence"
            )
        elif status == "verified":
            proofs_complete = bool(obligations) and obligations_valid and all(
                obligation["discharged"] for obligation in obligations
            )
            if not (executable and all(tests.values()) and proofs_complete):
                errors.append(
                    f"feature {label} is verified without executable, test, and discharged proof evidence"
                )
    return errors


def reference_snapshot_errors(manifest: dict[str, object]) -> list[str]:
    errors: list[str] = []
    snapshot = load_json(ROOT / "protocol/nearcore-references.json")
    if not isinstance(snapshot, dict):
        return ["nearcore reference snapshot must be a JSON object"]
    if snapshot.get("commit") != manifest.get("nearcoreCommit"):
        errors.append("nearcore reference snapshot commit does not match feature manifest")
    references = snapshot.get("references")
    if not isinstance(references, list):
        return errors + ["nearcore reference snapshot needs a references array"]
    snapshot_paths: list[str] = []
    for index, reference in enumerate(references):
        if not isinstance(reference, dict):
            errors.append(f"nearcore reference {index} is not an object")
            continue
        path = reference.get("path")
        object_id = reference.get("object")
        kind = reference.get("type")
        if not isinstance(path, str) or not path:
            errors.append(f"nearcore reference {index} needs a path")
        else:
            snapshot_paths.append(path)
        if not isinstance(object_id, str) or not SHA1.fullmatch(object_id):
            errors.append(f"nearcore reference {path or index} needs a Git object SHA")
        if kind not in {"blob", "tree"}:
            errors.append(f"nearcore reference {path or index} has invalid object type")
    duplicates = sorted(item for item, count in Counter(snapshot_paths).items() if count > 1)
    if duplicates:
        errors.append(f"duplicate nearcore reference paths: {', '.join(duplicates)}")
    features = manifest.get("features", [])
    feature_paths = {
        feature.get("nearcoreReference")
        for feature in features
        if isinstance(feature, dict) and isinstance(feature.get("nearcoreReference"), str)
    }
    missing = sorted(feature_paths - set(snapshot_paths))
    unused = sorted(set(snapshot_paths) - feature_paths)
    if missing:
        errors.append(f"nearcore references missing provenance: {', '.join(missing)}")
    if unused:
        errors.append(f"nearcore reference snapshot has unused paths: {', '.join(unused)}")
    return errors


def ratchet_errors(current: dict[str, object], previous: dict[str, object]) -> list[str]:
    errors: list[str] = []
    current_range = current.get("protocolVersionRange")
    previous_range = previous.get("protocolVersionRange")
    if isinstance(current_range, dict) and isinstance(previous_range, dict):
        if current_range.get("minimum", 0) > previous_range.get("minimum", 0):
            errors.append("protocol minimum may not increase and narrow the supported range")
        if current_range.get("maximum", 0) < previous_range.get("maximum", 0):
            errors.append("protocol maximum may not decrease and narrow the supported range")
    current_features = {
        feature.get("id"): feature
        for feature in current.get("features", [])
        if isinstance(feature, dict) and isinstance(feature.get("id"), str)
    }
    previous_features = {
        feature.get("id"): feature
        for feature in previous.get("features", [])
        if isinstance(feature, dict) and isinstance(feature.get("id"), str)
    }
    removed = sorted(previous_features.keys() - current_features.keys())
    if removed:
        errors.append(f"feature IDs may not be removed: {', '.join(removed)}")
    for feature_id in sorted(previous_features.keys() & current_features.keys()):
        old = previous_features[feature_id]
        new = current_features[feature_id]
        for field in ("group", "milestone", "name", "weight"):
            if old.get(field) != new.get(field):
                errors.append(f"feature {feature_id} immutable field `{field}` changed")
        old_status = old.get("status")
        new_status = new.get("status")
        if old_status in STATUS_RANK and new_status in STATUS_RANK:
            if STATUS_RANK[new_status] < STATUS_RANK[old_status]:
                errors.append(f"feature {feature_id} status regressed from {old_status} to {new_status}")
        if old.get("executableSemantics") is True and new.get("executableSemantics") is not True:
            errors.append(f"feature {feature_id} lost executable semantics evidence")
        old_tests = old.get("tests", {})
        new_tests = new.get("tests", {})
        if isinstance(old_tests, dict) and isinstance(new_tests, dict):
            for kind in TEST_KINDS:
                if old_tests.get(kind) is True and new_tests.get(kind) is not True:
                    errors.append(f"feature {feature_id} lost {kind} test evidence")
        old_obligations = {
            obligation.get("id"): obligation
            for obligation in old.get("proofObligations", [])
            if isinstance(obligation, dict) and isinstance(obligation.get("id"), str)
        }
        new_obligations = {
            obligation.get("id"): obligation
            for obligation in new.get("proofObligations", [])
            if isinstance(obligation, dict) and isinstance(obligation.get("id"), str)
        }
        for obligation_id, obligation in old_obligations.items():
            if obligation_id not in new_obligations:
                errors.append(f"feature {feature_id} removed proof obligation {obligation_id}")
            elif obligation.get("discharged") is True and not new_obligations[obligation_id].get(
                "discharged"
            ):
                errors.append(f"feature {feature_id} regressed proof obligation {obligation_id}")
    return errors


def previous_manifest() -> dict[str, object] | None:
    revision = os.environ.get("NEAR_LEAN_BASE_REV", "").strip()
    if not revision or set(revision) == {"0"}:
        changed = subprocess.run(
            ["git", "diff", "--quiet", "HEAD", "--", "protocol/features.json"],
            cwd=ROOT,
            check=False,
            capture_output=True,
        )
        revision = "HEAD" if changed.returncode == 1 else "HEAD^"
    result = subprocess.run(
        ["git", "show", f"{revision}:protocol/features.json"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        return None
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None
    return data if isinstance(data, dict) else None


def validate_manifest() -> list[str]:
    errors: list[str] = []
    baseline = load_json(ROOT / "protocol/baseline.json")
    manifest = load_json(ROOT / "protocol/features.json")
    if not isinstance(baseline, dict) or not isinstance(manifest, dict):
        return ["protocol manifests must be JSON objects"]
    toolchain = (ROOT / "lean-toolchain").read_text(encoding="utf-8").strip()
    lean = baseline.get("lean")
    nearcore = baseline.get("nearcore")
    protocol_versions = baseline.get("protocolVersions")
    if not isinstance(lean, dict) or lean.get("toolchain") != toolchain:
        errors.append("baseline Lean toolchain does not match lean-toolchain")
    if not isinstance(nearcore, dict) or not SHA1.fullmatch(str(nearcore.get("commit", ""))):
        errors.append("baseline nearcore commit must be a full Git SHA")
    if not isinstance(protocol_versions, dict) or not all(
        is_integer(protocol_versions.get(key)) for key in ("minimum", "maximum")
    ):
        errors.append("baseline protocol version range must contain integer bounds")
    elif protocol_versions["minimum"] > protocol_versions["maximum"]:
        errors.append("baseline protocol version range is inverted")
    commit = nearcore.get("commit") if isinstance(nearcore, dict) else None
    if manifest.get("nearcoreCommit") != commit:
        errors.append("feature manifest nearcore commit does not match baseline")
    if manifest.get("protocolVersionRange") != protocol_versions:
        errors.append("feature manifest protocol range does not match baseline")
    if manifest.get("statusValues") != STATUS_VALUES:
        errors.append("feature status values must use the canonical lifecycle order")
    observation_level = manifest.get("observationLevel")
    if not isinstance(observation_level, str) or not re.fullmatch(r"L[0-7]", observation_level):
        errors.append("feature manifest observationLevel must be L0 through L7")
    features = manifest.get("features")
    if not isinstance(features, list) or not features:
        return errors + ["feature manifest must contain a non-empty features array"]
    ids: list[str] = []
    for index, feature in enumerate(features):
        errors.extend(feature_errors(feature, index, set(STATUS_VALUES)))
        if isinstance(feature, dict) and isinstance(feature.get("id"), str):
            ids.append(feature["id"])
    duplicates = sorted(item for item, count in Counter(ids).items() if count > 1)
    if duplicates:
        errors.append(f"duplicate feature ids: {', '.join(duplicates)}")
    milestones = {feature.get("milestone") for feature in features if isinstance(feature, dict)}
    if milestones != set(range(1, 15)):
        errors.append("manifest must contain at least one feature for every milestone 1-14")
    errors.extend(reference_snapshot_errors(manifest))
    previous = previous_manifest()
    if previous is not None:
        errors.extend(ratchet_errors(manifest, previous))
    return errors


def production_theorems() -> list[str]:
    lines = (ROOT / "audit/theorems.txt").read_text(encoding="utf-8").splitlines()
    return [line.strip() for line in lines if line.strip() and not line.lstrip().startswith("#")]


def production_modules() -> list[str]:
    paths = [ROOT / "NEARLean.lean", *sorted((ROOT / "NEARLean").rglob("*.lean"))]
    return [".".join(path.relative_to(ROOT).with_suffix("").parts) for path in paths]


def allowed_axioms() -> tuple[list[str], list[str]]:
    data = load_json(ROOT / "audit/allowed_axioms.json")
    if not isinstance(data, dict):
        return ["allowed axiom policy must be a JSON object"], []
    allowed = data.get("allowed")
    errors: list[str] = []
    if not isinstance(allowed, list) or any(not isinstance(name, str) or not name for name in allowed):
        errors.append("allowed axiom policy needs a list of non-empty names")
        allowed = []
    if len(set(allowed)) != len(allowed):
        errors.append("allowed axiom policy contains duplicate names")
    rationale = data.get("rationale")
    if not isinstance(rationale, str) or not rationale.strip():
        errors.append("allowed axiom policy needs a rationale")
    return errors, sorted(allowed)


def audit_declarations(imports: list[str], prefixes: list[str]) -> tuple[list[str], dict[str, object]]:
    policy_errors_found, allowed = allowed_axioms()
    prefix_literals = ", ".join(f"`{prefix}" for prefix in prefixes)
    source = "import Lean\n" + "".join(f"import {module}\n" for module in imports)
    source += f"""
open Lean

run_cmd do
  let env ← getEnv
  let prefixes : Array Name := #[{prefix_literals}]
  for h : index in [0:env.header.moduleNames.size] do
    let moduleName := env.header.moduleNames[index]
    if prefixes.any (fun modulePrefix => modulePrefix.isPrefixOf moduleName) then
      for info in env.header.moduleData[index]!.constants do
        let axioms ← collectAxioms info.name
        logInfo m!\"{AUDIT_MARKER}{{info.name}}\\t{{String.intercalate \",\" (axioms.toList.map Name.toString)}}\"
"""
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
    errors = list(policy_errors_found)
    if result.returncode != 0:
        errors.append(f"axiom audit failed to elaborate: {output.strip()}")
    declarations: dict[str, list[str]] = {}
    marker = re.compile(r"AXIOM_AUDIT\t([^\t\r\n]+)\t([^\r\n]*)")
    for match in marker.finditer(output):
        name = match.group(1).strip()
        axioms = sorted(item for item in match.group(2).strip().split(",") if item)
        declarations[name] = axioms
    if not declarations:
        errors.append("axiom audit returned no project declarations")
    allowed_set = set(allowed)
    for name, axioms in declarations.items():
        unexpected = sorted(set(axioms) - allowed_set)
        if unexpected:
            errors.append(f"{name} uses prohibited axioms: {', '.join(unexpected)}")
    headlines = production_theorems() if prefixes == ["NEARLean"] else []
    missing_headlines = sorted(set(headlines) - declarations.keys())
    if missing_headlines:
        errors.append(f"headline theorems missing from project audit: {', '.join(missing_headlines)}")
    report = {
        "allowedAxioms": allowed,
        "declarations": [
            {"axioms": declarations[name], "name": name} for name in sorted(declarations)
        ],
        "headlineTheorems": headlines,
        "modulePrefixes": prefixes,
        "schemaVersion": 1,
    }
    return errors, report


def production_audit() -> tuple[list[str], dict[str, object]]:
    return audit_declarations(production_modules(), ["NEARLean"])


def report_staleness_errors(report: dict[str, object]) -> list[str]:
    path = ROOT / "audit/report.json"
    rendered = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if not path.exists() or path.read_text(encoding="utf-8") != rendered:
        return ["audit/report.json is stale; regenerate it with scripts/check.py audit"]
    return []


def scorecard() -> dict[str, object]:
    manifest = load_json(ROOT / "protocol/features.json")
    baseline = load_json(ROOT / "protocol/baseline.json")
    audit = load_json(ROOT / "audit/report.json")
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
        and all(obligation["discharged"] for obligation in feature["proofObligations"])
    )
    declarations = audit["declarations"]
    return {
        "axiomAudit": {
            "allowedAxioms": audit["allowedAxioms"],
            "auditedDeclarations": len(declarations),
            "declarationsUsingAxioms": sum(1 for item in declarations if item["axioms"]),
            "headlineTheoremNames": audit["headlineTheorems"],
            "headlineTheorems": len(audit["headlineTheorems"]),
        },
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
        "observationLevel": manifest["observationLevel"],
        "schemaVersion": 2,
    }


def online_reference_errors() -> list[str]:
    snapshot = load_json(ROOT / "protocol/nearcore-references.json")
    if not isinstance(snapshot, dict):
        return ["nearcore reference snapshot must be a JSON object"]
    commit = snapshot.get("commit")
    url = f"https://api.github.com/repos/near/nearcore/git/trees/{commit}?recursive=1"
    request = urllib.request.Request(
        url,
        headers={"Accept": "application/vnd.github+json", "User-Agent": "NEAR-Lean-CI"},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            tree_data = json.load(response)
    except (OSError, urllib.error.URLError, json.JSONDecodeError) as error:
        return [f"could not verify nearcore references online: {error}"]
    if tree_data.get("truncated"):
        return ["GitHub returned a truncated nearcore tree"]
    upstream = {
        item["path"]: (item["sha"], item["type"])
        for item in tree_data.get("tree", [])
        if isinstance(item, dict) and {"path", "sha", "type"} <= item.keys()
    }
    errors: list[str] = []
    for reference in snapshot.get("references", []):
        expected = (reference.get("object"), reference.get("type"))
        actual = upstream.get(reference.get("path"))
        if actual != expected:
            errors.append(
                f"nearcore reference provenance mismatch for {reference.get('path')}: "
                f"expected {expected}, got {actual}"
            )
    return errors


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


def expect_success(name: str, errors: list[str]) -> bool:
    if not errors:
        print(f"positive gate passed: {name}")
        return True
    print(f"error: positive fixture failed {name}: {'; '.join(errors)}", file=sys.stderr)
    return False


def run_negative_tests() -> int:
    negative = ROOT / "Tests/Negative"
    manifest = load_json(ROOT / "protocol/features.json")
    invalid_manifest = copy.deepcopy(manifest)
    invalid_feature = invalid_manifest["features"][0]
    invalid_feature["status"] = "verified"
    invalid_feature["knownDeviations"] = []
    invalid_reference_manifest = copy.deepcopy(manifest)
    invalid_reference_manifest["features"][0]["nearcoreReference"] = "missing/path.rs"
    previous = copy.deepcopy(manifest)
    previous["features"][0].update(
        {
            "executableSemantics": True,
            "proofObligations": [{"discharged": True, "id": "proof"}],
            "status": "verified",
            "tests": {kind: True for kind in TEST_KINDS},
        }
    )
    private_audit_errors, _ = audit_declarations(
        ["Tests.Negative.PrivateAxiom"], ["Tests.Negative.PrivateAxiom"]
    )
    transitive_errors, _ = audit_declarations(
        ["Tests.Negative.Axiom"], ["Tests.Negative.Axiom"]
    )
    outcomes = [
        expect_failure("source hygiene", format_errors([negative / "BadFormat.lean"])),
        expect_failure("sorry", policy_errors([negative / "Sorry.lean"])),
        expect_failure("prohibited source axiom", policy_errors([negative / "Axiom.lean"])),
        expect_failure(
            "private source axiom", policy_errors([negative / "PrivateAxiom.lean"])
        ),
        expect_success(
            "keywords in comments and strings",
            policy_errors([negative / "CommentKeywords.lean"]),
        ),
        expect_failure("private declaration axiom audit", private_audit_errors),
        expect_failure("transitive axiom audit", transitive_errors),
        expect_failure(
            "verified lifecycle evidence",
            feature_errors(invalid_feature, 0, set(STATUS_VALUES)),
        ),
        expect_failure(
            "nearcore reference provenance", reference_snapshot_errors(invalid_reference_manifest)
        ),
        expect_failure("feature ratchet", ratchet_errors(manifest, previous)),
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


def json_artifact(path: pathlib.Path, data: dict[str, object], check: bool) -> int:
    rendered = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    output = path if path.is_absolute() else ROOT / path
    if check:
        if not output.exists() or output.read_text(encoding="utf-8") != rendered:
            print(f"error: {output.relative_to(ROOT)} is stale; regenerate it", file=sys.stderr)
            return 1
    else:
        output.write_text(rendered, encoding="utf-8")
    return 0


def main() -> int:
    if sys.version_info < (3, 11):
        print("error: Python 3.11 or newer is required", file=sys.stderr)
        return 2
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("format")
    subparsers.add_parser("lint")
    subparsers.add_parser("negative-tests")
    audit = subparsers.add_parser("audit")
    audit.add_argument("--output", type=pathlib.Path, default=pathlib.Path("audit/report.json"))
    audit.add_argument("--check", action="store_true")
    references = subparsers.add_parser("nearcore-references")
    references.add_argument("--online", action="store_true")
    score = subparsers.add_parser("scorecard")
    score.add_argument("--output", type=pathlib.Path, required=True)
    score.add_argument("--check", action="store_true")
    args = parser.parse_args()

    if args.command == "format":
        return print_errors(format_errors(repository_files()))
    if args.command == "lint":
        lean_files = [path for path in repository_files() if path.suffix == ".lean"]
        audit_errors, report = production_audit()
        errors = policy_errors(lean_files) + validate_manifest() + audit_errors
        errors += report_staleness_errors(report)
        return print_errors(errors)
    if args.command == "negative-tests":
        return run_negative_tests()
    if args.command == "audit":
        errors, report = production_audit()
        if errors:
            return print_errors(errors)
        return json_artifact(args.output, report, args.check)
    if args.command == "nearcore-references":
        manifest = load_json(ROOT / "protocol/features.json")
        errors = reference_snapshot_errors(manifest)
        if args.online:
            errors += online_reference_errors()
        return print_errors(errors)
    if args.command == "scorecard":
        audit_errors, report = production_audit()
        audit_errors += report_staleness_errors(report)
        if audit_errors:
            return print_errors(audit_errors)
        return json_artifact(args.output, scorecard(), args.check)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
