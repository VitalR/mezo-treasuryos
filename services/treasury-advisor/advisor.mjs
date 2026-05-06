const DAY_COUNT = [7, 30, 60];

const RISK_WEIGHT = {
  low: 3,
  medium: 2,
  high: 1,
};

export function buildTreasuryAdvisorReport(snapshot) {
  const composition = snapshot.composition ?? {};
  const health = snapshot.health ?? {};
  const sleeves = normalizeSleeves(snapshot.sleeves ?? []);
  const idleMUSD = asNumber(composition.idleMUSD);
  const requiredBufferMUSD = asNumber(composition.liquidityBufferMUSD);
  const surplusMUSD = Math.max(0, asNumber(composition.deployableSurplusMUSD, idleMUSD - requiredBufferMUSD));
  const bufferShortfallMUSD = Math.max(0, requiredBufferMUSD - idleMUSD);
  const totalAllocatedMUSD = sleeves.reduce((sum, sleeve) => sum + sleeve.allocatedMUSD, 0);
  const riskState = health.belowCriticalRatio ? "critical" : health.belowWarningRatio ? "warning" : "healthy";
  const allocationCandidates = sleeves
    .filter((sleeve) => sleeve.approved && sleeve.remainingCapacityMUSD > 0)
    .sort(compareSleevesForAllocation);

  const automationAction = chooseAutomationAction({
    bufferShortfallMUSD,
    riskState,
    sleeves,
    requestedRepayMUSD: Math.min(totalAllocatedMUSD, asNumber(snapshot.position?.totalDebtMUSD)),
  });
  const allocationPlan = buildAllocationPlan(surplusMUSD, riskState, allocationCandidates);

  return {
    treasuryName: snapshot.treasuryName ?? "Mezo TreasuryOS Treasury",
    summary: {
      idleMUSD,
      requiredBufferMUSD,
      surplusMUSD,
      bufferShortfallMUSD,
      totalAllocatedMUSD,
      riskState,
    },
    sleeves,
    allocationPlan,
    automationAction,
    memo: buildMemo({ riskState, surplusMUSD, bufferShortfallMUSD, allocationPlan, automationAction, sleeves }),
    guardrails: [
      "Advisor output is reporting only and does not control funds.",
      "Every allocation still requires TreasuryPolicyEngine checks.",
      "Automation may only execute bounded restore/de-risk workflows already approved onchain.",
    ],
  };
}

export function formatAdvisorReport(report) {
  const lines = [];
  lines.push(`Treasury Advisor: ${report.treasuryName}`);
  lines.push("");
  lines.push(`Risk state: ${report.summary.riskState}`);
  lines.push(`Idle MUSD: ${formatMUSD(report.summary.idleMUSD)}`);
  lines.push(`Required buffer: ${formatMUSD(report.summary.requiredBufferMUSD)}`);
  lines.push(`Allocatable surplus: ${formatMUSD(report.summary.surplusMUSD)}`);
  lines.push(`Buffer shortfall: ${formatMUSD(report.summary.bufferShortfallMUSD)}`);
  lines.push("");
  lines.push("Sleeves:");

  for (const sleeve of report.sleeves) {
    lines.push(
      `- ${sleeve.label}: ${sleeve.status}, risk ${sleeve.riskTier}, ${formatMUSD(
        sleeve.allocatedMUSD,
      )} allocated, ${formatMUSD(sleeve.remainingCapacityMUSD)} capacity, ${formatBps(sleeve.annualYieldBps)} assumed APY`,
    );
  }

  lines.push("");
  lines.push("Recommended allocation plan:");
  if (report.allocationPlan.length === 0) {
    lines.push("- No new allocation recommended.");
  } else {
    for (const row of report.allocationPlan) {
      lines.push(
        `- ${row.label}: allocate ${formatMUSD(row.amountMUSD)}; projected 30d yield ${formatMUSD(
          row.projectedYieldMUSD["30d"],
        )}`,
      );
    }
  }

  lines.push("");
  lines.push(`Automation recommendation: ${report.automationAction.action}`);
  lines.push(report.automationAction.reason);
  lines.push("");
  lines.push("Advisor memo:");
  lines.push(report.memo);
  lines.push("");
  lines.push("Guardrails:");
  for (const guardrail of report.guardrails) lines.push(`- ${guardrail}`);

  return lines.join("\n");
}

function buildAllocationPlan(surplusMUSD, riskState, sleeves) {
  if (surplusMUSD <= 0 || riskState !== "healthy") return [];

  const plan = [];
  let remaining = surplusMUSD;

  for (const sleeve of sleeves) {
    if (remaining <= 0) break;
    const amount = Math.min(remaining, sleeve.remainingCapacityMUSD);
    if (amount <= 0) continue;

    plan.push({
      label: sleeve.label,
      destination: sleeve.destination,
      amountMUSD: amount,
      annualYieldBps: sleeve.annualYieldBps,
      projectedYieldMUSD: projectYield(amount, sleeve.annualYieldBps),
      reason: allocationReason(sleeve),
    });
    remaining -= amount;
  }

  return plan;
}

function chooseAutomationAction({ bufferShortfallMUSD, riskState, sleeves, requestedRepayMUSD }) {
  if (bufferShortfallMUSD > 0) {
    const source = bestAutomationSource(sleeves);
    if (!source) {
      return {
        action: "PREPARE_MANUAL_BUFFER_RESTORE",
        reason: "Buffer is below policy target, but no automation-eligible sleeve has withdrawable allocation.",
      };
    }

    return {
      action: "RESTORE_BUFFER_FROM_SLEEVE",
      destination: source.destination,
      sleeve: source.label,
      amountMUSD: Math.min(bufferShortfallMUSD, source.allocatedMUSD),
      reason: `${source.label} is automation-eligible and can restore the operating buffer within sleeve exposure.`,
    };
  }

  if (riskState === "critical" || riskState === "warning") {
    const source = bestAutomationSource(sleeves);
    if (!source) {
      return {
        action: "PREPARE_MANUAL_DE_RISK",
        reason: "Collateral health is weakening, but no automation-eligible sleeve can be unwound.",
      };
    }

    return {
      action: "PREPARE_DE_RISK_REPAYMENT",
      destination: source.destination,
      sleeve: source.label,
      amountMUSD: Math.min(requestedRepayMUSD, source.allocatedMUSD),
      reason: `${source.label} can be unwound to repay debt if the treasury admin or bounded executor approves.`,
    };
  }

  return {
    action: "NO_AUTOMATION_NEEDED",
    reason: "Buffer is funded and collateral health is not in warning or critical state.",
  };
}

function bestAutomationSource(sleeves) {
  return sleeves
    .filter((sleeve) => sleeve.automationEligible && sleeve.allocatedMUSD > 0 && sleeve.unwindDays <= 7)
    .sort((left, right) => left.unwindDays - right.unwindDays || right.allocatedMUSD - left.allocatedMUSD)[0] ?? null;
}

function buildMemo({ riskState, surplusMUSD, bufferShortfallMUSD, allocationPlan, automationAction, sleeves }) {
  if (riskState !== "healthy") {
    return "Collateral health is weakening. Do not allocate more surplus until the treasury reviews repayment or collateral actions.";
  }

  if (bufferShortfallMUSD > 0) {
    return `Idle MUSD is below the operating buffer by ${formatMUSD(bufferShortfallMUSD)}. ${automationAction.reason}`;
  }

  if (surplusMUSD <= 0) {
    return "Idle MUSD does not exceed the required buffer. Keep capital liquid and do not route new sleeve allocations.";
  }

  const pressured = sleeves.find((sleeve) => sleeve.capPressure >= 0.9);
  if (pressured) {
    return `${pressured.label} is near its sleeve cap. Prefer the allocation plan's remaining approved sleeves before increasing that cap.`;
  }

  if (allocationPlan.length === 0) {
    return "Surplus exists, but no approved sleeve has remaining capacity. Treasury admin should add or recap a destination before allocation.";
  }

  return `Idle MUSD exceeds buffer by ${formatMUSD(surplusMUSD)}. Allocate across approved sleeves according to caps and risk ranking.`;
}

function compareSleevesForAllocation(left, right) {
  const leftScore = allocationScore(left);
  const rightScore = allocationScore(right);
  return rightScore - leftScore || right.remainingCapacityMUSD - left.remainingCapacityMUSD;
}

function allocationScore(sleeve) {
  const riskScore = RISK_WEIGHT[sleeve.riskTier] ?? RISK_WEIGHT.medium;
  const capPenalty = sleeve.capPressure >= 0.9 ? 3 : sleeve.capPressure >= 0.75 ? 1 : 0;
  return sleeve.annualYieldBps / 100 + riskScore * 4 - capPenalty - sleeve.unwindDays / 10;
}

function allocationReason(sleeve) {
  if (sleeve.capPressure >= 0.75) return "approved but capacity-constrained";
  if (sleeve.riskTier === "low") return "lowest-risk approved sleeve with available cap";
  return "approved sleeve with available cap and higher yield assumption";
}

function normalizeSleeves(sleeves) {
  return sleeves.map((sleeve, index) => {
    const allocatedMUSD = asNumber(sleeve.allocatedMUSD);
    const capMUSD = asNumber(sleeve.capMUSD);
    const remainingCapacityMUSD = asNumber(
      sleeve.remainingCapacityMUSD,
      Math.max(0, capMUSD - allocatedMUSD),
    );
    const capPressure = capMUSD > 0 ? allocatedMUSD / capMUSD : 0;
    const approved = sleeve.approved ?? capMUSD > 0;
    const riskTier = String(sleeve.riskTier ?? "medium").toLowerCase();

    return {
      label: sleeve.label ?? `Sleeve ${index + 1}`,
      destination: sleeve.destination ?? null,
      status: approved ? "approved" : "not approved",
      approved,
      allocatedMUSD,
      capMUSD,
      remainingCapacityMUSD,
      capPressure,
      annualYieldBps: asNumber(sleeve.annualYieldBps),
      riskTier: RISK_WEIGHT[riskTier] ? riskTier : "medium",
      unwindDays: asNumber(sleeve.unwindDays, 1),
      automationEligible: Boolean(sleeve.automationEligible ?? true),
    };
  });
}

function projectYield(amountMUSD, annualYieldBps) {
  const result = {};
  for (const days of DAY_COUNT) {
    result[`${days}d`] = (amountMUSD * annualYieldBps * days) / 10_000 / 365;
  }
  return result;
}

function asNumber(value, fallback = 0) {
  const parsed = Number(value ?? fallback);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function formatMUSD(value) {
  return `${asNumber(value).toLocaleString("en-US", { maximumFractionDigits: 2 })} MUSD`;
}

function formatBps(value) {
  return `${(asNumber(value) / 100).toFixed(2)}%`;
}
