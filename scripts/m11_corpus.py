#!/usr/bin/env python3
"""Generate and check the Milestone 11 synthetic concrete-state corpus."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import pathlib
import subprocess


ROOT = pathlib.Path(__file__).resolve().parents[1]
CORPUS = ROOT / "concrete/synthetic-chunks.json"
NEARCORE_COMMIT = "5af9ca74631e6cf0dae33e77d1a632e94d2952ce"


def le(value: int, width: int) -> bytes:
    return value.to_bytes(width, "little")


def borsh_bytes(value: bytes) -> bytes:
    return le(len(value), 4) + value


def borsh_list(values: list[bytes]) -> bytes:
    return le(len(values), 4) + b"".join(values)


def account_id(index: int) -> bytes:
    return bytes((97, 65 + index))


def account_value(identifier: bytes, account: dict[str, object]) -> bytes:
    contract = account["contract"]
    storage = account["storage"]
    code_hash = hashlib.sha256(contract).digest() if contract is not None else bytes(32)
    storage_usage = len(identifier) + sum(len(key) + len(value) for key, value in storage)
    if contract is not None:
        storage_usage += len(contract)
    return (
        le(account["balance"], 16)
        + le(account["locked"], 16)
        + code_hash
        + le(storage_usage, 8)
    )


def records(accounts: list[tuple[bytes, dict[str, object]]]) -> list[tuple[bytes, bytes]]:
    result: list[tuple[bytes, bytes]] = []
    for identifier, account in accounts:
        result.append((bytes((0,)) + identifier, account_value(identifier, account)))
        if account["contract"] is not None:
            result.append((bytes((1,)) + identifier, account["contract"]))
        result.extend(
            (bytes((9,)) + identifier + bytes((44,)) + key, value)
            for key, value in account["storage"]
        )
    return result


def changes(
    before: list[tuple[bytes, bytes]], after: list[tuple[bytes, bytes]]
) -> list[tuple[bytes, bytes | None]]:
    old = dict(before)
    new = dict(after)
    updates = [(key, value) for key, value in after if old.get(key) != value]
    removals = [(key, None) for key, _ in before if key not in new]
    return updates + removals


def encode_changes(values: list[tuple[bytes, bytes | None]]) -> bytes:
    encoded = []
    for key, value in values:
        encoded.append(borsh_bytes(key) + (b"\x00" if value is None else b"\x01" + borsh_bytes(value)))
    return borsh_list(encoded)


def outcome(executor: bytes, logs: list[bytes], gas: int, returned: bytes) -> bytes:
    return (
        borsh_list([borsh_bytes(log) for log in logs])
        + le(0, 4)
        + le(gas, 8)
        + le(0, 16)
        + borsh_bytes(executor)
        + b"\x02"
        + borsh_bytes(returned)
        + b"\x00"
    )


def json_record(key: bytes, value: bytes | None) -> dict[str, object]:
    return {"key": key.hex(), "value": None if value is None else value.hex()}


def generated_input(count: int = 1000) -> dict[str, object]:
    accounts = [
        (account_id(index), {"balance": 100_000, "locked": 0, "storage": [], "contract": None})
        for index in range(16)
    ]
    counter_id = b"counter"
    accounts.append(
        (counter_id, {"balance": 100, "locked": 0, "storage": [(b"\x01", b"")], "contract": b"\x01"})
    )
    initial = records(accounts)
    previous = initial
    chunks = []
    for index in range(count):
        if index % 5 == 0:
            account = accounts[-1][1]
            account["storage"][0] = (b"\x01", b"\x00" + account["storage"][0][1])
            returned = account["storage"][0][1]
            action = {"kind": "increment", "caller": (index // 5) % 16}
            encoded_outcome = outcome(counter_id, [b"\x01"], 1, returned)
        else:
            sender = index % 16
            receiver = (sender + index % 15 + 1) % 16
            amount = index % 7 + 1
            accounts[sender][1]["balance"] -= amount
            accounts[receiver][1]["balance"] += amount
            action = {
                "kind": "transfer",
                "sender": sender,
                "receiver": receiver,
                "amount": amount,
            }
            encoded_outcome = outcome(account_id(receiver), [], 0, b"")
        current = records(accounts)
        delta = changes(previous, current)
        transaction_hash = hashlib.sha256(f"transaction:{index}".encode()).digest()
        receipt_id = hashlib.sha256(transaction_hash + le(index + 1, 8) + le(0, 8)).digest()
        chunks.append(
            {
                "index": index,
                "action": action,
                "changes": [json_record(key, value) for key, value in delta],
                "stateChangesBorsh": encode_changes(delta).hex(),
                "serializedOutcome": encoded_outcome.hex(),
                "receiptId": receipt_id.hex(),
            }
        )
        previous = current
    return {
        "schemaVersion": 1,
        "nearcoreCommit": NEARCORE_COMMIT,
        "protocolVersion": 86,
        "seed": 11,
        "chunkCount": count,
        "initialRecords": [json_record(key, value) for key, value in initial],
        "chunks": chunks,
    }


def with_oracle(value: dict[str, object], oracle_bin: pathlib.Path) -> dict[str, object]:
    completed = subprocess.run(
        [str(oracle_bin)],
        cwd=ROOT,
        input=json.dumps(value),
        text=True,
        capture_output=True,
        check=True,
    )
    oracle = json.loads(completed.stdout)
    result = copy.deepcopy(value)
    result["nearcoreVectors"] = oracle["vectors"]
    roots = oracle["roots"]
    if len(roots) != len(result["chunks"]):
        raise SystemExit("nearcore oracle returned the wrong root count")
    for chunk, root in zip(result["chunks"], roots, strict=True):
        chunk["stateRoot"] = root
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--oracle-bin", type=pathlib.Path)
    arguments = parser.parse_args()
    generated = generated_input()
    if arguments.oracle_bin:
        generated = with_oracle(generated, arguments.oracle_bin)
    elif CORPUS.exists():
        current = json.loads(CORPUS.read_text(encoding="utf-8"))
        generated["nearcoreVectors"] = current.get("nearcoreVectors")
        for chunk, old_chunk in zip(generated["chunks"], current.get("chunks", []), strict=True):
            chunk["stateRoot"] = old_chunk.get("stateRoot")
    else:
        raise SystemExit("--oracle-bin is required to create the corpus")
    encoded = json.dumps(generated, indent=2) + "\n"
    if arguments.check:
        if CORPUS.read_text(encoding="utf-8") != encoded:
            raise SystemExit("concrete/synthetic-chunks.json is stale")
    else:
        CORPUS.parent.mkdir(parents=True, exist_ok=True)
        CORPUS.write_text(encoded, encoding="utf-8")


if __name__ == "__main__":
    main()
