#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(new URL("../Oracle/package.json", import.meta.url));
const wabtFactory = require("wabt");

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MANIFEST = path.join(ROOT, "wasm/manifest.json");
const TALOS_COMMIT = "87336df09b41d819c670be99860481573fd00055";
const CONTRACTS = ["counter", "escrow", "fungible_token", "nft", "async"];

async function generated() {
  const wabt = await wabtFactory();
  const artifacts = [];
  for (const name of CONTRACTS) {
    const source = await fs.readFile(path.join(ROOT, `Oracle/contracts/${name}.wat`), "utf8");
    const module = wabt.parseWat(`${name}.wat`, source);
    let binary;
    try {
      module.validate();
      binary = Buffer.from(module.toBinary({ write_debug_names: false }).buffer);
    } finally {
      module.destroy();
    }
    const decoded = spawnSync("wasm-tools", ["print", "-"], {
      input: binary,
      encoding: "utf8"
    });
    if (decoded.status !== 0) {
      throw new Error(`wasm-tools print failed for ${name}: ${decoded.stderr}`);
    }
    artifacts.push({
      name,
      binary,
      decoded: decoded.stdout,
      binaryPath: path.join(ROOT, `Oracle/contracts/${name}.wasm`),
      decodedPath: path.join(ROOT, `Oracle/contracts/${name}.compiled.wat`)
    });
  }
  const version = spawnSync("wasm-tools", ["--version"], { encoding: "utf8" });
  if (version.status !== 0) throw new Error("wasm-tools is required");
  const manifest = {
    binary: "Oracle/contracts/counter.wasm",
    binarySha256: crypto.createHash("sha256").update(artifacts[0].binary).digest("hex"),
    benchmarks: artifacts.map((artifact) => ({
      binary: `Oracle/contracts/${artifact.name}.wasm`,
      binarySha256: crypto.createHash("sha256").update(artifact.binary).digest("hex"),
      compiledWat: `Oracle/contracts/${artifact.name}.compiled.wat`,
      name: artifact.name
    })),
    decoder: "wasm-tools print followed by Talos WAT decoding",
    execution: "Talos deterministic small-step interpreter",
    instructionFamilies: [
      "call",
      "call_indirect",
      "drop",
      "i32.add",
      "i32.const",
      "i32.store8",
      "i32.wrap_i64",
      "i64.add",
      "i64.const",
      "global.get",
      "local.get",
      "local.set",
      "unreachable"
    ],
    moduleFeatures: [
      "calls",
      "data",
      "exports",
      "function-imports",
      "globals",
      "memory",
      "tables",
      "traps"
    ],
    schemaVersion: 1,
    talosCommit: TALOS_COMMIT,
    wasmTools: version.stdout.trim(),
    wasmVersion: "WebAssembly Core 1.0 (MVP)"
  };
  return {
    artifacts,
    manifest: `${JSON.stringify(manifest, null, 2)}\n`
  };
}

async function main() {
  const check = process.argv.slice(2).includes("--check");
  const value = await generated();
  if (check) {
    const current = await Promise.all(value.artifacts.flatMap((artifact) => [
      fs.readFile(artifact.binaryPath), fs.readFile(artifact.decodedPath, "utf8")
    ]));
    const stale = value.artifacts.some((artifact, index) =>
      !current[index * 2].equals(artifact.binary) || current[index * 2 + 1] !== artifact.decoded
    );
    if (stale || await fs.readFile(MANIFEST, "utf8") !== value.manifest) {
      throw new Error("WASM artifacts are stale");
    }
    return;
  }
  await fs.mkdir(path.dirname(MANIFEST), { recursive: true });
  for (const artifact of value.artifacts) {
    await fs.writeFile(artifact.binaryPath, artifact.binary);
    await fs.writeFile(artifact.decodedPath, artifact.decoded);
  }
  await fs.writeFile(MANIFEST, value.manifest);
}

await main();
