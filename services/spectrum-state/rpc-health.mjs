#!/usr/bin/env node

import { readFileSync } from "node:fs";

const MEZO_CHAIN_ID_HEX = "0x7b7b";
const MEZO_CHAIN_ID_DECIMAL = 31611;

loadDotEnv();

const args = parseArgs(process.argv.slice(2));

if (args.help) {
  printHelp();
  process.exit(0);
}

const results = await checkAllProviders();
const selected = results.find((result) => result.ok);

if (args.shell) {
  if (!selected) process.exit(1);
  console.log(`ACTIVE_MEZO_RPC_PROVIDER=${quoteShell(selected.label)}`);
  console.log(`ACTIVE_MEZO_RPC_ENV=${quoteShell(selected.env)}`);
  console.log(`ACTIVE_MEZO_RPC_KIND=${quoteShell(selected.kind)}`);
  process.exit(0);
}

if (args.printProvider) {
  if (!selected) process.exit(1);
  console.log(selected.label);
  process.exit(0);
}

if (args.json) {
  console.log(
    JSON.stringify(
      {
        expectedChainId: MEZO_CHAIN_ID_DECIMAL,
        selected: selected ? sanitizeResult(selected) : null,
        results: results.map(sanitizeResult),
      },
      null,
      2,
    ),
  );
} else {
  printTable(results);
  if (selected?.kind === "spectrum") {
    console.log(`Spectrum Mezo Testnet RPC is active: using ${selected.env}.`);
  } else if (selected) {
    console.log(
      `No healthy Spectrum endpoint found. Using official Mezo RPC fallback from ${selected.env}; keep Spectrum configured for future probes.`,
    );
  }
}

process.exit(selected ? 0 : 1);

async function checkAllProviders() {
  const providers = [
    provider("Spectrum 1", "SPECTRUM_MEZO_RPC_URL_1", "spectrum"),
    provider("Spectrum 2", "SPECTRUM_MEZO_RPC_URL_2", "spectrum"),
    provider("Spectrum 3", "SPECTRUM_MEZO_RPC_URL_3", "spectrum"),
    provider("Spectrum legacy", "SPECTRUM_MEZO_RPC_URL", "spectrum"),
    provider("Mezo official fallback", "MEZO_RPC_URL", "official"),
  ];

  const results = [];
  for (const candidate of providers) {
    results.push(await checkProvider(candidate));
  }

  return results;
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

async function checkProvider(candidate) {
  if (!candidate.configured) {
    return {
      ...candidate,
      httpStatus: "-",
      chainId: "-",
      result: "not configured",
      diagnostic: "Set this env var to include it in provider selection.",
      ok: false,
    };
  }

  try {
    const response = await jsonRpc(candidate.url, "eth_chainId", []);
    const chainId = typeof response.body?.result === "string" ? response.body.result.toLowerCase() : "-";
    const ok = chainId === MEZO_CHAIN_ID_HEX;

    if (ok) {
      return {
        ...candidate,
        httpStatus: response.status,
        chainId,
        result: "OK",
        diagnostic: `Endpoint returned Mezo EVM Testnet chain ID ${MEZO_CHAIN_ID_DECIMAL}.`,
        ok: true,
      };
    }

    if (response.body?.error) {
      return {
        ...candidate,
        httpStatus: response.status,
        chainId,
        result: "failed",
        diagnostic: redactDiagnostic(`JSON-RPC error ${response.body.error.code}: ${response.body.error.message}`),
        ok: false,
      };
    }

    return {
      ...candidate,
      httpStatus: response.status,
      chainId,
      result: "wrong chain",
      diagnostic: "Endpoint responded, but not as Mezo EVM Testnet.",
      ok: false,
    };
  } catch (error) {
    return {
      ...candidate,
      httpStatus: error.status ?? "-",
      chainId: "-",
      result: likelyNonJsonRpc(error) ? "likely non-JSON-RPC endpoint" : "failed",
      diagnostic: diagnosticForError(error),
      ok: false,
    };
  }
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
    const text = await response.text();
    let body;

    try {
      body = text ? JSON.parse(text) : {};
    } catch {
      const error = new Error(`Non-JSON response from endpoint`);
      error.status = response.status;
      error.bodyText = text.slice(0, 120);
      throw error;
    }

    if (!response.ok) {
      const error = new Error(`HTTP ${response.status}`);
      error.status = response.status;
      error.body = body;
      throw error;
    }

    return { status: response.status, body };
  } finally {
    clearTimeout(timeout);
  }
}

function diagnosticForError(error) {
  if (error.status === 400) {
    return "This endpoint may be a Blockchain API / GraphQL endpoint, not an EVM JSON-RPC endpoint. Foundry/ethers/viem require eth_chainId = 0x7b7b.";
  }

  if (error.status) {
    return `Endpoint did not return a valid Mezo JSON-RPC response: HTTP ${error.status}.`;
  }

  return redactDiagnostic(`Endpoint probe failed: ${error.message}`);
}

function likelyNonJsonRpc(error) {
  return error.status === 400 || error.message.includes("Non-JSON");
}

function printTable(results) {
  const rows = results.map((result) => ({
    provider: result.label,
    env: result.env,
    configured: result.configured ? "yes" : "no",
    http: String(result.httpStatus),
    chainId: result.chainId,
    result: result.result,
  }));

  console.table(rows);

  for (const result of results) {
    if (result.configured && !result.ok && result.diagnostic) {
      console.log(`${result.env}: ${result.diagnostic}`);
    }
  }
}

function sanitizeResult(result) {
  return {
    provider: result.label,
    env: result.env,
    configured: result.configured,
    httpStatus: result.httpStatus,
    chainId: result.chainId,
    result: result.result,
    diagnostic: result.diagnostic,
    selected: result.ok,
  };
}

function parseArgs(argv) {
  const parsed = {};
  for (const token of argv) {
    if (token === "--help") parsed.help = true;
    if (token === "--json") parsed.json = true;
    if (token === "--shell") parsed.shell = true;
    if (token === "--print-provider") parsed.printProvider = true;
  }
  return parsed;
}

function quoteShell(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}

function redactDiagnostic(value) {
  return String(value).replace(/https?:\/\/\S+/g, "[redacted-url]");
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
      if (process.env[key] != null && process.env[key].trim().length > 0) continue;

      process.env[key] = rawValue.trim().replace(/^['"]|['"]$/g, "");
    }
  } catch {
    // A missing .env is acceptable for CI and documentation checks.
  }
}

function printHelp() {
  console.log(`Usage:
  node services/spectrum-state/rpc-health.mjs
  node services/spectrum-state/rpc-health.mjs --json
  node services/spectrum-state/rpc-health.mjs --shell

Provider order:
  1. SPECTRUM_MEZO_RPC_URL_1
  2. SPECTRUM_MEZO_RPC_URL_2
  3. SPECTRUM_MEZO_RPC_URL_3
  4. SPECTRUM_MEZO_RPC_URL
  5. MEZO_RPC_URL

The table and shell modes print provider labels/env keys only, not raw RPC URLs.
`);
}
