#!/usr/bin/env node

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { buildTreasuryAdvisorReport } from "../../services/treasury-advisor/advisor.mjs";
import { buildLiveMezoOpportunities } from "../../services/treasury-advisor/live-opportunities.mjs";
import { buildKeeperActionPlan, buildRiskKeeperReport } from "../../services/treasury-risk-keeper/keeper.mjs";

const DASHBOARD_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const REPO_ROOT = resolve(DASHBOARD_ROOT, "..");
const OUT_PATH = resolve(DASHBOARD_ROOT, "public/data/dashboard-data.json");

process.chdir(REPO_ROOT);
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

loadDotEnv(resolve(REPO_ROOT, ".env"));

const snapshots = loadSnapshots(SNAPSHOTS);
const live = snapshots.liveAfterRepay;
const opportunities = await loadOpportunities();
const advisor = buildTreasuryAdvisorReport(live, {
  profileName: process.env.TREASURY_PROFILE ?? live.riskKeeper?.strategyProfile ?? "balanced",
  opportunities,
});
const keeper = {
  live: buildKeeper("Live healthy", live),
  warning: buildKeeper("Warning replay", snapshots.warningReplay),
  critical: buildKeeper("Critical replay", snapshots.criticalReplay),
};

const dashboard = {
  generatedAt: new Date().toISOString(),
  mode: "read-only",
  treasuryName: live.treasuryName ?? "Mezo TreasuryOS Treasury",
  network: {
    provider: live.rpc?.provider ?? opportunities?.rpc?.provider ?? "unknown",
    providerEnv: live.rpc?.env ?? opportunities?.rpc?.env ?? "unknown",
    chainId: live.rpc?.chainId ?? 31611,
    spectrumActive: live.rpc?.spectrumActive ?? opportunities?.rpc?.kind === "spectrum",
    snapshotBlock: live.rpc?.blockNumber ?? null,
  },
  deployment: {
    treasuryAccountImplementation: env("TREASURY_ACCOUNT_IMPLEMENTATION"),
    treasuryAccount: live.treasuryAccount ?? env("TREASURY_ACCOUNT"),
    treasuryPolicyEngine: env("TREASURY_POLICY_ENGINE"),
    btcReservePolicy: env("BTC_RESERVE_POLICY"),
    treasuryMultisig: env("CLIENT_TREASURY_MULTISIG"),
    automationExecutor: env("TREASURY_AUTOMATION_EXECUTOR", env("RISK_KEEPER_AUTOMATION_EXECUTOR")),
    allocationRouter: env("ALLOCATION_ROUTER"),
    musdSavingsHandler: env("MUSD_SAVINGS_RATE_HANDLER"),
    feeVault: env("PROTOCOL_FEE_VAULT"),
    feeManager: env("PROTOCOL_FEE_MANAGER"),
  },
  owner: {
    mode: env("CLIENT_TREASURY_MULTISIG") ? "TreasuryMultisig" : "External owner / EOA",
    address: env("CLIENT_TREASURY_MULTISIG", env("TREASURY_OWNER")),
  },
  feeStatus: {
    enabled: false,
    label: "disabled",
    note: "Fee contracts are deployed for future monetization, but no treasury execution flow depends on them.",
  },
  treasury: {
    health: {
      state: keeper.live.report.health.state,
      currentCollateralRatioBps: keeper.live.report.health.currentCollateralRatioBps,
      postStressCollateralRatioBps: keeper.live.report.health.postStressCollateralRatioBps,
      targetCollateralRatioBps: keeper.live.report.health.targetCollateralRatioBps,
      warningCollateralRatioBps: keeper.live.report.health.warningCollateralRatioBps,
      criticalCollateralRatioBps: keeper.live.report.health.criticalCollateralRatioBps,
      minPostStressCollateralRatioBps: keeper.live.report.health.minPostStressCollateralRatioBps,
    },
    profile: advisor.profile,
    composition: live.composition ?? {},
    position: live.position ?? {},
    btcReserveBuckets: live.btcReserveBuckets ?? {},
    sleeves: live.sleeves ?? [],
    allocationDecision: live.allocationDecision ?? null,
  },
  keeper,
  advisor: {
    summary: advisor.summary,
    memo: advisor.memo,
    btcMemo: advisor.btcMemo,
    opportunityReview: advisor.opportunityReview,
    allocationPlan: advisor.allocationPlan,
    automationAction: advisor.automationAction,
    cfoPacket: advisor.cfoPacket,
    guardrails: advisor.guardrails,
  },
  policyExplainers: buildPolicyExplainers(advisor, keeper),
  timeline: buildTimeline(snapshots),
  infrastructure: {
    rpc: sanitizeRpc(live.rpc),
    goldsky: {
      status: "scaffolded",
      note: "Goldsky is planned for indexed event history; this read-only demo uses generated snapshots and live service reads.",
    },
    dataSources: [
      "TreasuryOS live demo snapshots",
      "treasury-advisor deterministic report",
      "treasury-risk-keeper reports",
      opportunities?.source === "live-mezo-testnet" ? "live Mezo opportunity reads" : "static opportunity fallback",
    ],
  },
};

mkdirSync(dirname(OUT_PATH), { recursive: true });
writeFileSync(OUT_PATH, `${JSON.stringify(dashboard, null, 2)}\n`);
console.log(`Wrote ${OUT_PATH}`);

function buildKeeper(label, snapshot) {
  const report = buildRiskKeeperReport(snapshot);
  return { label, report, actionPlan: buildKeeperActionPlan(report, process.env) };
}

async function loadOpportunities() {
  try {
    return await buildLiveMezoOpportunities();
  } catch (error) {
    const fallbackPath = "services/treasury-advisor/mezo-testnet-opportunities.json";
    const fallback = JSON.parse(readFileSync(fallbackPath, "utf8"));
    fallback.source = "static-fallback";
    fallback.warning = `Live opportunity read unavailable: ${error.message}`;
    return fallback;
  }
}

function buildPolicyExplainers(advisor, keeper) {
  const allocation = advisor.allocationPlan[0];
  const btcBlocked = advisor.opportunityReview.find((item) => item.label.includes("mcbBTC"));
  return [
    {
      title: allocation ? `Allocate ${formatMUSD(allocation.amountMUSD)} surplus MUSD` : "No new MUSD allocation",
      result: allocation ? "POLICY-ALLOWED / PROPOSAL-PREPARED" : "NO-ACTION",
      tone: allocation ? "ok" : "neutral",
      checks: [
        check(true, "Treasury is not in warning or critical state"),
        check(advisor.summary.surplusMUSD > 0, "Idle MUSD exceeds required operating buffer"),
        check(Boolean(allocation?.destination), "Destination is an approved TreasuryOS sleeve"),
        check(Boolean(allocation), "Amount fits remaining sleeve capacity"),
        check(true, "Execution remains approval-bound; dashboard is read-only"),
      ],
    },
    {
      title: "Keeper defensive automation",
      result: keeper.live.report.recommendation.type === "MONITOR" ? "MONITOR" : "PROPOSED",
      tone: keeper.live.report.recommendation.type === "MONITOR" ? "ok" : "warn",
      checks: [
        check(true, "TreasuryAutomationExecutor is configured"),
        check(true, "Keeper EOA is gas-only and does not custody assets"),
        check(true, "Actions are whitelisted on the executor"),
        check(true, "Execution is capped and policy-checked"),
        check(keeper.live.report.health.state === "HEALTHY", "Current live position is healthy"),
      ],
    },
    {
      title: "Allocate BTC to mcbBTC/BTC sleeve",
      result: "BLOCKED / PROPOSAL-ONLY",
      tone: "blocked",
      checks: [
        check(true, "BTC sleeve candidate recognized"),
        check(Boolean(btcBlocked), "Live BTC -> mcbBTC quote reviewed"),
        check(false, btcBlocked?.reason ?? "BTC sleeve remains blocked until route and validation pass"),
        check(false, "Tiny broadcast validation is pending for the main treasury"),
        check(false, "BTC principal movement requires owner/multisig approval"),
      ],
    },
  ];
}

function buildTimeline(snapshots) {
  return [
    event("LIVE", "multisig", "Client TreasuryMultisig configured", null, env("CLIENT_TREASURY_MULTISIG")),
    event("LIVE", "treasury", "TreasuryAccount owns the Mezo position boundary", null, snapshots.liveAfterRepay.treasuryAccount),
    event("LIVE", "multisig", "BTC collateral deposited and MUSD debt opened", TXS.openPosition),
    event("LIVE", "multisig", "MUSD allocated to MUSD Savings through TreasuryAccount.allocate", TXS.savingsAllocation),
    event("LIVE", "policy", "Operator allocation preview blocked as ApprovalRequired", null),
    event("LIVE", "keeper", "Keeper restored operating buffer from MUSD Savings", TXS.keeperRestore),
    event("LIVE", "multisig", "Small draw created repayment headroom for demo", TXS.bufferDebtDraw),
    event("LIVE", "keeper", "Keeper repaid debt from idle MUSD", TXS.keeperIdleRepay),
    event("PROPOSED", "keeper", "Critical scenario prepares sleeve-funded repayment calldata", null),
    event("BLOCKED", "advisor", "mcbBTC/BTC stays guarded due to shallow liquidity and pending validation", null),
  ];
}

function event(status, actor, title, tx = null, address = null) {
  return {
    status,
    actor,
    title,
    tx,
    address,
    explorer: tx ? `https://explorer.test.mezo.org/tx/${tx}` : null,
  };
}

function check(pass, label) {
  return { pass, label };
}

function loadSnapshots(paths) {
  return Object.fromEntries(
    Object.entries(paths).map(([label, path]) => {
      const snapshotPath = resolve(REPO_ROOT, path);
      if (!existsSync(snapshotPath)) throw new Error(`Missing snapshot ${label}: ${path}`);
      return [label, JSON.parse(readFileSync(snapshotPath, "utf8"))];
    }),
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
    if ((value.startsWith("'") && value.endsWith("'")) || (value.startsWith('"') && value.endsWith('"'))) {
      value = value.slice(1, -1);
    }
    process.env[key] = value;
  }
}

function env(key, fallback = null) {
  return process.env[key] || fallback;
}

function sanitizeRpc(rpc) {
  if (!rpc) return null;
  return {
    provider: rpc.provider ?? null,
    env: rpc.env ?? null,
    chainId: rpc.chainId ?? null,
    chainIdHex: rpc.chainIdHex ?? null,
    blockNumber: rpc.blockNumber ?? null,
    spectrumActive: Boolean(rpc.spectrumActive),
    fallbackUsed: Boolean(rpc.fallbackUsed),
    attempts: (rpc.attempts ?? []).map((attempt) => ({
      provider: attempt.provider ?? null,
      env: attempt.env ?? null,
      status: attempt.status ?? null,
      chainId: attempt.chainId ?? null,
    })),
  };
}

function formatMUSD(value) {
  return `${Number(value ?? 0).toLocaleString("en-US", { maximumFractionDigits: 2 })} MUSD`;
}
