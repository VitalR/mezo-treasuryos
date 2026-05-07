#!/usr/bin/env node

import { readFileSync } from "node:fs";

const MEZO_CHAIN_ID_HEX = "0x7b7b";
const MEZO_CHAIN_ID_DECIMAL = 31611;
const CONFIG_PATH = "config/mezo-testnet.json";

const SELECTORS = {
  balanceOf: "0x70a08231",
  decimals: "0x313ce567",
  factory: "0xc45a0155",
  getReserves: "0x0902f1ac",
  musdToken: "0x9d78d46b",
  name: "0x06fdde03",
  stable: "0x22be3de1",
  symbol: "0x95d89b41",
  token0: "0x0dfe1681",
  token1: "0xd21220a7",
  totalSupply: "0x18160ddd",
  yieldToken: "0x76d5de85",
};

loadDotEnv();

const config = JSON.parse(readFileSync(CONFIG_PATH, "utf8"));
const selected = await selectProvider();

if (!selected) {
  console.error("No configured RPC endpoint returned Mezo testnet chain ID 31611.");
  process.exit(1);
}

const report = {
  rpc: {
    provider: selected.label,
    env: selected.env,
    kind: selected.kind,
    chainId: MEZO_CHAIN_ID_DECIMAL,
    spectrumActive: selected.kind === "spectrum",
    fallbackUsed: selected.kind !== "spectrum",
  },
  savingsVault: await inspectSavingsVault(config.musd.savingsRate.address),
  tigris: {
    router: config.tigris.router,
    poolFactory: config.tigris.poolFactory,
    pools: {
      musdMusdc: await inspectPool("MUSD/mUSDC Basic Stable", config.tigris.pools.musdMusdc.address),
      mcbtcBtc: await inspectPool("mcbBTC/BTC Basic Stable", config.tigris.pools.mcbtcBtc.address),
    },
  },
  recommendations: [
    "MUSD Savings Vault is the primary V1 MUSD operating-capital sleeve.",
    "Tigris MUSD/mUSDC can be a V1 optional sleeve after add/remove-liquidity simulation with live balances.",
    "Tigris mcbBTC/BTC is a real BTC-correlated pool, but execution should wait for BTC-denominated policy and accounting.",
  ],
};

console.log(JSON.stringify(report, null, 2));

async function inspectSavingsVault(address) {
  const [name, symbol, decimals, musdToken, yieldToken, totalSupply] = await Promise.all([
    readString(address, SELECTORS.name),
    readString(address, SELECTORS.symbol),
    readUint(address, SELECTORS.decimals),
    readAddress(address, SELECTORS.musdToken),
    readAddress(address, SELECTORS.yieldToken),
    readUint(address, SELECTORS.totalSupply),
  ]);

  const expectedMUSD = normalizeAddress(config.musd.token);
  const compatible = normalizeAddress(musdToken) === expectedMUSD && normalizeAddress(yieldToken) === expectedMUSD;

  return {
    address,
    name,
    symbol,
    decimals: numberOrString(decimals),
    musdToken,
    yieldToken,
    totalSupply: totalSupply.toString(),
    compatible,
    notes: compatible
      ? "Vault ABI matches TreasuryOS MUSDSavingsRateHandler: deposit, withdraw, claimYield, ERC20 receipt balance."
      : "Vault token metadata does not match the configured MUSD token; do not route demo funds until resolved.",
  };
}

async function inspectPool(label, address) {
  const [symbol, stable, factory, token0, token1, reserves, totalSupply] = await Promise.all([
    readString(address, SELECTORS.symbol),
    readBool(address, SELECTORS.stable),
    readAddress(address, SELECTORS.factory),
    readAddress(address, SELECTORS.token0),
    readAddress(address, SELECTORS.token1),
    readWords(address, SELECTORS.getReserves, 3),
    readUint(address, SELECTORS.totalSupply),
  ]);

  const [token0Metadata, token1Metadata] = await Promise.all([inspectToken(token0), inspectToken(token1)]);
  const configuredFactory = normalizeAddress(config.tigris.poolFactory);
  const isMUSD = normalizeAddress(token0) === normalizeAddress(config.musd.token)
    || normalizeAddress(token1) === normalizeAddress(config.musd.token);
  const isBTCCorrelated = [token0Metadata.symbol, token1Metadata.symbol].some((value) => /btc/i.test(value ?? ""));
  const reserve0Formatted = formatUnits(reserves[0], token0Metadata.decimals);
  const reserve1Formatted = formatUnits(reserves[1], token1Metadata.decimals);
  const liquidityWarning = lowReserve(reserves[0], token0Metadata.decimals) || lowReserve(reserves[1], token1Metadata.decimals)
    ? "One side of this pool currently has less than one whole token unit; transaction-test before demo allocation."
    : null;

  return {
    label,
    address,
    symbol,
    stable,
    factory,
    factoryMatchesConfig: normalizeAddress(factory) === configuredFactory,
    token0: token0Metadata,
    token1: token1Metadata,
    reserve0: reserves[0].toString(),
    reserve1: reserves[1].toString(),
    reserve0Formatted,
    reserve1Formatted,
    blockTimestampLast: reserves[2].toString(),
    totalSupply: totalSupply.toString(),
    compatibleWithMUSDHandler: isMUSD && stable && normalizeAddress(factory) === configuredFactory,
    executionRecommendation: isBTCCorrelated && !isMUSD ? "btc_policy_required" : "v1_musd_sleeve_candidate",
    liquidityWarning,
  };
}

async function inspectToken(address) {
  const [symbol, decimals] = await Promise.all([
    readString(address, SELECTORS.symbol),
    readUint(address, SELECTORS.decimals),
  ]);

  return {
    address,
    symbol,
    decimals: numberOrString(decimals),
  };
}

async function selectProvider() {
  const providers = [
    provider("Spectrum 1", "SPECTRUM_MEZO_RPC_URL_1", "spectrum"),
    provider("Spectrum 2", "SPECTRUM_MEZO_RPC_URL_2", "spectrum"),
    provider("Spectrum 3", "SPECTRUM_MEZO_RPC_URL_3", "spectrum"),
    provider("Spectrum legacy", "SPECTRUM_MEZO_RPC_URL", "spectrum"),
    provider("Mezo official fallback", "MEZO_RPC_URL", "official"),
  ];

  for (const candidate of providers) {
    if (!candidate.configured) continue;

    try {
      const response = await jsonRpc(candidate.url, "eth_chainId", []);
      const chainId = typeof response.result === "string" ? response.result.toLowerCase() : "";
      if (chainId === MEZO_CHAIN_ID_HEX) return candidate;
    } catch {
      // Keep probing; detailed RPC diagnostics belong in rpc-health.mjs.
    }
  }

  return null;
}

function provider(label, env, kind) {
  const url = process.env[env] ?? "";
  return {
    label,
    env,
    kind,
    configured: url.trim().length > 0,
    url,
  };
}

async function readString(to, selector) {
  const data = await ethCall(to, selector);
  return decodeString(data);
}

async function readBool(to, selector) {
  const words = await readWords(to, selector, 1);
  return words[0] !== 0n;
}

async function readUint(to, selector) {
  const words = await readWords(to, selector, 1);
  return words[0];
}

async function readAddress(to, selector) {
  const data = await ethCall(to, selector);
  if (data.length < 66) return null;
  return checksumlessAddress(`0x${data.slice(26, 66)}`);
}

async function readWords(to, selector, count) {
  const data = await ethCall(to, selector);
  const body = strip0x(data);
  const words = [];

  for (let index = 0; index < count; index += 1) {
    const word = body.slice(index * 64, (index + 1) * 64);
    words.push(word ? BigInt(`0x${word}`) : 0n);
  }

  return words;
}

async function ethCall(to, data) {
  const response = await jsonRpc(selected.url, "eth_call", [{ to, data }, "latest"]);
  if (typeof response.result !== "string") {
    throw new Error(`Invalid eth_call result for ${to}`);
  }
  return response.result;
}

async function jsonRpc(url, method, params) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), Number(process.env.RPC_TIMEOUT_MS ?? 10_000));

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
      signal: controller.signal,
    });
    const body = await response.json();
    if (!response.ok || body.error) {
      throw new Error(body.error?.message ?? `HTTP ${response.status}`);
    }
    return body;
  } finally {
    clearTimeout(timeout);
  }
}

function decodeString(data) {
  const body = strip0x(data);
  if (!body) return null;

  if (body.length === 64) {
    return hexToUtf8(body);
  }

  const offset = Number(BigInt(`0x${body.slice(0, 64)}`));
  const lengthStart = offset * 2;
  const length = Number(BigInt(`0x${body.slice(lengthStart, lengthStart + 64)}`));
  const valueStart = lengthStart + 64;
  return hexToUtf8(body.slice(valueStart, valueStart + length * 2));
}

function hexToUtf8(hex) {
  const bytes = Buffer.from(hex.replace(/00+$/u, ""), "hex");
  return bytes.toString("utf8");
}

function normalizeAddress(value) {
  return checksumlessAddress(value);
}

function checksumlessAddress(value) {
  if (!value) return null;
  return `0x${strip0x(value).padStart(40, "0").slice(-40).toLowerCase()}`;
}

function strip0x(value) {
  return String(value ?? "").replace(/^0x/u, "");
}

function numberOrString(value) {
  return value <= BigInt(Number.MAX_SAFE_INTEGER) ? Number(value) : value.toString();
}

function lowReserve(value, decimals) {
  const scale = 10n ** BigInt(Number(decimals));
  return value < scale;
}

function formatUnits(value, decimals) {
  const scale = 10n ** BigInt(Number(decimals));
  const whole = value / scale;
  const fraction = value % scale;
  const fractionText = fraction.toString().padStart(Number(decimals), "0").replace(/0+$/u, "");

  return fractionText ? `${whole.toString()}.${fractionText}` : whole.toString();
}

function loadDotEnv() {
  try {
    const text = readFileSync(".env", "utf8");
    for (const line of text.split(/\r?\n/u)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;

      const match = trimmed.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/u);
      if (!match) continue;

      const [, key, rawValue] = match;
      if (process.env[key] != null) continue;

      process.env[key] = rawValue.trim().replace(/^['"]|['"]$/gu, "");
    }
  } catch {
    // A missing .env is acceptable for CI and documentation checks.
  }
}
