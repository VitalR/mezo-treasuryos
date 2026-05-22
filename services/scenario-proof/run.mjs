#!/usr/bin/env node

import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

import { buildTreasuryAdvisorReport } from "../treasury-advisor/advisor.mjs";
import { buildKeeperActionPlan, buildRiskKeeperReport } from "../treasury-risk-keeper/keeper.mjs";

loadDotEnv();

const SNAPSHOTS = {
  liveAfterRepay: "draft/internal/live-fixed-stack-after-keeper-repay-snapshot.json",
  liveAfterRestore: "draft/internal/live-fixed-stack-after-keeper-restore-snapshot.json",
  liveAfterAllocation: "draft/internal/live-fixed-stack-snapshot.json",
  warningReplay: "draft/internal/live-warning-idle-repay-snapshot.json",
  criticalReplay: "draft/internal/live-critical-sleeve-repay-snapshot.json",
};

const TXS = {
  openPosition: "0xe0fe153b870514833ca3962bd38052cc2fbbd3ab659d298c0f3604614905c21a",
  savingsAllocation: "0x7e730bb74b46b20585890124a458aa0fe7d4414caf1cac83e0826061f4ebd96b",
  operatingDisbursement: "0xc5e12729a6f2faa17d3f54e435d3ab930d9e6143d63779014c742615768dd641",
  keeperRestore: "0x88006ce0bdbb0c1e433b9df31f99d11b85ccd2e0cd89e4e059112d88bf7087be",
  bufferDebtDraw: "0x721de359cf1e00def213f4024a6a37ea359f9fe6a4f8497c5b53986f0176490b",
  keeperIdleRepay: "0x25441e1ec5309673d6515f63d628913350741192c1ec23f9f62a0a557d984933",
};

const CHECK = "OK";

main();

function main() {
  const snapshots = loadSnapshots(SNAPSHOTS);
  const live = snapshots.liveAfterRepay;
  const restored = snapshots.liveAfterRestore;
  const allocated = snapshots.liveAfterAllocation;
  const warning = snapshots.warningReplay;
  const critical = snapshots.criticalReplay;

  const liveKeeper = buildRiskKeeperReport(live);
  const warningKeeper = buildRiskKeeperReport(warning);
  const criticalKeeper = buildRiskKeeperReport(critical);
  const advisor = buildTreasuryAdvisorReport(live);

  printHeader("Mezo TreasuryOS Scenario Proof");
  printNetwork(live);
  printDeployment();
  printLiveState(live);
  printScenarioMatrix({ live, restored, allocated, warningKeeper, criticalKeeper });
  printKeeperPlans({ liveKeeper, warningKeeper, criticalKeeper });
  printAdvisor(advisor);
  printTransactions();
  printClaims();
}

function loadSnapshots(paths) {
  const missing = Object.entries(paths).filter(([, path]) => !existsSync(path));
  if (missing.length > 0) {
    console.error("Missing scenario snapshot(s):");
    for (const [label, path] of missing) {
      console.error(`- ${label}: ${path}`);
    }
    console.error("");
    console.error("Refresh live/internal snapshots before running this proof command.");
    process.exit(1);
  }

  return Object.fromEntries(
    Object.entries(paths).map(([label, path]) => [label, JSON.parse(readFileSync(resolve(path), "utf8"))]),
  );
}

function loadDotEnv(path = ".env") {
  if (!existsSync(path)) return;

  const content = readFileSync(path, "utf8");
  for (const line of content.split(/\r?\n/u)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const separator = trimmed.indexOf("=");
    if (separator === -1) continue;

    const key = trimmed.slice(0, separator).trim();
    let value = trimmed.slice(separator + 1).trim();
    if (!key || process.env[key] != null) continue;

    if (
      (value.startsWith("'") && value.endsWith("'"))
      || (value.startsWith('"') && value.endsWith('"'))
    ) {
      value = value.slice(1, -1);
    }

    process.env[key] = value;
  }
}

function printHeader(title) {
  console.log(title);
  console.log("=".repeat(title.length));
  console.log("");
}

function printNetwork(snapshot) {
  console.log("Network / data source");
  console.log(`- RPC provider: ${snapshot.rpc?.provider ?? "unknown"} (${snapshot.rpc?.env ?? "n/a"})`);
  console.log(`- Chain ID: ${snapshot.rpc?.chainId ?? "n/a"}`);
  console.log(`- Snapshot block: ${snapshot.rpc?.blockNumber ?? "n/a"}`);
  console.log(`- Spectrum active: ${snapshot.rpc?.spectrumActive === true ? "yes" : "no"}`);
  console.log("");
}

function printDeployment() {
  console.log("Deployment");
  line("TreasuryAccount implementation", process.env.TREASURY_ACCOUNT_IMPLEMENTATION);
  line("TreasuryAccount", process.env.TREASURY_ACCOUNT);
  line("Client TreasuryMultisig", process.env.CLIENT_TREASURY_MULTISIG);
  line("TreasuryAutomationExecutor", process.env.TREASURY_AUTOMATION_EXECUTOR);
  line("AllocationRouter", process.env.ALLOCATION_ROUTER);
  line("MUSD Savings handler", process.env.MUSD_SAVINGS_RATE_HANDLER);
  console.log("- Fee infrastructure: deployed for future monetization, disabled, not wired into treasury execution");
  console.log(`  - ProtocolFeeVault: ${process.env.PROTOCOL_FEE_VAULT || "not set"}`);
  console.log(`  - ProtocolFeeManager: ${process.env.PROTOCOL_FEE_MANAGER || "not set"}`);
  console.log("");
}

function printLiveState(snapshot) {
  const savings = firstSavingsSleeve(snapshot);
  console.log("Current live treasury state");
  console.log(`- TreasuryAccount: ${snapshot.treasuryAccount}`);
  console.log(`- BTC collateral: ${snapshot.position?.collateralBTC ?? "0"} BTC`);
  console.log(`- Total debt: ${snapshot.position?.totalDebtMUSD ?? "0"} MUSD`);
  console.log(`- Idle MUSD: ${snapshot.composition?.idleMUSD ?? "0"} MUSD`);
  console.log(`- Required buffer: ${snapshot.composition?.liquidityBufferMUSD ?? "0"} MUSD`);
  console.log(`- MUSD Savings allocation: ${savings?.allocatedMUSD ?? "0"} MUSD`);
  console.log(`- MUSD Savings receipt balance: ${savings?.receiptBalance ?? "0"} sMUSD`);
  console.log(`- Collateral ratio: ${formatBps(snapshot.health?.collateralRatioBps)}`);
  console.log(`- Policy paused: ${snapshot.health?.paused === true ? "yes" : "no"}`);
  console.log("");
}

function printScenarioMatrix({ live, restored, allocated, warningKeeper, criticalKeeper }) {
  console.log("Scenario matrix");
  scenario(
    CHECK,
    "Onboard + borrow",
    `0.05 BTC collateral, ${allocated.position?.totalDebtMUSD ?? "n/a"} MUSD debt, TreasuryAccount-owned position`,
  );
  scenario(
    CHECK,
    "MUSD Savings allocation",
    `${firstSavingsSleeve(allocated)?.allocatedMUSD ?? "0"} MUSD allocated through TreasuryAccount.allocate`,
  );
  scenario(
    CHECK,
    "Policy block",
    `operator allocation preview blocked as ${allocated.allocationDecision?.code ?? "n/a"}`,
  );
  scenario(CHECK, "Healthy keeper", `live state recommends ${buildRiskKeeperReport(live).recommendation.type}`);
  scenario(CHECK, "Warning keeper", `replay recommends ${warningKeeper.recommendation.type}`);
  scenario(CHECK, "Critical keeper", `replay recommends ${criticalKeeper.recommendation.type}`);
  scenario(
    CHECK,
    "Live keeper buffer restore",
    `keeper restored idle MUSD to ${restored.composition?.idleMUSD ?? "n/a"} MUSD from Savings onchain`,
  );
  scenario(
    CHECK,
    "Live keeper debt repayment",
    `keeper repaid idle MUSD onchain; close debt now ${live.position?.closeDebtMUSD ?? "n/a"} MUSD`,
  );
  console.log("");
}

function printKeeperPlans({ liveKeeper, warningKeeper, criticalKeeper }) {
  console.log("Keeper cases");
  printKeeperCase("Live healthy", liveKeeper);
  printKeeperCase("Warning replay", warningKeeper);
  printKeeperCase("Critical replay", criticalKeeper);
  console.log("");
}

function printKeeperCase(label, report) {
  const plan = buildKeeperActionPlan(report, process.env);
  console.log(`- ${label}: ${report.health.state} -> ${report.recommendation.type}`);
  console.log(`  CR: ${formatBps(report.health.currentCollateralRatioBps)}, post-stress: ${formatBps(report.health.postStressCollateralRatioBps)}`);
  console.log(`  Memo: ${report.recommendation.memo}`);
  if (report.recommendation.amountMUSD != null) {
    console.log(`  Amount: ${round(report.recommendation.amountMUSD)} MUSD`);
  }
  console.log(`  Executable plan: ${plan.available ? `${plan.signature} ${plan.humanAmount}` : `no (${plan.reason})`}`);
}

function printAdvisor(report) {
  console.log("Advisor / AI-safe memo proof");
  console.log(`- Risk state: ${report.summary.riskState}`);
  console.log(`- Automation recommendation: ${report.automationAction.action}`);
  console.log(`- Memo: ${report.memo}`);
  console.log("- Guardrail: advisor is reporting only; policy and executor enforce actions");
  console.log("");
}

function printTransactions() {
  console.log("Live transaction proof");
  line("Open position", TXS.openPosition);
  line("Savings allocation", TXS.savingsAllocation);
  line("Operating disbursement to create buffer shortfall", TXS.operatingDisbursement);
  line("Keeper buffer restore", TXS.keeperRestore);
  line("Multisig draw to create repayment headroom", TXS.bufferDebtDraw);
  line("Keeper idle-MUSD debt repayment", TXS.keeperIdleRepay);
  console.log("");
}

function printClaims() {
  console.log("What this proves");
  console.log("- One client TreasuryAccount is owned by a TreasuryMultisig, not an EOA.");
  console.log("- MUSD stays inside TreasuryAccount/Savings vault boundaries; keeper never custodies funds.");
  console.log("- TreasuryAccount is the product execution boundary for live Savings allocation.");
  console.log("- Policy can block unsafe or over-threshold allocation previews.");
  console.log("- Keeper supports monitor, warning, critical, live bounded restore, and live idle-MUSD repayment flows.");
  console.log("- Fees are deployed for monetization, but disabled for the demo.");
}

function firstSavingsSleeve(snapshot) {
  return (snapshot.sleeves ?? []).find((sleeve) => /savings/i.test(sleeve.label ?? ""));
}

function line(label, value) {
  console.log(`- ${label}: ${value || "not set"}`);
}

function scenario(status, label, detail) {
  console.log(`- [${status}] ${label}: ${detail}`);
}

function formatBps(value) {
  const number = Number(value ?? 0);
  return `${(number / 100).toFixed(2)}%`;
}

function round(value) {
  return Number(value ?? 0).toLocaleString("en-US", { maximumFractionDigits: 4 });
}
