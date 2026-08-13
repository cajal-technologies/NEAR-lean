#!/usr/bin/env python3
"""Generate or verify the canonical Talos validation report."""

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "wasm/report.json"


def report() -> str:
    result = subprocess.run(
        [ROOT / ".lake/build/bin/wasmValidation"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return json.dumps(json.loads(result.stdout), indent=2, ensure_ascii=False) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=pathlib.Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    rendered = report()
    if arguments.check:
        if not arguments.output.exists() or arguments.output.read_text(encoding="utf-8") != rendered:
            raise SystemExit(f"{arguments.output} is stale")
    else:
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_text(rendered, encoding="utf-8")


if __name__ == "__main__":
    main()
