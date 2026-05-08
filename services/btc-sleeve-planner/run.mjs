#!/usr/bin/env node

import { readFileSync } from "node:fs";

import { buildBTCSleevePlan, formatBTCSleevePlan } from "./planner.mjs";

const inputPath = process.argv[2] ?? "services/btc-sleeve-planner/sample-snapshot.json";
const requestedArg = process.argv.find((arg) => arg.startsWith("--btc="));
const requestedBTC = requestedArg ? requestedArg.slice("--btc=".length) : undefined;
const snapshot = JSON.parse(readFileSync(inputPath, "utf8"));
const plan = buildBTCSleevePlan(snapshot, { requestedBTC });

console.log(formatBTCSleevePlan(plan));
