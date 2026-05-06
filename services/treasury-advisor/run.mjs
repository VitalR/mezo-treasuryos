#!/usr/bin/env node

import { readFileSync } from "node:fs";

import { buildTreasuryAdvisorReport, formatAdvisorReport } from "./advisor.mjs";

const inputPath = process.argv[2];

if (!inputPath) {
  console.error("Usage: node services/treasury-advisor/run.mjs <snapshot.json>");
  process.exit(1);
}

const snapshot = JSON.parse(readFileSync(inputPath, "utf8"));
const report = buildTreasuryAdvisorReport(snapshot);

console.log(formatAdvisorReport(report));
