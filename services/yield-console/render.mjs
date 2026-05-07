#!/usr/bin/env node

import { readFileSync } from "node:fs";

const inputPath = process.argv[2];

if (!inputPath) {
  console.error("Usage: node services/yield-console/render.mjs <snapshot.json>");
  process.exit(1);
}

const snapshot = JSON.parse(readFileSync(inputPath, "utf8"));

function asNumber(value) {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function musd(value) {
  return `${asNumber(value).toLocaleString("en-US", {
    maximumFractionDigits: 2,
  })} MUSD`;
}

function bps(value) {
  return `${(asNumber(value) / 100).toFixed(2)}%`;
}

function btc(value) {
  return `${asNumber(value).toLocaleString("en-US", {
    maximumFractionDigits: 8,
  })} BTC`;
}

function decisionReason(code) {
  const reasons = {
    Allowed: "allocation passes current policy",
    Paused: "treasury policy is paused",
    ZeroAmount: "allocation amount is zero",
    InvalidDestination: "destination is not valid",
    NotApprovedDestination: "destination is not approved for this treasury",
    UnauthorizedActor: "actor is not authorized for this treasury action",
    ApprovalRequired: "amount exceeds the operator approval threshold",
    InsufficientIdleBalance: "idle MUSD is below the requested amount",
    LiquidityBufferBreached: "allocation would breach the required operating buffer",
    AllocationCapExceeded: "allocation would exceed the destination cap",
  };

  return reasons[code] ?? "policy returned an unknown decision";
}

function sleeveMemo(sleeves) {
  const pressured = sleeves.find((sleeve) => {
    const cap = asNumber(sleeve.capMUSD);
    if (cap === 0) return false;
    return asNumber(sleeve.remainingCapacityMUSD) / cap <= 0.1;
  });

  if (!pressured) return null;

  return `${pressured.label} sleeve cap is near limit; prefer another approved sleeve unless policy caps are updated.`;
}

function recommendation(snapshot) {
  const surplus = asNumber(snapshot.composition.deployableSurplusMUSD);
  const health = snapshot.health ?? {};
  const decision = snapshot.allocationDecision ?? {};

  if (health.belowCriticalRatio || health.belowWarningRatio) {
    return "Collateral health is weakening; do not allocate more MUSD. Prepare buffer restoration or debt repayment.";
  }

  if (surplus <= 0) {
    return "Idle MUSD does not exceed the required buffer. No additional allocation is recommended.";
  }

  if (!decision.allowed) {
    return `Requested allocation is blocked because ${decisionReason(decision.code)}. Keep surplus idle or choose a compliant action.`;
  }

  const sleevePressure = sleeveMemo(snapshot.sleeves ?? []);
  if (sleevePressure) return sleevePressure;

  return `Idle MUSD exceeds the operating buffer by ${musd(surplus)}; the proposed allocation is policy-compliant.`;
}

function btcRecommendation(snapshot) {
  const composition = snapshot.composition ?? {};
  const position = snapshot.position ?? {};
  const btcSleeves = snapshot.btcSleeves ?? [];
  const idleBTC = asNumber(composition.idleBTC);
  const collateralBTC = asNumber(position.collateralBTC);
  const executableSleeve = btcSleeves.find((sleeve) => sleeve.approved && sleeve.executable);
  const directionalSleeve = btcSleeves.find((sleeve) =>
    String(sleeve.riskClass ?? "").includes("stable") || String(sleeve.riskClass ?? "").includes("directional"),
  );

  if (idleBTC <= 0 && collateralBTC <= 0 && btcSleeves.length === 0) {
    return null;
  }

  if (!executableSleeve) {
    if (directionalSleeve) {
      return `${directionalSleeve.label} is a planning-only BTC/stable LP candidate; it changes pure BTC exposure and should require elevated approval.`;
    }

    return "BTC reserve and collateral are reported separately from MUSD sleeves. No BTC-denominated sleeve has a live V1 execution path.";
  }

  return `${executableSleeve.label} is the only BTC-denominated sleeve with a live execution path in this snapshot; apply BTC-specific policy before use.`;
}

const lines = [];

lines.push(`Treasury Yield Console: ${snapshot.treasuryName}`);
lines.push("");
lines.push(`Idle MUSD: ${musd(snapshot.composition.idleMUSD)}`);
lines.push(`Required buffer: ${musd(snapshot.composition.liquidityBufferMUSD)}`);
lines.push(`Allocatable surplus: ${musd(snapshot.composition.deployableSurplusMUSD)}`);
lines.push(`Idle BTC reserve: ${btc(snapshot.composition.idleBTC)}`);
lines.push(`BTC collateral: ${btc(snapshot.position?.collateralBTC)}`);
lines.push(`Collateral ratio: ${bps(snapshot.health?.collateralRatioBps)}`);
lines.push("");
lines.push("Approved sleeves:");

for (const sleeve of snapshot.sleeves ?? []) {
  lines.push(
    `- ${sleeve.label}: allocated ${musd(sleeve.allocatedMUSD)} / cap ${musd(
      sleeve.capMUSD,
    )}, remaining ${musd(sleeve.remainingCapacityMUSD)}`,
  );
}

if ((snapshot.btcSleeves ?? []).length > 0) {
  lines.push("");
  lines.push("BTC sleeve candidates:");
  for (const sleeve of snapshot.btcSleeves ?? []) {
    lines.push(
      `- ${sleeve.label}: ${sleeve.status ?? "candidate"}, allocated ${btc(
        sleeve.allocatedBTC,
      )}, ${sleeve.executable ? "execution path live" : "reporting only"}`,
    );
  }
}

const decision = snapshot.allocationDecision ?? {};
lines.push("");
lines.push(`Policy decision: ${decision.allowed ? "ALLOW" : "BLOCK"} (${decision.code})`);
lines.push(`Decision reason: ${decisionReason(decision.code)}`);
lines.push("");
lines.push("Advisor memo:");
lines.push(recommendation(snapshot));
const btcMemo = btcRecommendation(snapshot);
if (btcMemo) {
  lines.push("");
  lines.push("BTC memo:");
  lines.push(btcMemo);
}

console.log(lines.join("\n"));
