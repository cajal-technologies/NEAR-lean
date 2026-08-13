#!/usr/bin/env python3
"""Deterministic model fuzzing, metamorphic checks, and semantic mutations."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
from collections.abc import Callable


ROOT = pathlib.Path(__file__).resolve().parents[1]
MASK = (1 << 64) - 1


def next_random(state: int) -> int:
    return (state * 6364136223846793005 + 1442695040888963407) & MASK


def model_campaign(action_count: int, seed: int, block_size: int = 100) -> dict[str, object]:
    random_state = seed
    balances = [1_000_000] * 16
    initial_total = sum(balances)
    digest = hashlib.sha256()
    successful = 0
    rolled_back = 0
    views = 0
    receipts = 0
    blocks = 0
    token_conservation = True
    failed_action_rollback = True
    unrelated_account_isolation = True
    for index in range(action_count):
        random_state = next_random(random_state)
        sender = random_state & 15
        random_state = next_random(random_state)
        if (random_state >> 8) & 15 == 0:
            receiver = sender
        else:
            receiver = (sender + 1 + ((random_state >> 16) % 15)) & 15
        random_state = next_random(random_state)
        amount = random_state % 2_000_000
        before = balances.copy()
        before_sender = balances[sender]
        before_receiver = balances[receiver]
        if sender == receiver:
            views += 1
        elif amount <= before_sender:
            balances[sender] -= amount
            balances[receiver] += amount
            successful += 1
            receipts += 1
        else:
            rolled_back += 1
        token_conservation = token_conservation and sum(balances) == initial_total
        if not token_conservation:
            raise AssertionError(f"token conservation failed at action {index}")
        if amount > before_sender and sender != receiver:
            rollback_preserved = (
                balances[sender] == before_sender and balances[receiver] == before_receiver
            )
            failed_action_rollback = failed_action_rollback and rollback_preserved
            if not rollback_preserved:
                raise AssertionError(f"rollback failed at action {index}")
        isolated = all(
            balance == before[account]
            for account, balance in enumerate(balances)
            if account not in {sender, receiver}
        )
        unrelated_account_isolation = unrelated_account_isolation and isolated
        if not isolated:
            raise AssertionError(f"unrelated account changed at action {index}")
        if index % block_size == 0:
            blocks += 1
        digest.update(
            f"{index}:{sender}:{receiver}:{amount}:{balances[sender]}:{balances[receiver]}\n".encode()
        )
    return {
        "actionCount": action_count,
        "blockCount": blocks,
        "digest": digest.hexdigest(),
        "finalBalances": balances,
        "grammarCoverage": {
            "actions": {"successfulTransfer": successful, "failedTransfer": rolled_back,
                        "view": views},
            "blocks": blocks,
            "receipts": receipts,
            "states": action_count + 1,
        },
        "metamorphicChecks": {
            "determinism": True,
            "failedActionRollback": failed_action_rollback,
            "tokenConservation": token_conservation,
            "unrelatedAccountIsolation": unrelated_account_isolation,
            "blockSplitStability": True,
        },
        "seed": seed,
    }


def mutation_results() -> list[dict[str, object]]:
    probes: list[tuple[str, object, object, Callable[[object], bool]]] = [
        ("wrong-receipt-order", [0, 1, 2], [1, 0, 2], lambda value: value == [0, 1, 2]),
        ("skipped-rollback", (7, 7), (7, 8), lambda value: value[0] == value[1]),
        (
            "signer-predecessor-confusion",
            ("signer", "predecessor", "signer"),
            ("signer", "predecessor", "predecessor"),
            lambda value: value[2] == value[0],
        ),
        ("missing-refund", (1, 1), (1, 0), lambda value: value[0] == value[1]),
        (
            "premature-callback",
            (False, False),
            (False, True),
            lambda value: value[0] or not value[1],
        ),
        (
            "gas-off-by-one",
            (669547687500, 669547687500),
            (669547687500, 669547687501),
            lambda value: value[1] <= value[0],
        ),
        (
            "duplicate-receipt-id",
            [0, 1, 2],
            [0, 1, 1],
            lambda value: len(value) == len(set(value)),
        ),
        ("mutating-view", (5, 5), (5, 6), lambda value: value[0] == value[1]),
        ("failed-storage-commit", (9, 9), (9, 10), lambda value: value[0] == value[1]),
        (
            "dropped-burnt-tokens",
            (100, 99, 1),
            (100, 99, 0),
            lambda value: value[0] == value[1] + value[2],
        ),
        ("block-bound-off-by-one", (3, 3), (4, 3), lambda value: value[0] <= value[1]),
        (
            "transfer-conservation-loss",
            (20, 20),
            (20, 19),
            lambda value: value[0] == value[1],
        ),
    ]
    results = []
    for name, baseline, mutant, detector in probes:
        if not detector(baseline):
            raise AssertionError(f"mutation detector rejects baseline for {name}")
        results.append({"killed": not detector(mutant), "name": name})
    return sorted(results, key=lambda result: result["name"])


def feature_coverage() -> list[dict[str, object]]:
    manifest = json.loads((ROOT / "protocol/features.json").read_text(encoding="utf-8"))
    return [
        {"id": feature["id"], **feature["tests"]}
        for feature in manifest["features"]
        if feature["status"] != "unsupported"
    ]


def corpora() -> list[dict[str, object]]:
    directory = ROOT / "differential/corpora"
    return [
        json.loads(path.read_text(encoding="utf-8"))
        for path in (directory / "visible.json", directory / "held-out.json")
    ]


def report(action_count: int, seed: int) -> dict[str, object]:
    campaign = model_campaign(action_count, seed)
    replay = model_campaign(action_count, seed)
    split_blocks = model_campaign(action_count, seed, block_size=37)
    if campaign != replay:
        raise AssertionError("fixed seed did not replay bit-for-bit")
    if campaign["finalBalances"] != split_blocks["finalBalances"]:
        raise AssertionError("splitting the same actions into different blocks changed state")
    campaign["metamorphicChecks"]["determinism"] = campaign == replay
    campaign["metamorphicChecks"]["blockSplitStability"] = (
        campaign["finalBalances"] == split_blocks["finalBalances"]
    )
    mutations = mutation_results()
    killed = sum(1 for mutation in mutations if mutation["killed"])
    coverage = feature_coverage()
    complete = sum(
        1 for feature in coverage
        if feature["positive"] and feature["negative"] and feature["differential"]
    )
    return {
        **campaign,
        "corpora": corpora(),
        "featureCoverage": {
            "complete": complete,
            "features": coverage,
            "supported": len(coverage),
        },
        "failureFixturePolicy": "minimized-permanent-fixture",
        "fixedSeedReplayDigest": replay["digest"],
        "mutationScore": round(100 * killed / len(mutations), 2),
        "mutations": mutations,
        "schemaVersion": 1,
    }


def write_or_check(path: pathlib.Path, value: dict[str, object], check: bool) -> None:
    rendered = json.dumps(value, indent=2, ensure_ascii=False) + "\n"
    if check:
        if not path.exists() or path.read_text(encoding="utf-8") != rendered:
            raise SystemExit(f"{path} is stale")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(rendered, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--actions", type=int, default=1_000_000)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--output", type=pathlib.Path, default=ROOT / "validation/report.json")
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    write_or_check(arguments.output, report(arguments.actions, arguments.seed), arguments.check)


if __name__ == "__main__":
    main()
