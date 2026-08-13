#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Account, JsonRpcProvider } from "near-api-js";
import {
  DEFAULT_PRIVATE_KEY,
  DEFAULT_PUBLIC_KEY,
  GenesisAccount,
  Sandbox
} from "near-sandbox";
import wabtFactory from "wabt";

const PINNED_RELEASE = "2.13.3";
const PINNED_COMMIT = "5af9ca74631e6cf0dae33e77d1a632e94d2952ce";
const PROTOCOL_VERSION = 86;
const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));

function bytes(value) {
  return [...Buffer.from(value, "utf8")];
}

function assertBaseline(trace) {
  if (trace.schemaVersion !== 1) {
    throw new Error(`unsupported trace schema ${trace.schemaVersion}`);
  }
  if (trace.nearcoreRelease !== PINNED_RELEASE || trace.nearcoreCommit !== PINNED_COMMIT) {
    throw new Error("trace nearcore baseline does not match the pinned oracle");
  }
  if (trace.protocolVersion !== PROTOCOL_VERSION) {
    throw new Error("trace protocol version does not match the pinned oracle");
  }
}

async function compileContract(name) {
  if (name !== "counter") {
    throw new Error(`unsupported oracle contract \`${name}\``);
  }
  const source = await fs.readFile(path.join(SCRIPT_DIR, "contracts", `${name}.wat`), "utf8");
  const wabt = await wabtFactory();
  const module = wabt.parseWat(`${name}.wat`, source);
  try {
    module.validate();
    return new Uint8Array(module.toBinary({ write_debug_names: false }).buffer);
  } finally {
    module.destroy();
  }
}

function finalBytes(outcome) {
  const status = outcome?.status;
  if (status && typeof status === "object" && "SuccessValue" in status) {
    return [...Buffer.from(status.SuccessValue, "base64")];
  }
  return [];
}

function logs(outcome) {
  const outcomes = [outcome?.transaction_outcome, ...(outcome?.receipts_outcome ?? [])];
  return outcomes.flatMap((entry) =>
    (entry?.outcome?.logs ?? []).map((line) => bytes(line))
  );
}

function tokensBurnt(outcome) {
  const outcomes = [outcome?.transaction_outcome, ...(outcome?.receipts_outcome ?? [])];
  return outcomes.reduce(
    (total, entry) => total + BigInt(entry?.outcome?.tokens_burnt ?? "0"),
    0n
  );
}

function errorText(error) {
  const seen = new WeakSet();
  const serialized = JSON.stringify(error, (_key, value) => {
    if (typeof value === "bigint") return value.toString();
    if (value && typeof value === "object") {
      if (seen.has(value)) return undefined;
      seen.add(value);
    }
    return value;
  });
  return `${String(error)} ${serialized ?? ""}`;
}

function errorCategory(error) {
  const text = errorText(error);
  if (/AccountAlreadyExists|account.*already exists/i.test(text)) return "accountAlreadyExists";
  if (/AccountDoesNotExist|UnknownAccount|does not exist/i.test(text)) return "accountNotFound";
  if (/NotEnoughBalance|not enough balance|insufficient balance/i.test(text)) return "insufficientBalance";
  if (/MethodResolveError|MethodNotFound|method.*not found/i.test(text)) return "methodNotFound";
  if (/InvalidAccountId|invalid account/i.test(text)) return "invalidAccountId";
  if (/FunctionCallError|wasm trap|Smart contract panicked/i.test(text)) return "contractFailure";
  return "nearcoreError";
}

function account(id, rpcUrl) {
  return new Account(id, rpcUrl, DEFAULT_PRIVATE_KEY);
}

async function finalized(outcome, provider, signerId) {
  if (!outcome?.transaction?.hash) return outcome;
  return provider.viewTransactionStatus({
    txHash: outcome.transaction.hash,
    accountId: signerId,
    waitUntil: "FINAL"
  });
}

function creditFees(feeCredits, signerId, outcome) {
  feeCredits.set(signerId, (feeCredits.get(signerId) ?? 0n) + tokensBurnt(outcome));
}

async function snapshotAccount(id, provider, contracts, feeCredits) {
  try {
    const [state, contractState] = await Promise.all([
      provider.viewAccount({
        accountId: id,
        blockQuery: { finality: "final" }
      }),
      provider.viewContractState({
        contractId: id,
        prefix: "",
        blockQuery: { finality: "final" }
      })
    ]);
    return {
      id,
      present: true,
      balance: (state.amount + (feeCredits.get(id) ?? 0n)).toString(),
      storage: contractState.values.map((entry) => ({
        key: [...Buffer.from(entry.key, "base64")],
        value: [...Buffer.from(entry.value, "base64")]
      })),
      contract: contracts.get(id) ?? null
    };
  } catch (error) {
    if (errorCategory(error) !== "accountNotFound") throw error;
    return {
      id,
      present: false,
      balance: null,
      storage: [],
      contract: null
    };
  }
}

async function snapshot(trace, provider, contracts, feeCredits) {
  return Promise.all(
    trace.observeAccounts.map((id) => snapshotAccount(id, provider, contracts, feeCredits))
  );
}

async function executeAction(action, rpcUrl, provider, contracts, feeCredits) {
  switch (action.kind) {
    case "createAccount": {
      const outcome = await finalized(await account(action.creator, rpcUrl).createAccount({
        newAccountId: action.accountId,
        publicKey: DEFAULT_PUBLIC_KEY,
        nearToTransfer: BigInt(action.initialBalance)
      }), provider, action.creator);
      creditFees(feeCredits, action.creator, outcome);
      return outcome;
    }
    case "transfer": {
      const outcome = await finalized(await account(action.sender, rpcUrl).transfer({
        receiverId: action.receiver,
        amount: BigInt(action.amount)
      }), provider, action.sender);
      creditFees(feeCredits, action.sender, outcome);
      return outcome;
    }
    case "deployContract": {
      if (action.deployer !== action.accountId) {
        throw new Error("oracle deployment requires the deploying account to sign for itself");
      }
      const deployed = await finalized(await account(action.accountId, rpcUrl).deployContract(
        await compileContract(action.contract)
      ), provider, action.deployer);
      creditFees(feeCredits, action.deployer, deployed);
      const initialized = await finalized(await account(action.deployer, rpcUrl).callFunctionRaw({
        contractId: action.accountId,
        methodName: "init",
        args: new Uint8Array(),
        gas: 100_000_000_000_000n,
        deposit: 0n,
        waitUntil: "FINAL"
      }), provider, action.deployer);
      creditFees(feeCredits, action.deployer, initialized);
      contracts.set(action.accountId, action.contract);
      return deployed;
    }
    case "functionCall": {
      const outcome = await finalized(await account(action.caller, rpcUrl).callFunctionRaw({
        contractId: action.receiver,
        methodName: action.method,
        args: new Uint8Array(Buffer.from(action.arguments ?? "", "utf8")),
        gas: BigInt(action.prepaidGas),
        deposit: BigInt(action.attachedDeposit),
        waitUntil: "FINAL"
      }), provider, action.caller);
      creditFees(feeCredits, action.caller, outcome);
      return outcome;
    }
    default:
      throw new Error(`unsupported canonical action \`${action.kind}\``);
  }
}

async function runTrace(trace, rpcUrl) {
  const observations = [];
  const contracts = new Map();
  const feeCredits = new Map();
  const provider = new JsonRpcProvider({ url: rpcUrl });
  for (const [index, action] of trace.actions.entries()) {
    try {
      const outcome = await executeAction(action, rpcUrl, provider, contracts, feeCredits);
      observations.push({
        index,
        success: true,
        errorCategory: null,
        returnValue: finalBytes(outcome),
        logs: logs(outcome),
        accounts: await snapshot(trace, provider, contracts, feeCredits)
      });
    } catch (error) {
      observations.push({
        index,
        success: false,
        errorCategory: errorCategory(error),
        returnValue: [],
        logs: [],
        accounts: await snapshot(trace, provider, contracts, feeCredits)
      });
    }
  }
  return {
    schemaVersion: trace.schemaVersion,
    nearcoreCommit: trace.nearcoreCommit,
    nearcoreRelease: trace.nearcoreRelease,
    protocolVersion: trace.protocolVersion,
    seed: trace.seed,
    observations
  };
}

async function main() {
  const arguments_ = process.argv.slice(2);
  const outputIndex = arguments_.indexOf("--output");
  const outputPath = outputIndex === -1 ? null : arguments_[outputIndex + 1];
  const tracePaths = outputIndex === -1
    ? arguments_
    : arguments_.filter((_value, index) => index !== outputIndex && index !== outputIndex + 1);
  if (tracePaths.length === 0 || (outputIndex !== -1 && !outputPath)) {
    console.error("usage: node Oracle/run.mjs [--output RUNS.json] TRACE.json...");
    process.exitCode = 2;
    return;
  }
  const traces = await Promise.all(
    tracePaths.map(async (tracePath) => JSON.parse(await fs.readFile(tracePath, "utf8")))
  );
  traces.forEach(assertBaseline);
  const genesisEntries = traces.flatMap((trace) => trace.genesis);
  const genesisIds = genesisEntries.map((entry) => entry.id);
  if (new Set(genesisIds).size !== genesisIds.length) {
    throw new Error("batched traces must use disjoint genesis account IDs");
  }
  const genesis = genesisEntries.map((entry) =>
    new GenesisAccount(
      entry.id,
      DEFAULT_PUBLIC_KEY,
      DEFAULT_PRIVATE_KEY,
      BigInt(entry.balance)
    )
  );
  const sandbox = await Sandbox.start({
    version: PINNED_RELEASE,
    config: {
      additionalAccounts: genesis,
      additionalGenesis: {
        min_gas_price: "0"
      }
    }
  });
  try {
    const runs = [];
    for (const trace of traces) runs.push(await runTrace(trace, sandbox.rpcUrl));
    const result = runs.length === 1 ? runs[0] : runs;
    const encoded = `${JSON.stringify(result, null, 2)}\n`;
    if (outputPath) await fs.writeFile(outputPath, encoded, "utf8");
    else process.stdout.write(encoded);
  } finally {
    await sandbox.tearDown();
  }
}

await main();
