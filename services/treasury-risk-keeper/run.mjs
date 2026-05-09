#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

import { buildKeeperActionPlan, buildRiskKeeperReport, renderRiskKeeperReport } from "./keeper.mjs";

const DEFAULT_SNAPSHOT_PATH = "services/treasury-risk-keeper/sample-snapshot.json";

export function main(argv = process.argv.slice(2), env = process.env, io = console) {
  const snapshotPath = snapshotPathFromArgs(argv);
  const snapshot = JSON.parse(readFileSync(snapshotPath, "utf8"));
  const report = buildRiskKeeperReport(snapshot);
  const mode = env.RISK_KEEPER_MODE ?? (argv.includes("--propose") ? "propose" : "dry-run");

  if (argv.includes("--json")) {
    io.log(JSON.stringify({ mode, report, actionPlan: buildKeeperActionPlan(report, env) }, null, 2));
    return;
  }

  io.log(renderRiskKeeperReport(report));

  if (mode === "propose") {
    io.log("");
    io.log(renderActionPlan(buildKeeperActionPlan(report, env)));
    return;
  }

  if (mode === "execute") {
    io.log("");
    const plan = buildKeeperActionPlan(report, env);
    io.log(renderActionPlan(plan));
    executeActionPlan(plan, env, spawnSync, io);
  }
}

export function renderActionPlan(plan) {
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

export function executeActionPlan(plan, env = process.env, runner = spawnSync, io = console) {
  if (!plan.available) {
    throw new Error(`Keeper action is not executable: ${plan.reason}`);
  }

  if (env.RISK_KEEPER_EXECUTE_CONFIRM !== "true") {
    throw new Error("Refusing execute mode without RISK_KEEPER_EXECUTE_CONFIRM=true");
  }

  const maxActions = Number(env.RISK_KEEPER_MAX_ACTIONS_PER_RUN ?? "1");
  if (maxActions !== 1) {
    throw new Error("RISK_KEEPER_MAX_ACTIONS_PER_RUN must be 1 for this guarded executor");
  }

  const privateKey = env.RISK_KEEPER_PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("Missing RISK_KEEPER_PRIVATE_KEY for execute mode");
  }

  const rpcUrl = env.ACTIVE_MEZO_RPC_URL ?? env.MEZO_RPC_URL;
  if (!rpcUrl) {
    throw new Error("Missing ACTIVE_MEZO_RPC_URL or MEZO_RPC_URL for execute mode");
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

  io.log("");
  io.log(`Executing one keeper action through TreasuryAutomationExecutor: ${plan.recommendationType}`);
  const result = runner("cast", args, { stdio: "inherit" });
  if (result.status !== 0) {
    throw new Error(`cast send failed with status ${result.status}`);
  }
}

function snapshotPathFromArgs(argv) {
  return argv.find((arg) => !arg.startsWith("--")) ?? DEFAULT_SNAPSHOT_PATH;
}

if (fileURLToPath(import.meta.url) === resolve(process.argv[1] ?? "")) {
  try {
    main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  }
}
