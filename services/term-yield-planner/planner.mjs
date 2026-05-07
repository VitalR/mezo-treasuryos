const DEFAULT_WINDOWS_DAYS = [7, 30, 60];
const DEFAULT_REVIEW_BUFFER_DAYS = 1;

const RISK_WEIGHT = {
  low: 3,
  medium: 2,
  high: 1,
};

export function buildTermYieldPlan(snapshot) {
  const plannerConfig = snapshot.termYieldPlanner ?? {};
  const asOfDate = parseDate(plannerConfig.asOfDate);
  const windowsDays = normalizeWindows(plannerConfig.windowsDays);
  const sleeves = normalizeSleeves(snapshot.sleeves ?? []);
  const btcSleeves = normalizeBTCSleeves(snapshot.btcSleeves ?? []);
  const health = snapshot.health ?? {};
  const composition = snapshot.composition ?? {};
  const idleMUSD = asNumber(composition.idleMUSD);
  const requiredBufferMUSD = asNumber(composition.liquidityBufferMUSD);
  const configuredSurplusMUSD = asNumber(composition.deployableSurplusMUSD, idleMUSD - requiredBufferMUSD);
  const plannedDisbursementsMUSD = asNumber(plannerConfig.plannedOperatingDisbursementsMUSD);
  const extraReserveMUSD = asNumber(plannerConfig.reserveAboveBufferMUSD);
  const allocatableMUSD = Math.max(0, configuredSurplusMUSD - plannedDisbursementsMUSD - extraReserveMUSD);
  const riskState = health.belowCriticalRatio ? "critical" : health.belowWarningRatio ? "warning" : "healthy";
  const blocked = allocationBlockReason({ riskState, idleMUSD, requiredBufferMUSD, allocatableMUSD });

  return {
    treasuryName: snapshot.treasuryName ?? "Mezo TreasuryOS Treasury",
    generatedAt: asOfDate.toISOString().slice(0, 10),
    posture: blocked ? "blocked" : "planning",
    inputs: {
      idleMUSD,
      requiredBufferMUSD,
      deployableSurplusMUSD: Math.max(0, configuredSurplusMUSD),
      plannedDisbursementsMUSD,
      reserveAboveBufferMUSD: extraReserveMUSD,
      allocatableMUSD,
      riskState,
    },
    plans: windowsDays.map((days) =>
      buildWindowPlan({
        days,
        asOfDate,
        allocatableMUSD,
        sleeves,
        blocked,
        reviewBufferDays: asNumber(plannerConfig.reviewBufferDays, DEFAULT_REVIEW_BUFFER_DAYS),
      }),
    ),
    btcPlanningNotes: buildBTCPlanningNotes(snapshot, btcSleeves),
    guardrails: [
      "Term Yield Planner is reporting-only and does not create a fixed-yield instrument.",
      "Only surplus MUSD above the operating buffer and planned disbursement reserve is considered allocatable.",
      "Every execution still goes through TreasuryPolicyEngine and the configured AllocationRouter handler.",
      "BTC sleeve candidates remain separate from MUSD operating-capital plans unless a verified BTC execution path exists.",
    ],
  };
}

export function formatTermYieldPlan(plan) {
  const lines = [];

  lines.push(`Term Yield Planner: ${plan.treasuryName}`);
  lines.push(`As of: ${plan.generatedAt}`);
  lines.push("");
  lines.push(`Posture: ${plan.posture}`);
  lines.push(`Idle MUSD: ${formatMUSD(plan.inputs.idleMUSD)}`);
  lines.push(`Required buffer: ${formatMUSD(plan.inputs.requiredBufferMUSD)}`);
  lines.push(`Planned operating disbursements: ${formatMUSD(plan.inputs.plannedDisbursementsMUSD)}`);
  lines.push(`Reserve above buffer: ${formatMUSD(plan.inputs.reserveAboveBufferMUSD)}`);
  lines.push(`Allocatable for term plans: ${formatMUSD(plan.inputs.allocatableMUSD)}`);
  lines.push(`Risk state: ${plan.inputs.riskState}`);

  for (const windowPlan of plan.plans) {
    lines.push("");
    lines.push(`${windowPlan.termDays}-day plan`);
    lines.push(`Review date: ${windowPlan.reviewDate}`);
    lines.push(`Projected yield: ${formatMUSD(windowPlan.projectedYieldMUSD)}`);

    if (windowPlan.blockedReason) {
      lines.push(`Status: BLOCKED - ${windowPlan.blockedReason}`);
    } else if (windowPlan.allocations.length === 0) {
      lines.push("Status: no approved capacity fits this term window.");
    } else {
      lines.push("Allocations:");
      for (const allocation of windowPlan.allocations) {
        lines.push(
          `- ${allocation.label}: ${formatMUSD(allocation.amountMUSD)}, ${formatBps(
            allocation.annualYieldBps,
          )} assumed APY, review ${allocation.reviewDate}, unwind ${allocation.unwindDays}d`,
        );
      }
    }

    lines.push("Unwind conditions:");
    for (const condition of windowPlan.unwindConditions) lines.push(`- ${condition}`);
  }

  if (plan.btcPlanningNotes.length > 0) {
    lines.push("");
    lines.push("BTC planning notes:");
    for (const note of plan.btcPlanningNotes) lines.push(`- ${note}`);
  }

  lines.push("");
  lines.push("Guardrails:");
  for (const guardrail of plan.guardrails) lines.push(`- ${guardrail}`);

  return lines.join("\n");
}

function buildWindowPlan({ days, asOfDate, allocatableMUSD, sleeves, blocked, reviewBufferDays }) {
  const reviewDate = addDays(asOfDate, Math.max(1, days - reviewBufferDays));

  if (blocked) {
    return {
      termDays: days,
      reviewDate,
      allocatableMUSD: 0,
      projectedYieldMUSD: 0,
      blockedReason: blocked,
      allocations: [],
      unwindConditions: defaultUnwindConditions(days),
    };
  }

  let remaining = allocatableMUSD;
  const allocations = [];
  const candidates = sleeves
    .filter((sleeve) => sleeve.approved && sleeve.remainingCapacityMUSD > 0 && sleeve.unwindDays <= days)
    .sort((left, right) => windowScore(right, days) - windowScore(left, days));

  for (const sleeve of candidates) {
    if (remaining <= 0) break;

    const amountMUSD = Math.min(remaining, sleeve.remainingCapacityMUSD, sleeve.termCapMUSD || Number.MAX_SAFE_INTEGER);
    if (amountMUSD <= 0) continue;

    allocations.push({
      label: sleeve.label,
      destination: sleeve.destination,
      amountMUSD,
      annualYieldBps: sleeve.annualYieldBps,
      projectedYieldMUSD: projectYield(amountMUSD, sleeve.annualYieldBps, days),
      reviewDate,
      maturityDate: addDays(asOfDate, days),
      unwindDays: sleeve.unwindDays,
      riskTier: sleeve.riskTier,
      reason: allocationReason(sleeve, days),
    });
    remaining -= amountMUSD;
  }

  return {
    termDays: days,
    reviewDate,
    allocatableMUSD,
    projectedYieldMUSD: allocations.reduce((sum, allocation) => sum + allocation.projectedYieldMUSD, 0),
    blockedReason: null,
    allocations,
    unallocatedMUSD: remaining,
    unwindConditions: buildUnwindConditions(days, allocations),
  };
}

function allocationBlockReason({ riskState, idleMUSD, requiredBufferMUSD, allocatableMUSD }) {
  if (riskState === "critical") return "collateral health is critical; prepare repayment or collateral action";
  if (riskState === "warning") return "collateral health is in warning state; pause new yield allocation";
  if (idleMUSD < requiredBufferMUSD) return "idle MUSD is below the required operating buffer";
  if (allocatableMUSD <= 0) return "no MUSD remains after buffer, planned disbursements, and reserve constraints";
  return null;
}

function buildUnwindConditions(days, allocations) {
  const conditions = defaultUnwindConditions(days);
  const slowestUnwind = allocations.reduce((max, allocation) => Math.max(max, allocation.unwindDays), 0);

  if (slowestUnwind > 0) {
    conditions.push(`Start unwind at least ${slowestUnwind} day(s) before the review date if operating cash is needed.`);
  }

  if (allocations.some((allocation) => allocation.riskTier !== "low")) {
    conditions.push("Escalate review if stable-pool liquidity, slippage, or cap pressure deteriorates.");
  }

  return conditions;
}

function defaultUnwindConditions(days) {
  return [
    "Unwind if idle MUSD would fall below the operating buffer.",
    "Unwind or pause if collateral health drops below the warning threshold.",
    `Review no later than the ${days}-day planning window end.`,
  ];
}

function buildBTCPlanningNotes(snapshot, btcSleeves) {
  const buckets = snapshot.btcReserveBuckets ?? {};
  const notes = [];
  const idleBTC = asNumber(buckets.idleBTCReserve, asNumber(snapshot.composition?.idleBTC));
  const collateralBTC = asNumber(buckets.collateralBTC, asNumber(snapshot.position?.collateralBTC));
  const emergencyBTCReserve = asNumber(buckets.emergencyBTCReserve);
  const yieldActiveBTC = asNumber(buckets.yieldActiveBTC);

  if (idleBTC > 0) {
    notes.push(`${formatBTC(idleBTC)} of idle BTC reserve is not part of MUSD term-yield allocatable surplus.`);
  }

  if (collateralBTC > 0) {
    notes.push(`${formatBTC(collateralBTC)} of BTC collateral remains governed by collateral-health policy first.`);
  }

  if (emergencyBTCReserve > 0) {
    notes.push(`${formatBTC(emergencyBTCReserve)} of emergency BTC reserve should stay outside yield planning.`);
  }

  if (yieldActiveBTC > 0) {
    notes.push(`${formatBTC(yieldActiveBTC)} BTC is already yield-active; keep it in separate BTC-denominated reporting.`);
  }

  for (const sleeve of btcSleeves) {
    if (sleeve.executable && sleeve.approved) {
      notes.push(`${sleeve.label} is executable in this snapshot but still requires BTC-specific policy approval.`);
    } else if (sleeve.riskClass.includes("correlated")) {
      notes.push(`${sleeve.label} is a BTC-correlated candidate, not a V1 MUSD operating-capital sleeve.`);
    } else if (sleeve.riskClass.includes("directional") || sleeve.riskClass.includes("stable")) {
      notes.push(`${sleeve.label} is directional BTC/stable exposure and should require elevated approval.`);
    } else if (sleeve.riskClass.includes("speculative")) {
      notes.push(`${sleeve.label} is speculative and should remain disabled by default.`);
    }
  }

  return notes;
}

function normalizeSleeves(sleeves) {
  return sleeves.map((sleeve, index) => {
    const allocatedMUSD = asNumber(sleeve.allocatedMUSD);
    const capMUSD = asNumber(sleeve.capMUSD);
    const remainingCapacityMUSD = asNumber(sleeve.remainingCapacityMUSD, Math.max(0, capMUSD - allocatedMUSD));
    const riskTier = String(sleeve.riskTier ?? "medium").toLowerCase();

    return {
      label: sleeve.label ?? `Sleeve ${index + 1}`,
      destination: sleeve.destination ?? null,
      approved: Boolean(sleeve.approved ?? capMUSD > 0),
      allocatedMUSD,
      capMUSD,
      remainingCapacityMUSD,
      termCapMUSD: asNumber(sleeve.termCapMUSD),
      annualYieldBps: asNumber(sleeve.annualYieldBps),
      riskTier: RISK_WEIGHT[riskTier] ? riskTier : "medium",
      unwindDays: asNumber(sleeve.unwindDays, 1),
    };
  });
}

function normalizeBTCSleeves(sleeves) {
  return sleeves.map((sleeve, index) => ({
    label: sleeve.label ?? `BTC sleeve ${index + 1}`,
    approved: Boolean(sleeve.approved),
    executable: Boolean(sleeve.executable),
    riskClass: String(sleeve.riskClass ?? "btc-denominated").toLowerCase(),
  }));
}

function normalizeWindows(windows) {
  if (!Array.isArray(windows) || windows.length === 0) return DEFAULT_WINDOWS_DAYS;

  const values = windows.map((value) => Number(value)).filter((value) => Number.isInteger(value) && value > 0);
  return values.length > 0 ? [...new Set(values)].sort((left, right) => left - right) : DEFAULT_WINDOWS_DAYS;
}

function windowScore(sleeve, days) {
  const riskScore = RISK_WEIGHT[sleeve.riskTier] ?? RISK_WEIGHT.medium;
  const shortWindowBonus = days <= 7 && sleeve.unwindDays <= 1 ? 8 : 0;
  const lowRiskBonus = sleeve.riskTier === "low" ? (days <= 7 ? 6 : 2) : 0;
  const yieldWeight = days <= 7 ? 1 : 2;
  return (sleeve.annualYieldBps / 100) * yieldWeight + riskScore * 2 + lowRiskBonus + shortWindowBonus
    - sleeve.unwindDays / 5;
}

function allocationReason(sleeve, days) {
  if (days <= 7 && sleeve.unwindDays <= 1) return "fast unwind sleeve suitable for short operating window";
  if (sleeve.riskTier === "low") return "conservative sleeve with available policy capacity";
  return "approved sleeve fits this term window and remaining capacity";
}

function projectYield(amountMUSD, annualYieldBps, days) {
  return (amountMUSD * annualYieldBps * days) / 10_000 / 365;
}

function parseDate(value) {
  if (value) {
    const parsed = new Date(`${value}T00:00:00.000Z`);
    if (!Number.isNaN(parsed.valueOf())) return parsed;
  }

  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
}

function addDays(date, days) {
  const next = new Date(date.valueOf());
  next.setUTCDate(next.getUTCDate() + days);
  return next.toISOString().slice(0, 10);
}

function asNumber(value, fallback = 0) {
  const parsed = Number(value ?? fallback);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function formatMUSD(value) {
  return `${asNumber(value).toLocaleString("en-US", { maximumFractionDigits: 2 })} MUSD`;
}

function formatBTC(value) {
  return `${asNumber(value).toLocaleString("en-US", { maximumFractionDigits: 8 })} BTC`;
}

function formatBps(value) {
  return `${(asNumber(value) / 100).toFixed(2)}%`;
}
