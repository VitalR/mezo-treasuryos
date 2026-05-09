#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

import { buildKeeperActionPlan, buildRiskKeeperReport, renderRiskKeeperReport } from "./keeper.mjs";

const snapshotPath = process.argv[2] ?? "services/treasury-risk-keeper/sample-snapshot.json";
const snapshot = JSON.parse(readFileSync(snapshotPath, "utf8"));
const report = buildRiskKeeperReport(snapshot);
const mode = process.env.RISK_KEEPER_MODE ?? (process.argv.includes("--propose") ? "propose" : "dry-run");

if (process.argv.includes("--json")) {
  console.log(JSON.stringify({ mode, report, actionPlan: buildKeeperActionPlan(report) }, null, 2));
} else if (mode === "propose") {
  console.log(renderRiskKeeperReport(report));
  console.log("");
  console.log(renderActionPlan(buildKeeperActionPlan(report)));
} else if (mode === "execute") {
  console.log(renderRiskKeeperReport(report));
  console.log("");
  const plan = buildKeeperActionPlan(report);
  console.log(renderActionPlan(plan));
  executeActionPlan(plan);
} else {
  console.log(renderRiskKeeperReport(report));
}

function renderActionPlan(plan) {
  const lines = ["Keeper action plan:"];
  lines.push(`- Recommendation: ${plan.recommendationType}`);

  if (!plan.available) {
    lines.push(`- Executable: no (${plan.reason})`);
    return lines.join("\n");
  }

  lines.push("- Executable: yes");
  lines.push(`- Target: ${plan.target}`);
  lines.push(`- Value: ${plan.value}`);
  lines.push(`- Signature: ${plan.signature}`);
  lines.push(`- Args: ${plan.args.join(", ")}`);
  lines.push(`- Human amount: ${plan.humanAmount ?? "n/a"}`);
  lines.push(`- Calldata helper: ${plan.castCalldataCommand}`);
  lines.push("- Multisig proposal: target above, value 0, data from the calldata helper.");
  return lines.join("\n");
}

function executeActionPlan(plan) {
  if (!plan.available) {
    throw new Error(`Keeper action is not executable: ${plan.reason}`);
  }

  if (process.env.RISK_KEEPER_EXECUTE_CONFIRM !== "true") {
    throw new Error("Refusing execute mode without RISK_KEEPER_EXECUTE_CONFIRM=true");
  }

  const privateKey = process.env.RISK_KEEPER_PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("Missing RISK_KEEPER_PRIVATE_KEY for execute mode");
  }

  const rpcUrl = process.env.ACTIVE_MEZO_RPC_URL ?? process.env.MEZO_RPC_URL;
  if (!rpcUrl) {
    throw new Error("Missing ACTIVE_MEZO_RPC_URL or MEZO_RPC_URL for execute mode");
  }

  const maxActions = Number(process.env.RISK_KEEPER_MAX_ACTIONS_PER_RUN ?? "1");
  if (maxActions !== 1) {
    throw new Error("RISK_KEEPER_MAX_ACTIONS_PER_RUN must be 1 for this guarded executor");
  }

  const args = [
    "send",
    plan.target,
    plan.signature,
    ...plan.args,
    "--private-key",
    privateKey,
    "--rpc-url",
    rpcUrl,
  ];

  console.log("");
  console.log(`Executing one keeper action through TreasuryAutomationExecutor: ${plan.recommendationType}`);
  const result = spawnSync("cast", args, { stdio: "inherit" });
  if (result.status !== 0) {
    throw new Error(`cast send failed with status ${result.status}`);
  }
}
