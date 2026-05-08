#!/usr/bin/env node

import { existsSync, readFileSync } from "node:fs";

const MEZO_CHAIN_ID_HEX = "0x7b7b";
const MEZO_CHAIN_ID_DECIMAL = 31611;
const CONFIG_PATH = "config/mezo-testnet.json";

loadDotEnv();

const config = JSON.parse(readFileSync(CONFIG_PATH, "utf8"));
const selected = await selectProvider();
const manifestPath = normalizeRepoPath(
  process.env.BTC_SLEEVE_VALIDATION_MANIFEST_PATH ?? "deployments/btc-sleeve-validation.json",
);
const validationManifest = readJsonIfExists(manifestPath);
const validationTreasuryAddress = envAddress(
  "BTC_SLEEVE_TREASURY_ACCOUNT",
  envAddress("TREASURY_ACCOUNT", validationManifest?.contracts?.treasuryAccount ?? null),
);

const checks = await Promise.all([
  contractStatus("BTC sleeve validation TreasuryAccount", validationTreasuryAddress),
  contractStatus("MUSD Savings Vault", envAddress("MEZO_MUSD_SAVINGS_RATE", config.musd.savingsRate.address)),
  contractStatus("Tigris MUSD/mUSDC pool", envAddress("MEZO_TIGRIS_MUSD_MUSDC_POOL", config.tigris.pools.musdMusdc.address)),
  contractStatus("Tigris mcbBTC/BTC pool", envAddress("MEZO_TIGRIS_MCBTC_BTC_POOL", config.tigris.pools.mcbtcBtc.address)),
  contractStatus("BTCReservePolicy", envAddress("BTC_RESERVE_POLICY", null)),
  contractStatus("BTCReserveRouter", envAddress("BTC_RESERVE_ROUTER", validationManifest?.contracts?.btcReserveRouter ?? null)),
  contractStatus(
    "TigrisBTCStablePoolHandler",
    envAddress("TIGRIS_BTC_STABLE_POOL_HANDLER", validationManifest?.contracts?.tigrisBTCStablePoolHandler ?? null),
  ),
]);

const [validationTreasury, savings, musdMusdc, mcbtcBtc, btcPolicy, btcRouter, btcHandler] = checks;

printStatus({
  selected,
  savings,
  musdMusdc,
  mcbtcBtc,
  btcPolicy,
  btcRouter,
  btcHandler,
  validationTreasury,
  manifestPath,
  validationManifest,
});

function printStatus(status) {
  console.log("TreasuryOS Demo Status");
  console.log("");

  if (status.selected) {
    console.log(
      `Active RPC provider: ${status.selected.label} (${status.selected.env}, ${
        status.selected.kind === "spectrum" ? "Spectrum" : "official fallback"
      })`,
    );
    console.log(`Chain ID: ${MEZO_CHAIN_ID_DECIMAL}`);
  } else {
    console.log("Active RPC provider: none returned Mezo testnet chain ID 31611");
  }

  console.log("");
  console.log("Sleeve readiness:");
  console.log(
    `- MUSD Savings Vault: V1 executable, ${codePhrase(status.savings)}, address ${status.savings.address ?? "missing"}`,
  );
  console.log(
    `- MUSD/mUSDC: optional/pending final route validation, ${codePhrase(status.musdMusdc)}, address ${
      status.musdMusdc.address ?? "missing"
    }`,
  );
  console.log(
    `- mcbBTC/BTC: V1.5 guarded execution implemented, tiny broadcast validation ${
      status.validationManifest?.broadcastValidationPerformed ? "performed" : "pending"
    }, ${codePhrase(status.mcbtcBtc)}, address ${status.mcbtcBtc.address ?? "missing"}`,
  );

  console.log("");
  console.log("BTC sleeve controls:");
  console.log(
    `- Validation TreasuryAccount: ${
      status.validationTreasury.address
        ? `${codePhrase(status.validationTreasury)} at ${status.validationTreasury.address}`
        : "missing; set BTC_SLEEVE_TREASURY_ACCOUNT to a deployed TreasuryAccount, not OWNER_PUBLIC_KEY"
    }`,
  );
  console.log(`- BTCReservePolicy: ${status.btcPolicy.address ? codePhrase(status.btcPolicy) : "missing in env/manifest"}`);
  console.log(`- BTCReserveRouter: ${status.btcRouter.address ? codePhrase(status.btcRouter) : "will be deployed by validator if missing"}`);
  console.log(
    `- TigrisBTCStablePoolHandler: ${
      status.btcHandler.address ? codePhrase(status.btcHandler) : "will be deployed by validator if missing"
    }`,
  );
  console.log("- LP staking / rewards: future extension, not part of the deposit/unwind validation.");

  console.log("");
  console.log("Broadcast validation:");
  if (status.validationManifest?.broadcastValidationPerformed) {
    console.log(`- Status: performed`);
    console.log(`- Manifest: ${status.manifestPath}`);
    console.log(`- BTC amount: ${status.validationManifest.plan?.btcAmount ?? "unknown"} wei`);
    console.log(`- LP minted: ${status.validationManifest.result?.liquidityMinted ?? "unknown"}`);
    console.log(`- Principal after unwind: ${status.validationManifest.result?.principalAfterWithdraw ?? "unknown"}`);
  } else {
    console.log("- Status: pending");
    console.log(`- Expected manifest after success: ${status.manifestPath}`);
  }
}

function codePhrase(status) {
  if (!status.address) return "not configured";
  if (status.codeBytes == null) return "code not checked";
  return status.codeBytes > 0 ? `code found (${status.codeBytes} bytes)` : "no code found";
}

async function contractStatus(label, address) {
  if (!address) return { label, address: null, codeBytes: null };
  if (!selected) return { label, address, codeBytes: null };
  const code = await jsonRpc(selected.url, "eth_getCode", [address, "latest"]).catch(() => ({ result: "0x" }));
  const hex = typeof code.result === "string" ? code.result : "0x";
  return {
    label,
    address,
    codeBytes: Math.max(0, (hex.length - 2) / 2),
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
      if (typeof response.result === "string" && response.result.toLowerCase() === MEZO_CHAIN_ID_HEX) {
        return candidate;
      }
    } catch {
      // Keep this command compact; detailed diagnostics belong to rpc-health.
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
    if (!response.ok || body.error) throw new Error(body.error?.message ?? `HTTP ${response.status}`);
    return body;
  } finally {
    clearTimeout(timeout);
  }
}

function envAddress(key, fallback) {
  const value = process.env[key];
  if (value && /^0x[0-9a-fA-F]{40}$/u.test(value.trim())) return value.trim();
  return fallback;
}

function readJsonIfExists(path) {
  if (!existsSync(path)) return null;
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return null;
  }
}

function normalizeRepoPath(path) {
  return String(path).replace(/^\.\.\//u, "");
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
    // A missing .env is acceptable for docs and CI checks.
  }
}
