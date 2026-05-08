#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { webcrypto } from "node:crypto";

const MEZO_CHAIN_ID_HEX = "0x7b7b";
const MEZO_CHAIN_ID_DECIMAL = 31611;
const CONFIG_PATH = "config/mezo-testnet.json";

const TX_HASHES = {
  swapBtcToMcbtc: "0x5ad4f4ca53d3149b8c30c5003d522b921cce8c03b3ea6cae86c37536f52ada93",
  addLiquidityMcbtcBtc: "0x770ba8577ff0b382a93478ad01cf17214136b1994f095add675b2a140b711135",
  stakeMcbtcBtcLp: "0x3e7fb5fab85ee1afd0dec173f2ec8c6eff1400f25df2dd861bc017d975d49f96",
};

const SELECTORS = {
  balanceOf: "0x70a08231",
  decimals: "0x313ce567",
  factory: "0xc45a0155",
  getReserves: "0x0902f1ac",
  name: "0x06fdde03",
  stable: "0x22be3de1",
  stakingToken: "0x72f702f3",
  symbol: "0x95d89b41",
  token0: "0x0dfe1681",
  token1: "0xd21220a7",
  totalSupply: "0x18160ddd",
  rewardToken: "0xf7c618c1",
  rewardsToken: "0xd1af0c7d",
};

const TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef";
const APPROVAL_TOPIC = "0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925";

const METHOD_SELECTORS = {
  "0xcac88ea9": "swapExactTokensForTokens(uint256,uint256,(address,address,bool,address)[],address,uint256)",
  "0x5a47ddc3": "addLiquidity(address,address,bool,uint256,uint256,uint256,uint256,address,uint256)",
  "0x6e553f65": "deposit(uint256,address)",
};

loadDotEnv();

const config = JSON.parse(readFileSync(CONFIG_PATH, "utf8"));
const selected = await selectProvider();

if (!selected) {
  console.error("No configured RPC endpoint returned Mezo testnet chain ID 31611.");
  process.exit(1);
}

const addresses = {
  btc: config.tigris.tokens.btc,
  mcbtc: config.tigris.tokens.mcbtc,
  pool: config.tigris.pools.mcbtcBtc.address,
  configuredRouter: config.tigris.router,
  poolFactory: config.tigris.poolFactory,
};

const [btc, mcbtc, pool] = await Promise.all([
  inspectToken(addresses.btc),
  inspectToken(addresses.mcbtc),
  inspectPool(addresses.pool),
]);

const [swapTx, addLiquidityTx, stakeTx] = await Promise.all([
  inspectTransaction(TX_HASHES.swapBtcToMcbtc),
  inspectTransaction(TX_HASHES.addLiquidityMcbtcBtc),
  inspectTransaction(TX_HASHES.stakeMcbtcBtcLp),
]);

const uiRouter = addLiquidityTx.to;
const gauge = stakeTx.to;
const [uiRouterCode, configuredRouterCode, gaugeInfo] = await Promise.all([
  codeHashInfo(uiRouter),
  codeHashInfo(addresses.configuredRouter),
  inspectGauge(gauge).catch((error) => ({ address: gauge, error: error.message })),
]);

const report = {
  rpc: {
    provider: selected.label,
    env: selected.env,
    kind: selected.kind,
    chainId: MEZO_CHAIN_ID_DECIMAL,
    spectrumActive: selected.kind === "spectrum",
    fallbackUsed: selected.kind !== "spectrum",
  },
  btcToken: {
    ...btc,
    interpretation:
      "BTCCaller/precompile responds to ERC20 metadata and emits ERC20 Transfer logs in swap/add-liquidity transactions.",
  },
  mcbtcToken: mcbtc,
  pool,
  router: {
    configuredRouter: addresses.configuredRouter,
    uiObservedRouter: uiRouter,
    configuredRouterCodeHash: configuredRouterCode.codeHash,
    uiObservedRouterCodeHash: uiRouterCode.codeHash,
    sameRuntimeCode: configuredRouterCode.codeHash === uiRouterCode.codeHash,
    note:
      uiRouter.toLowerCase() === addresses.configuredRouter.toLowerCase()
        ? "Configured router matches the UI-observed BTC pool router."
        : "UI BTC transactions use a different router address with the same ABI shape; configure BTC sleeve experiments explicitly.",
  },
  gauge: gaugeInfo,
  transactions: {
    swapBtcToMcbtc: swapTx,
    addLiquidityMcbtcBtc: addLiquidityTx,
    stakeMcbtcBtcLp: stakeTx,
  },
  conclusion: {
    erc20StyleBTC:
      addLiquidityTx.value === "0" &&
      addLiquidityTx.transfers.some((transfer) => transfer.token.toLowerCase() === addresses.btc.toLowerCase()),
    addLiquidityUsesMsgValue: addLiquidityTx.value !== "0",
    btcSleeveFeasibility:
      "BTC sleeve blocker can be reduced to guarded execution prerequisites: BTCReservePolicy limits, swap price-impact/slippage bounds, LP min-liquidity checks, receipt/staked-LP accounting, and multisig approval.",
    recommendedScope:
      "Keep V1 final demo on MUSD sleeves. Treat mcbBTC/BTC as V1 experimental preview or V1.5 guarded execution until a tiny broadcast deposit/withdraw/stake/unstake flow is validated through the selected router/gauge.",
  },
};

console.log(JSON.stringify(report, null, 2));

async function inspectPool(address) {
  const [symbol, stable, factory, token0, token1, reserves, totalSupply] = await Promise.all([
    readString(address, SELECTORS.symbol),
    readBool(address, SELECTORS.stable),
    readAddress(address, SELECTORS.factory),
    readAddress(address, SELECTORS.token0),
    readAddress(address, SELECTORS.token1),
    readWords(address, SELECTORS.getReserves, 3),
    readUint(address, SELECTORS.totalSupply),
  ]);
  const [token0Info, token1Info] = await Promise.all([inspectToken(token0), inspectToken(token1)]);

  return {
    address,
    symbol,
    stable,
    factory,
    factoryMatchesConfig: normalizeAddress(factory) === normalizeAddress(addresses.poolFactory),
    token0: token0Info,
    token1: token1Info,
    reserve0: reserves[0].toString(),
    reserve1: reserves[1].toString(),
    reserve0Formatted: formatUnits(reserves[0], token0Info.decimals),
    reserve1Formatted: formatUnits(reserves[1], token1Info.decimals),
    blockTimestampLast: reserves[2].toString(),
    totalSupply: totalSupply.toString(),
    totalSupplyFormatted: formatUnits(totalSupply, 18),
  };
}

async function inspectToken(address) {
  const [name, symbol, decimals, totalSupply] = await Promise.all([
    readString(address, SELECTORS.name).catch(() => null),
    readString(address, SELECTORS.symbol).catch(() => null),
    readUint(address, SELECTORS.decimals),
    readUint(address, SELECTORS.totalSupply).catch(() => null),
  ]);

  return {
    address,
    name,
    symbol,
    decimals: Number(decimals),
    totalSupply: totalSupply?.toString() ?? null,
    totalSupplyFormatted: totalSupply == null ? null : formatUnits(totalSupply, Number(decimals)),
  };
}

async function inspectGauge(address) {
  const [stakingToken, rewardToken, rewardsToken] = await Promise.all([
    readAddress(address, SELECTORS.stakingToken).catch(() => null),
    readAddress(address, SELECTORS.rewardToken).catch(() => null),
    readAddress(address, SELECTORS.rewardsToken).catch(() => null),
  ]);

  const rewardAsset = rewardToken ?? rewardsToken;
  const [stakingTokenInfo, rewardTokenInfo] = await Promise.all([
    stakingToken ? inspectToken(stakingToken) : null,
    rewardAsset ? inspectToken(rewardAsset).catch(() => null) : null,
  ]);

  return {
    address,
    stakingToken,
    stakingTokenInfo,
    rewardToken: rewardAsset,
    rewardTokenInfo,
    supportsDepositForRecipient: true,
  };
}

async function inspectTransaction(hash) {
  const [tx, receipt] = await Promise.all([
    jsonRpc(selected.url, "eth_getTransactionByHash", [hash]),
    jsonRpc(selected.url, "eth_getTransactionReceipt", [hash]),
  ]);
  const result = tx.result;
  const receiptResult = receipt.result;
  const selector = result.input.slice(0, 10);
  const tokenByAddress = new Map([
    [normalizeAddress(addresses.btc), btc],
    [normalizeAddress(addresses.mcbtc), mcbtc],
    [normalizeAddress(addresses.pool), { symbol: "sAMM-mcbBTC/BTC", decimals: 18 }],
  ]);

  return {
    hash,
    to: result.to,
    value: BigInt(result.value).toString(),
    selector,
    method: METHOD_SELECTORS[selector] ?? "unknown",
    status: receiptResult.status === "0x1" ? "success" : "failed",
    transfers: receiptResult.logs
      .filter((log) => log.topics[0] === TRANSFER_TOPIC)
      .map((log) => formatTransfer(log, tokenByAddress)),
    approvals: receiptResult.logs
      .filter((log) => log.topics[0] === APPROVAL_TOPIC)
      .map((log) => formatApproval(log, tokenByAddress)),
  };
}

function formatTransfer(log, tokenByAddress) {
  const token = tokenByAddress.get(normalizeAddress(log.address));
  const amount = BigInt(log.data);

  return {
    token: log.address,
    symbol: token?.symbol ?? null,
    from: wordToAddress(log.topics[1]),
    to: wordToAddress(log.topics[2]),
    amount: amount.toString(),
    amountFormatted: token ? formatUnits(amount, token.decimals) : amount.toString(),
  };
}

function formatApproval(log, tokenByAddress) {
  const token = tokenByAddress.get(normalizeAddress(log.address));
  const amount = BigInt(log.data);

  return {
    token: log.address,
    symbol: token?.symbol ?? null,
    owner: wordToAddress(log.topics[1]),
    spender: wordToAddress(log.topics[2]),
    amount: amount.toString(),
    amountFormatted: token ? formatUnits(amount, token.decimals) : amount.toString(),
  };
}

async function codeHashInfo(address) {
  const response = await jsonRpc(selected.url, "eth_getCode", [address, "latest"]);
  const code = response.result ?? "0x";
  return {
    address,
    codeBytes: Math.max(0, (code.length - 2) / 2),
    codeHash: await sha256Hex(code),
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

function wordToAddress(word) {
  return checksumlessAddress(`0x${strip0x(word).slice(24)}`);
}

function strip0x(value) {
  return String(value).startsWith("0x") ? String(value).slice(2) : String(value);
}

function checksumlessAddress(address) {
  return `0x${strip0x(address).padStart(40, "0").toLowerCase().slice(-40)}`;
}

function normalizeAddress(address) {
  return checksumlessAddress(address);
}

function formatUnits(value, decimals) {
  const bigint = BigInt(value);
  const base = 10n ** BigInt(decimals);
  const whole = bigint / base;
  const fraction = bigint % base;
  if (fraction === 0n) return whole.toString();

  const fractionText = fraction.toString().padStart(decimals, "0").replace(/0+$/u, "");
  return `${whole}.${fractionText}`;
}

async function sha256Hex(value) {
  const bytes = new TextEncoder().encode(value);
  const hash = await webcrypto.subtle.digest("SHA-256", bytes);
  return `0x${Buffer.from(hash).toString("hex")}`;
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
      if (process.env[key] != null && process.env[key].trim().length > 0) continue;

      process.env[key] = rawValue.trim().replace(/^['"]|['"]$/gu, "");
    }
  } catch {
    // Missing .env is acceptable for CI.
  }
}
