#!/usr/bin/env node

import { readFileSync, writeFileSync } from "node:fs";

const MEZO_TESTNET_CHAIN_ID_HEX = "0x7b7b";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

const SELECTORS = {
  allocationCap: "0xe26e4b48",
  allocationRouter: "0xa4addd3b",
  balanceOf: "0x70a08231",
  collateralRatioBps: "0x593855a0",
  destinationAllocations: "0x9ad8adac",
  getAccountPolicy: "0x91854354",
  getTreasuryHealthState: "0x9721d308",
  handlers: "0x1a21c0bc",
  idleBTC: "0xbe61d10e",
  idleMUSD: "0x9307f3ab",
  isDestinationApproved: "0xeffac8e3",
  policyEngine: "0x927399a5",
  positionCloseDebt: "0x1c18e86b",
  positionCollateral: "0xe380420d",
  positionTotalDebt: "0x894dbd77",
  previewAllocation: "0xfc196068",
};

const DECISION_CODES = [
  "Allowed",
  "Paused",
  "ZeroAmount",
  "InvalidDestination",
  "NotApprovedDestination",
  "UnauthorizedActor",
  "ApprovalRequired",
  "InsufficientIdleBalance",
  "LiquidityBufferBreached",
  "AllocationCapExceeded",
];

loadDotEnv();

process.on("unhandledRejection", handleFatalError);
process.on("uncaughtException", handleFatalError);

const args = parseArgs(process.argv.slice(2));

if (args.help) {
  printHelp();
  process.exit(0);
}

const rpc = await selectRpc();

if (!args.treasuryAccount && !args.manifest) {
  const blockNumber = await rpcRequest(rpc.url, "eth_blockNumber", []);
  emitResult({
    mode: "probe",
    rpc: publicRpcInfo(rpc, blockNumber),
    message:
      "RPC probe succeeded. Provide --manifest or --treasury-account to build a live TreasuryOS state snapshot.",
  });
  process.exit(0);
}

const manifest = args.manifest ? readJson(args.manifest) : {};
const treasuryAccount = normalizeAddress(
  args.treasuryAccount ?? valueAt(manifest, ["contracts", "treasuryAccount"]),
  "treasury account",
);

const actor = normalizeAddress(
  args.actor ?? valueAt(manifest, ["actors", "treasuryOperator"]),
  "actor",
  { allowZero: true },
);

const destinations = loadDestinations(args, manifest);
const fallbackDestination = destinations[0]?.address ?? ZERO_ADDRESS;
const proposedDestination = normalizeAddress(args.proposedDestination ?? fallbackDestination, "proposed destination", {
  allowZero: true,
});

const policyEngine = await readAddress(rpc.url, treasuryAccount, SELECTORS.policyEngine);
const allocationRouter = await readAddress(rpc.url, treasuryAccount, SELECTORS.allocationRouter).catch(() => ZERO_ADDRESS);
const policy = await readPolicy(rpc.url, policyEngine, treasuryAccount);
const idleMUSDWei = await readUint(rpc.url, treasuryAccount, SELECTORS.idleMUSD);
const idleBTCWei = await readUint(rpc.url, treasuryAccount, SELECTORS.idleBTC);
const health = await readHealth(rpc.url, treasuryAccount).catch(() => null);
const position = await readPosition(rpc.url, treasuryAccount);
const sleeves = await readSleeves(rpc.url, treasuryAccount, policyEngine, allocationRouter, destinations);

const deployableSurplusWei = idleMUSDWei > policy.liquidityBuffer ? idleMUSDWei - policy.liquidityBuffer : 0n;
const proposedAmountWei =
  args.proposedAmountWei != null
    ? BigInt(args.proposedAmountWei)
    : args.proposedAmountMusd != null
      ? parseUnits(args.proposedAmountMusd, 18)
      : defaultProposedAmount(deployableSurplusWei, proposedDestination, sleeves);

const allocationDecision =
  actor !== ZERO_ADDRESS && proposedDestination !== ZERO_ADDRESS
    ? await readAllocationDecision(rpc.url, treasuryAccount, actor, proposedDestination, proposedAmountWei)
    : null;

const blockNumber = await rpcRequest(rpc.url, "eth_blockNumber", []);
const snapshot = {
  treasuryName: args.name ?? valueAt(manifest, ["treasuryName"]) ?? "Mezo TreasuryOS Live Treasury",
  rpc: publicRpcInfo(rpc, blockNumber),
  treasuryAccount,
  composition: {
    idleMUSD: formatUnits(idleMUSDWei, 18),
    idleBTC: formatUnits(idleBTCWei, 18),
    liquidityBufferMUSD: formatUnits(policy.liquidityBuffer, 18),
    deployableSurplusMUSD: formatUnits(deployableSurplusWei, 18),
    approvalThresholdMUSD: formatUnits(policy.approvalThreshold, 18),
  },
  position: {
    collateralBTC: formatUnits(position.collateral, 18),
    totalDebtMUSD: formatUnits(position.totalDebt, 18),
    closeDebtMUSD: formatUnits(position.closeDebt, 18),
  },
  health: health ?? {
    collateralRatioBps: "0",
    belowWarningRatio: false,
    belowCriticalRatio: false,
    riskDataAvailable: false,
  },
  sleeves,
  allocationDecision,
};

emitResult(snapshot);

function emitResult(value) {
  const json = `${JSON.stringify(value, null, 2)}\n`;
  if (args.out) {
    writeFileSync(args.out, json);
    console.error(`Wrote Spectrum-backed snapshot to ${args.out}`);
    return;
  }

  process.stdout.write(json);
}

async function selectRpc() {
  const candidates = [
    { provider: "Spectrum Nodes", env: "SPECTRUM_MEZO_RPC_URL_1", url: process.env.SPECTRUM_MEZO_RPC_URL_1 },
    { provider: "Spectrum Nodes", env: "SPECTRUM_MEZO_RPC_URL_2", url: process.env.SPECTRUM_MEZO_RPC_URL_2 },
    { provider: "Spectrum Nodes", env: "SPECTRUM_MEZO_RPC_URL_3", url: process.env.SPECTRUM_MEZO_RPC_URL_3 },
    { provider: "Spectrum Nodes", env: "SPECTRUM_MEZO_RPC_URL", url: process.env.SPECTRUM_MEZO_RPC_URL },
    { provider: "Mezo Official RPC", env: "MEZO_RPC_URL", url: process.env.MEZO_RPC_URL },
  ].filter((candidate) => candidate.url);

  if (candidates.length === 0) {
    throw new Error("Missing Spectrum candidate RPC env vars or MEZO_RPC_URL");
  }

  const attempts = [];

  for (const candidate of candidates) {
    try {
      const chainId = await rpcRequest(candidate.url, "eth_chainId", []);
      const ok = chainId.toLowerCase() === MEZO_TESTNET_CHAIN_ID_HEX;
      attempts.push({
        provider: candidate.provider,
        env: candidate.env,
        status: ok ? "selected" : "wrong_chain",
        chainId,
      });

      if (ok) {
        return { ...candidate, chainId, attempts };
      }
    } catch (error) {
      attempts.push({
        provider: candidate.provider,
        env: candidate.env,
        status: "failed",
        error: error.message,
      });
    }
  }

  const error = new Error(`No configured RPC returned Mezo testnet chain ID ${MEZO_TESTNET_CHAIN_ID_HEX}`);
  error.attempts = attempts;
  throw error;
}

function publicRpcInfo(rpc, blockNumber) {
  return {
    provider: rpc.provider,
    env: rpc.env,
    chainId: Number(BigInt(rpc.chainId)),
    chainIdHex: rpc.chainId,
    blockNumber: Number(BigInt(blockNumber)),
    spectrumActive: rpc.env.startsWith("SPECTRUM_MEZO_RPC_URL"),
    fallbackUsed: !rpc.env.startsWith("SPECTRUM_MEZO_RPC_URL"),
    attempts: rpc.attempts,
  };
}

async function rpcRequest(url, method, params) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), Number(process.env.RPC_TIMEOUT_MS ?? 10_000));

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
      signal: controller.signal,
    });

    if (!response.ok) {
      throw new Error(`${method} HTTP ${response.status}`);
    }

    const json = await response.json();
    if (json.error) {
      throw new Error(`${method} RPC error ${json.error.code}: ${json.error.message}`);
    }

    return json.result;
  } finally {
    clearTimeout(timeout);
  }
}

async function ethCall(url, to, data) {
  return rpcRequest(url, "eth_call", [{ to, data }, "latest"]);
}

async function readUint(url, to, selector, encodedArgs = "") {
  const data = await ethCall(url, to, `${selector}${strip0x(encodedArgs)}`);
  return wordToUint(data, 0);
}

async function readAddress(url, to, selector, encodedArgs = "") {
  const data = await ethCall(url, to, `${selector}${strip0x(encodedArgs)}`);
  return wordToAddress(data, 0);
}

async function readBool(url, to, selector, encodedArgs = "") {
  const data = await ethCall(url, to, `${selector}${strip0x(encodedArgs)}`);
  return wordToBool(data, 0);
}

async function readPolicy(url, policyEngine, account) {
  const data = await ethCall(url, policyEngine, encodeCall(SELECTORS.getAccountPolicy, [addressArg(account)]));

  return {
    treasuryAdmin: wordToAddress(data, 0),
    operator: wordToAddress(data, 1),
    approver: wordToAddress(data, 2),
    liquidityBuffer: wordToUint(data, 3),
    approvalThreshold: wordToUint(data, 4),
    automationEnabled: wordToBool(data, 5),
    paused: wordToBool(data, 6),
    initialized: wordToBool(data, 7),
  };
}

async function readHealth(url, treasuryAccount) {
  const data = await ethCall(url, treasuryAccount, SELECTORS.getTreasuryHealthState);

  return {
    collateralRatioBps: wordToUint(data, 8).toString(),
    warningCollateralRatioBps: wordToUint(data, 9).toString(),
    criticalCollateralRatioBps: wordToUint(data, 10).toString(),
    belowWarningRatio: wordToBool(data, 13),
    belowCriticalRatio: wordToBool(data, 14),
    riskDataAvailable: wordToBool(data, 15),
    automationEnabled: wordToBool(data, 16),
    paused: wordToBool(data, 17),
  };
}

async function readPosition(url, treasuryAccount) {
  const [totalDebt, collateral, closeDebt] = await Promise.all([
    readUint(url, treasuryAccount, SELECTORS.positionTotalDebt).catch(() => 0n),
    readUint(url, treasuryAccount, SELECTORS.positionCollateral).catch(() => 0n),
    readUint(url, treasuryAccount, SELECTORS.positionCloseDebt).catch(() => 0n),
  ]);

  return { totalDebt, collateral, closeDebt };
}

async function readSleeves(url, treasuryAccount, policyEngine, allocationRouter, destinations) {
  const sleeves = [];

  for (const destination of destinations) {
    const encodedAccountDestination = `${addressArg(treasuryAccount)}${addressArg(destination.address)}`;
    const encodedDestination = addressArg(destination.address);

    const [allocated, cap, approved, receiptBalance, handler] = await Promise.all([
      readUint(url, treasuryAccount, SELECTORS.destinationAllocations, encodedDestination).catch(() => 0n),
      readUint(url, policyEngine, SELECTORS.allocationCap, encodedAccountDestination).catch(() => 0n),
      readBool(url, policyEngine, SELECTORS.isDestinationApproved, encodedAccountDestination).catch(() => false),
      readUint(url, destination.address, SELECTORS.balanceOf, addressArg(treasuryAccount)).catch(() => 0n),
      allocationRouter !== ZERO_ADDRESS
        ? readAddress(url, allocationRouter, SELECTORS.handlers, encodedDestination).catch(() => ZERO_ADDRESS)
        : ZERO_ADDRESS,
    ]);

    sleeves.push({
      label: destination.label,
      destination: destination.address,
      handler,
      approved,
      allocatedMUSD: formatUnits(allocated, 18),
      capMUSD: formatUnits(cap, 18),
      remainingCapacityMUSD: formatUnits(cap > allocated ? cap - allocated : 0n, 18),
      receiptBalance: formatUnits(receiptBalance, 18),
    });
  }

  return sleeves;
}

async function readAllocationDecision(url, treasuryAccount, actor, destination, amountWei) {
  const data = await ethCall(
    url,
    treasuryAccount,
    encodeCall(SELECTORS.previewAllocation, [addressArg(actor), addressArg(destination), uintArg(amountWei)]),
  );
  const code = Number(wordToUint(data, 1));

  return {
    allowed: wordToBool(data, 0),
    code: DECISION_CODES[code] ?? `Unknown(${code})`,
    actor: wordToAddress(data, 2),
    destination: wordToAddress(data, 3),
    amountMUSD: formatUnits(wordToUint(data, 4), 18),
    idleMUSD: formatUnits(wordToUint(data, 5), 18),
    liquidityBufferMUSD: formatUnits(wordToUint(data, 6), 18),
    deployableSurplusMUSD: formatUnits(wordToUint(data, 7), 18),
    approvalThresholdMUSD: formatUnits(wordToUint(data, 8), 18),
    currentAllocationMUSD: formatUnits(wordToUint(data, 9), 18),
    allocationCapMUSD: formatUnits(wordToUint(data, 10), 18),
    remainingCapacityMUSD: formatUnits(wordToUint(data, 11), 18),
    nextIdleMUSD: formatUnits(wordToUint(data, 12), 18),
    nextAllocationMUSD: formatUnits(wordToUint(data, 13), 18),
  };
}

function defaultProposedAmount(deployableSurplusWei, proposedDestination, sleeves) {
  const sleeve = sleeves.find((candidate) => candidate.destination.toLowerCase() === proposedDestination.toLowerCase());
  if (!sleeve) return deployableSurplusWei;

  const remaining = parseUnits(sleeve.remainingCapacityMUSD, 18);
  return deployableSurplusWei < remaining ? deployableSurplusWei : remaining;
}

function loadDestinations(parsedArgs, manifest) {
  if (parsedArgs.destinations) {
    return parsedArgs.destinations
      .split(",")
      .map((address, index) => ({ address: normalizeAddress(address, "destination"), label: `Sleeve ${index + 1}` }));
  }

  const destinations = [];
  const savings = valueAt(manifest, ["references", "savingsDestination"]) ??
    valueAt(manifest, ["references", "musd", "savingsRate", "address"]);
  const tigris = valueAt(manifest, ["references", "tigrisMusdMusdcPool"]) ??
    valueAt(manifest, ["references", "tigris", "musdMusdcPool"]);

  if (savings && savings !== ZERO_ADDRESS) {
    destinations.push({ address: normalizeAddress(savings, "savings destination"), label: "MUSD Savings Vault" });
  }

  if (tigris && tigris !== ZERO_ADDRESS) {
    destinations.push({ address: normalizeAddress(tigris, "Tigris destination"), label: "Tigris Basic Stable MUSD/mUSDC" });
  }

  return destinations;
}

function encodeCall(selector, args = []) {
  return `${selector}${args.join("")}`;
}

function addressArg(address) {
  return strip0x(address).padStart(64, "0").toLowerCase();
}

function uintArg(value) {
  return BigInt(value).toString(16).padStart(64, "0");
}

function wordToUint(data, index) {
  const word = wordAt(data, index);
  return BigInt(`0x${word}`);
}

function wordToBool(data, index) {
  return wordToUint(data, index) !== 0n;
}

function wordToAddress(data, index) {
  return `0x${wordAt(data, index).slice(24)}`;
}

function wordAt(data, index) {
  const hex = strip0x(data);
  const start = index * 64;
  const word = hex.slice(start, start + 64);

  if (word.length !== 64) {
    throw new Error(`ABI word ${index} missing from ${data}`);
  }

  return word;
}

function strip0x(value) {
  return String(value).startsWith("0x") ? String(value).slice(2) : String(value);
}

function normalizeAddress(value, label, options = {}) {
  if (!value || value === ZERO_ADDRESS) {
    if (options.allowZero) return ZERO_ADDRESS;
    throw new Error(`Missing ${label}`);
  }

  const address = String(value).trim();
  if (!/^0x[0-9a-fA-F]{40}$/.test(address)) {
    throw new Error(`Invalid ${label}: ${address}`);
  }

  return address;
}

function parseUnits(value, decimals) {
  const raw = String(value);
  const [whole, fraction = ""] = raw.split(".");
  const paddedFraction = fraction.padEnd(decimals, "0").slice(0, decimals);
  return BigInt(whole || "0") * 10n ** BigInt(decimals) + BigInt(paddedFraction || "0");
}

function formatUnits(value, decimals) {
  const base = 10n ** BigInt(decimals);
  const whole = value / base;
  const fraction = value % base;
  if (fraction === 0n) return whole.toString();

  const fractionText = fraction.toString().padStart(decimals, "0").replace(/0+$/, "");
  return `${whole}.${fractionText}`;
}

function parseArgs(argv) {
  const parsed = {};

  for (let index = 0; index < argv.length; index++) {
    const token = argv[index];
    if (!token.startsWith("--")) continue;

    const key = token.slice(2).replace(/-([a-z])/g, (_, char) => char.toUpperCase());
    if (key === "help") {
      parsed.help = true;
      continue;
    }

    parsed[key] = argv[index + 1];
    index++;
  }

  return parsed;
}

function readJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function valueAt(object, path) {
  let current = object;
  for (const key of path) {
    if (current == null || typeof current !== "object") return undefined;
    current = current[key];
  }
  return current;
}

function loadDotEnv() {
  try {
    const text = readFileSync(".env", "utf8");
    for (const line of text.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;

      const match = trimmed.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
      if (!match) continue;

      const [, key, rawValue] = match;
      if (process.env[key] != null) continue;

      process.env[key] = rawValue.trim().replace(/^['"]|['"]$/g, "");
    }
  } catch {
    // A missing .env is fine for CI and sample rendering.
  }
}

function printHelp() {
  console.log(`Usage:
  node services/spectrum-state/snapshot.mjs
  node services/spectrum-state/snapshot.mjs --manifest deployments/mezo-testnet-client.json --out /tmp/treasuryos-snapshot.json
  node services/spectrum-state/snapshot.mjs --treasury-account 0x... --destinations 0x...,0x... --actor 0x...

RPC selection:
  1. SPECTRUM_MEZO_RPC_URL_1, if it returns Mezo testnet chain ID 31611
  2. SPECTRUM_MEZO_RPC_URL_2
  3. SPECTRUM_MEZO_RPC_URL_3
  4. SPECTRUM_MEZO_RPC_URL
  5. MEZO_RPC_URL fallback
`);
}

function handleFatalError(error) {
  console.error(error?.message ?? String(error));
  if (error?.attempts) {
    console.error(JSON.stringify({ attempts: error.attempts }, null, 2));
  }
  process.exit(1);
}
