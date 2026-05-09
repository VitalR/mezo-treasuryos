#!/usr/bin/env node

import { readFileSync } from "node:fs";

import { buildRiskKeeperReport, renderRiskKeeperReport } from "./keeper.mjs";

const snapshotPath = process.argv[2] ?? "services/treasury-risk-keeper/sample-snapshot.json";
const snapshot = JSON.parse(readFileSync(snapshotPath, "utf8"));
const report = buildRiskKeeperReport(snapshot);

if (process.argv.includes("--json")) {
  console.log(JSON.stringify(report, null, 2));
} else {
  console.log(renderRiskKeeperReport(report));
}
