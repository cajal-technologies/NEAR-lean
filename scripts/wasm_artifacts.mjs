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
const SOURCE = path.join(ROOT, "Oracle/contracts/counter.wat");
const BINARY = path.join(ROOT, "Oracle/contracts/counter.wasm");
const DECODED = path.join(ROOT, "Oracle/contracts/counter.compiled.wat");
const MANIFEST = path.join(ROOT, "wasm/manifest.json");
const TALOS_COMMIT = "87336df09b41d819c670be99860481573fd00055";

async function generated() {
  const source = await fs.readFile(SOURCE, "utf8");
  const wabt = await wabtFactory();
  const module = wabt.parseWat("counter.wat", source);
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
    throw new Error(`wasm-tools print failed: ${decoded.stderr}`);
  }
  const version = spawnSync("wasm-tools", ["--version"], { encoding: "utf8" });
  if (version.status !== 0) throw new Error("wasm-tools is required");
  const manifest = {
    binary: "Oracle/contracts/counter.wasm",
    binarySha256: crypto.createHash("sha256").update(binary).digest("hex"),
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
    binary,
    decoded: decoded.stdout,
    manifest: `${JSON.stringify(manifest, null, 2)}\n`
  };
}

async function main() {
  const check = process.argv.slice(2).includes("--check");
  const value = await generated();
  if (check) {
    const current = await Promise.all([
      fs.readFile(BINARY),
      fs.readFile(DECODED, "utf8"),
      fs.readFile(MANIFEST, "utf8")
    ]);
    if (!current[0].equals(value.binary) || current[1] !== value.decoded ||
        current[2] !== value.manifest) {
      throw new Error("WASM artifacts are stale");
    }
    return;
  }
  await fs.mkdir(path.dirname(MANIFEST), { recursive: true });
  await fs.writeFile(BINARY, value.binary);
  await fs.writeFile(DECODED, value.decoded);
  await fs.writeFile(MANIFEST, value.manifest);
}

await main();
