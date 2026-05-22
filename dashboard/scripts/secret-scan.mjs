#!/usr/bin/env node

import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const dashboardRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const roots = process.argv.slice(2);
const scanRoots = roots.length > 0 ? roots : [resolve(dashboardRoot, "public"), resolve(dashboardRoot, "dist")];
const denyPatterns = [
  /PRIVATE_KEY/i,
  /RISK_KEEPER_PRIVATE_KEY/i,
  /DEPLOYER_PRIVATE_KEY/i,
  /OWNER_PRIVATE_KEY/i,
  /MNEMONIC/i,
  /OPENAI_API_KEY/i,
  /API_KEY\s*[:=]/i,
  /SECRET\s*[:=]/i,
  /Bearer\s+[A-Za-z0-9._-]+/i,
  /sk-[A-Za-z0-9_-]{12,}/i,
  /(SPECTRUM|MEZO|RPC)[A-Z0-9_ -]*https?:\/\//i,
  /RPC_URL["'\s:=]+https?:\/\//i,
  /https?:\/\/[^"'\s]*(token|apikey|api_key|secret|key)=/i,
];
const allowedFiles = new Set();
const findings = [];

for (const root of scanRoots) {
  if (!existsSync(root)) continue;
  scanPath(root);
}

if (findings.length > 0) {
  console.error("Dashboard secret scan failed:");
  for (const finding of findings) {
    console.error(`- ${finding.file}:${finding.line}: ${finding.text}`);
  }
  process.exit(1);
}

console.log(`Dashboard secret scan passed for ${scanRoots.filter((root) => existsSync(root)).join(", ")}`);

function scanPath(path) {
  const stat = statSync(path);
  if (stat.isDirectory()) {
    for (const entry of readdirSync(path)) {
      if (["node_modules", ".vercel"].includes(entry)) continue;
      scanPath(join(path, entry));
    }
    return;
  }

  if (allowedFiles.has(path) || stat.size > 2_000_000 || !isTextFile(path)) return;

  const content = readFileSync(path, "utf8");
  content.split(/\r?\n/u).forEach((line, index) => {
    for (const pattern of denyPatterns) {
      if (pattern.test(line)) {
        findings.push({
          file: path,
          line: index + 1,
          text: line.trim().slice(0, 220),
        });
      }
    }
  });
}

function isTextFile(path) {
  return /\.(css|html|js|json|map|md|txt|svg)$/iu.test(path);
}
