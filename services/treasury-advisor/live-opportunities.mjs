import { existsSync, readFileSync } from "node:fs";

const MEZO_CHAIN_ID_HEX = "0x7b7b";
const CONFIG_PATH = "config/mezo-testnet.json";

const SELECTORS = {
  decimals: "0x313ce567",
  factory: "0xc45a0155",
  getAmountsOut: "0x5509a1ac",
  getReserves: "0x0902f1ac",
  musdToken: "0x9d78d46b",
  stable: "0x22be3de1",
  symbol: "0x95d89b41",
  token0: "0x0dfe1681",
  token1: "0xd21220a7",
  totalSupply: "0x18160ddd",
  yieldToken: "0x76d5de85",
};

export async function buildLiveMezoOpportunities(env = process.env) {
  const config = JSON.parse(readFileSync(CONFIG_PATH, "utf8"));
  const selected = await selectProvider(env);
  if (!selected) throw new Error("No configured RPC endpoint returned Mezo testnet chain ID 31611");

  const [savings, musdMusdc, mcbtcBtc] = await Promise.all([
    inspectSavingsVault(selected.url, config, config.musd.savingsRate.address),
    inspectPool(selected.url, config, "Tigris Basic Stable MUSD/mUSDC", config.tigris.pools.musdMusdc.address),
    inspectPool(selected.url, config, "Tigris mcbBTC/BTC", config.tigris.pools.mcbtcBtc.address),
  ]);

  const quoteInputBTC = env.BTC_SLEEVE_QUOTE_BTC ?? "0.0001";
  const mcbtcQuote = await quoteBTCToMcbtc(selected.url, config, quoteInputBTC).catch((error) => ({
    error: error.message,
  }));
  const btcValidation = readBTCValidationStatus(env);

  return {
    source: "live-mezo-testnet",
    rpc: {
      provider: selected.label,
      env: selected.env,
      kind: selected.kind,
      chainId: 31611,
    },
    items: [
      {
        label: "MUSD Savings Vault",
        kind: "musd-savings",
        address: savings.address,
        compatible: savings.compatible,
        totalSupply: savings.totalSupplyFormatted,
        note: savings.compatible
          ? "Live vault metadata matches TreasuryOS MUSD Savings handler expectations."
          : "Live vault metadata does not match configured MUSD; do not route funds.",
      },
      {
        label: "Tigris Basic Stable MUSD/mUSDC",
        kind: "stable-lp",
        address: musdMusdc.address,
        compatible: musdMusdc.compatibleWithMUSDHandler,
        reserve0: musdMusdc.reserve0Formatted,
        reserve1: musdMusdc.reserve1Formatted,
        liquidityWarning: musdMusdc.liquidityWarning,
        note: musdMusdc.compatibleWithMUSDHandler
          ? "Live pool metadata is compatible with the MUSD stable LP handler; allocation still depends on route/liquidity checks."
          : "Live pool metadata is not compatible with current MUSD handler config.",
      },
      {
        label: "Tigris mcbBTC/BTC",
        kind: "btc-correlated",
        address: mcbtcBtc.address,
        compatible: mcbtcBtc.factoryMatchesConfig && mcbtcBtc.stable,
        reserve0: mcbtcBtc.reserve0Formatted,
        reserve1: mcbtcBtc.reserve1Formatted,
        quoteInputBTC,
        quoteOutputMCBTC: mcbtcQuote.outputMCBTC ?? null,
        priceImpactBps: mcbtcQuote.priceImpactBpsVsOneToOne ?? null,
        quoteError: mcbtcQuote.error ?? null,
        executionValidated: btcValidation.broadcastValidationPerformed,
        validationManifest: btcValidation.manifestPath,
        note: "BTC-correlated candidate. Advisor must evaluate live quote impact and validation status before recommending execution.",
      },
    ],
  };
}

async function inspectSavingsVault(url, config, address) {
  const [decimals, musdToken, yieldToken, totalSupply] = await Promise.all([
    readUint(url, address, SELECTORS.decimals),
    readAddress(url, address, SELECTORS.musdToken),
    readAddress(url, address, SELECTORS.yieldToken),
    readUint(url, address, SELECTORS.totalSupply),
  ]);

  const compatible =
    normalizeAddress(musdToken) === normalizeAddress(config.musd.token)
    && normalizeAddress(yieldToken) === normalizeAddress(config.musd.token);

  return {
    address,
    decimals: Number(decimals),
    musdToken,
    yieldToken,
    totalSupply: totalSupply.toString(),
    totalSupplyFormatted: formatUnits(totalSupply, Number(decimals)),
    compatible,
  };
}

async function inspectPool(url, config, label, address) {
  const [symbol, stable, factory, token0, token1, reserves, totalSupply] = await Promise.all([
    readString(url, address, SELECTORS.symbol),
    readBool(url, address, SELECTORS.stable),
    readAddress(url, address, SELECTORS.factory),
    readAddress(url, address, SELECTORS.token0),
    readAddress(url, address, SELECTORS.token1),
    readWords(url, address, SELECTORS.getReserves, 3),
    readUint(url, address, SELECTORS.totalSupply),
  ]);
  const [token0Info, token1Info] = await Promise.all([inspectToken(url, token0), inspectToken(url, token1)]);
  const factoryMatchesConfig = normalizeAddress(factory) === normalizeAddress(config.tigris.poolFactory);
  const isMUSD =
    normalizeAddress(token0) === normalizeAddress(config.musd.token)
    || normalizeAddress(token1) === normalizeAddress(config.musd.token);

  return {
    label,
    address,
    symbol,
    stable,
    factory,
    factoryMatchesConfig,
    token0: token0Info,
    token1: token1Info,
    reserve0: reserves[0].toString(),
    reserve1: reserves[1].toString(),
    reserve0Formatted: formatUnits(reserves[0], token0Info.decimals),
    reserve1Formatted: formatUnits(reserves[1], token1Info.decimals),
    totalSupply: totalSupply.toString(),
    totalSupplyFormatted: formatUnits(totalSupply, 18),
    compatibleWithMUSDHandler: isMUSD && stable && factoryMatchesConfig,
    liquidityWarning:
      lowReserve(reserves[0], token0Info.decimals) || lowReserve(reserves[1], token1Info.decimals)
        ? "One side of this pool currently has less than one whole token unit."
        : null,
  };
}

async function inspectToken(url, address) {
  const [symbol, decimals] = await Promise.all([
    readString(url, address, SELECTORS.symbol),
    readUint(url, address, SELECTORS.decimals),
  ]);

  return { address, symbol, decimals: Number(decimals) };
}

async function quoteBTCToMcbtc(url, config, quoteInputBTC) {
  const inputRaw = parseUnits(quoteInputBTC, 18);
  const data = encodeGetAmountsOut(
    inputRaw,
    config.tigris.tokens.btc,
    config.tigris.tokens.mcbtc,
    config.tigris.pools.mcbtcBtc.stable,
    config.tigris.poolFactory,
  );
  const response = await ethCall(url, config.tigris.router, data);
  const amounts = decodeUintArray(response);
  const outputRaw = amounts[1] ?? 0n;

  return {
    inputBTC: quoteInputBTC,
    outputMCBTC: formatUnits(outputRaw, 8),
    outputRaw: outputRaw.toString(),
    priceImpactBpsVsOneToOne: Number(priceImpactBps(inputRaw, outputRaw, 18, 8)),
  };
}

function readBTCValidationStatus(env) {
  const manifestPath = env.BTC_SLEEVE_VALIDATION_MANIFEST_PATH ?? "deployments/btc-sleeve-validation.json";
  if (!existsSync(manifestPath)) return { manifestPath, broadcastValidationPerformed: false };

  try {
    const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
    return {
      manifestPath,
      broadcastValidationPerformed: Boolean(manifest.broadcastValidationPerformed),
    };
  } catch {
    return { manifestPath, broadcastValidationPerformed: false };
  }
}

async function selectProvider(env) {
  const providers = [
    provider(env, "Spectrum 1", "SPECTRUM_MEZO_RPC_URL_1", "spectrum"),
    provider(env, "Spectrum 2", "SPECTRUM_MEZO_RPC_URL_2", "spectrum"),
    provider(env, "Spectrum 3", "SPECTRUM_MEZO_RPC_URL_3", "spectrum"),
    provider(env, "Spectrum legacy", "SPECTRUM_MEZO_RPC_URL", "spectrum"),
    provider(env, "Mezo official fallback", "MEZO_RPC_URL", "official"),
  ];

  for (const candidate of providers) {
    if (!candidate.configured) continue;
    try {
      const response = await jsonRpc(candidate.url, "eth_chainId", []);
      if (String(response.result ?? "").toLowerCase() === MEZO_CHAIN_ID_HEX) return candidate;
    } catch {
      // Try the next configured provider.
    }
  }
  return null;
}

function provider(envValues, label, env, kind) {
  const url = envValues[env] ?? "";
  return { label, env, kind, configured: url.trim().length > 0, url };
}

async function readString(url, to, selector) {
  return decodeString(await ethCall(url, to, selector));
}

async function readBool(url, to, selector) {
  const words = await readWords(url, to, selector, 1);
  return words[0] !== 0n;
}

async function readUint(url, to, selector) {
  const words = await readWords(url, to, selector, 1);
  return words[0];
}

async function readAddress(url, to, selector) {
  const data = await ethCall(url, to, selector);
  if (data.length < 66) return null;
  return checksumlessAddress(`0x${data.slice(26, 66)}`);
}

async function readWords(url, to, selector, count) {
  const data = await ethCall(url, to, selector);
  const body = strip0x(data);
  const words = [];
  for (let index = 0; index < count; index += 1) {
    const word = body.slice(index * 64, (index + 1) * 64);
    words.push(word ? BigInt(`0x${word}`) : 0n);
  }
  return words;
}

async function ethCall(url, to, data) {
  const response = await jsonRpc(url, "eth_call", [{ to, data }, "latest"]);
  if (typeof response.result !== "string") throw new Error(`Invalid eth_call result for ${to}`);
  return response.result;
}

async function jsonRpc(url, method, params) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  if (!response.ok) throw new Error(`RPC ${method} failed with HTTP ${response.status}`);
  const json = await response.json();
  if (json.error) throw new Error(json.error.message ?? `RPC ${method} failed`);
  return json;
}

function encodeGetAmountsOut(amountIn, from, to, stable, factory) {
  const head = SELECTORS.getAmountsOut;
  const amount = word(amountIn);
  const offset = word(64n);
  const length = word(1n);
  const route = `${wordAddress(from)}${wordAddress(to)}${word(stable ? 1n : 0n)}${wordAddress(factory)}`;
  return `${head}${amount}${offset}${length}${route}`;
}

function decodeUintArray(data) {
  const body = strip0x(data);
  const offset = Number(BigInt(`0x${body.slice(0, 64)}`));
  const length = Number(BigInt(`0x${body.slice(offset * 2, offset * 2 + 64)}`));
  const values = [];
  for (let index = 0; index < length; index += 1) {
    const start = offset * 2 + 64 + index * 64;
    values.push(BigInt(`0x${body.slice(start, start + 64)}`));
  }
  return values;
}

function priceImpactBps(inputRaw, outputRaw, inputDecimals, outputDecimals) {
  if (inputRaw <= 0n || outputRaw <= 0n) return 10_000n;
  const scale = 10n ** BigInt(inputDecimals - outputDecimals);
  const outputAsInputDecimals = outputRaw * scale;
  if (outputAsInputDecimals >= inputRaw) return 0n;
  return (inputRaw - outputAsInputDecimals) * 10_000n / inputRaw;
}

function parseUnits(value, decimals) {
  const [whole, fraction = ""] = String(value).split(".");
  const padded = `${fraction}${"0".repeat(decimals)}`.slice(0, decimals);
  return BigInt(whole || "0") * 10n ** BigInt(decimals) + BigInt(padded || "0");
}

function formatUnits(value, decimals) {
  const base = 10n ** BigInt(decimals);
  const whole = value / base;
  const fraction = (value % base).toString().padStart(decimals, "0").replace(/0+$/u, "");
  return fraction ? `${whole}.${fraction}` : whole.toString();
}

function lowReserve(value, decimals) {
  return value > 0n && value < 10n ** BigInt(decimals);
}

function decodeString(data) {
  const body = strip0x(data);
  if (body.length < 128) return "";
  const offset = Number(BigInt(`0x${body.slice(0, 64)}`));
  const length = Number(BigInt(`0x${body.slice(offset * 2, offset * 2 + 64)}`));
  const start = offset * 2 + 64;
  const hex = body.slice(start, start + length * 2);
  return Buffer.from(hex, "hex").toString("utf8");
}

function word(value) {
  return BigInt(value).toString(16).padStart(64, "0");
}

function wordAddress(address) {
  return strip0x(address).toLowerCase().padStart(64, "0");
}

function strip0x(value) {
  return String(value).startsWith("0x") ? String(value).slice(2) : String(value);
}

function checksumlessAddress(value) {
  return `0x${strip0x(value).slice(-40).toLowerCase()}`;
}

function normalizeAddress(value) {
  return String(value ?? "").toLowerCase();
}
