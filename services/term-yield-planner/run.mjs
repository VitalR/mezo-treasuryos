#!/usr/bin/env node

import { readFileSync } from "node:fs";

import { buildTermYieldPlan, formatTermYieldPlan } from "./planner.mjs";

const inputPath = process.argv[2];

if (!inputPath) {
  console.error("Usage: node services/term-yield-planner/run.mjs <snapshot.json> [--json]");
  process.exit(1);
}

const snapshot = JSON.parse(readFileSync(inputPath, "utf8"));
const plan = buildTermYieldPlan(snapshot);

if (process.argv.includes("--json")) {
  console.log(JSON.stringify(plan, null, 2));
} else {
  console.log(formatTermYieldPlan(plan));
}
