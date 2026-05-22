import { createHash } from "node:crypto";

const DAY_COUNT = [7, 30, 60];

const RISK_WEIGHT = {
  low: 3,
  medium: 2,
  high: 1,
};

const TREASURY_PROFILES = {
  conservative: {
    label: "Conservative Treasury",
    stableLpWeight: -8,
    savingsWeight: 10,
    maxStableLpShareBps: 1000,
    btcYieldEnabled: false,
    memo: "Prioritize collateral safety, operating liquidity, and MUSD Savings. Stable LP and BTC sleeves are review-only.",
  },
  balanced: {
    label: "Balanced Treasury",
    stableLpWeight: 0,
    savingsWeight: 6,
    maxStableLpShareBps: 2500,
    btcYieldEnabled: false,
    memo: "Use MUSD Savings as the default sleeve, with limited stable LP only when liquidity and policy are healthy.",
  },
  active: {
    label: "Active Treasury",
    stableLpWeight: 6,
    savingsWeight: 3,
    maxStableLpShareBps: 4000,
    btcYieldEnabled: false,
    memo: "Accept more stablecoin sleeve exposure when the position is healthy, while keeping BTC principal movement gated.",
  },
  "aggressive-demo": {
    label: "Aggressive Demo Treasury",
    stableLpWeight: 12,
    savingsWeight: 0,
    maxStableLpShareBps: 6000,
    btcYieldEnabled: true,
    demoOnly: true,
    memo: "Demonstrates higher-risk routing logic for judges. Not a default institutional treasury posture.",
  },
};

export function buildTreasuryAdvisorReport(snapshot, options = {}) {
  const composition = snapshot.composition ?? {};
  const health = snapshot.health ?? {};
  const profile = resolveProfile(options.profileName ?? snapshot.riskKeeper?.strategyProfile ?? snapshot.strategyProfile);
  const sleeves = normalizeSleeves(snapshot.sleeves ?? []);
  const btcSleeves = normalizeBTCSleeves(snapshot.btcSleeves ?? []);
  const btcSleevePlan = snapshot.btcSleevePlan ?? null;
  const opportunities = normalizeOpportunities(options.opportunities ?? snapshot.opportunities);
  const idleMUSD = asNumber(composition.idleMUSD);
  const requiredBufferMUSD = asNumber(composition.liquidityBufferMUSD);
  const surplusMUSD = Math.max(0, asNumber(composition.deployableSurplusMUSD, idleMUSD - requiredBufferMUSD));
  const bufferShortfallMUSD = Math.max(0, requiredBufferMUSD - idleMUSD);
  const totalAllocatedMUSD = sleeves.reduce((sum, sleeve) => sum + sleeve.allocatedMUSD, 0);
  const btc = normalizeBTC(snapshot, btcSleeves);
  const riskState = health.belowCriticalRatio ? "critical" : health.belowWarningRatio ? "warning" : "healthy";
  const allocationCandidates = sleeves
    .filter((sleeve) => sleeve.approved && sleeve.remainingCapacityMUSD > 0)
    .sort((left, right) => compareSleevesForAllocation(left, right, profile));

  const automationAction = chooseAutomationAction({
    bufferShortfallMUSD,
    riskState,
    sleeves,
    requestedRepayMUSD: Math.min(totalAllocatedMUSD, asNumber(snapshot.position?.totalDebtMUSD)),
  });
  const allocationPlan = buildAllocationPlan(surplusMUSD, riskState, allocationCandidates, profile);
  const opportunityReview = buildOpportunityReview({
    sleeves,
    btcSleeves,
    btcSleevePlan,
    opportunities,
    profile,
    riskState,
    surplusMUSD,
  });

  const report = {
    treasuryName: snapshot.treasuryName ?? "Mezo TreasuryOS Treasury",
    treasuryAccount: snapshot.treasuryAccount ?? null,
    profile,
    summary: {
      idleMUSD,
      requiredBufferMUSD,
      surplusMUSD,
      bufferShortfallMUSD,
      totalAllocatedMUSD,
      riskState,
    },
    btc,
    sleeves,
    btcSleeves,
    btcSleevePlan,
    opportunities,
    opportunityReview,
    allocationPlan,
    automationAction,
    memo: buildMemo({ riskState, surplusMUSD, bufferShortfallMUSD, allocationPlan, automationAction, sleeves, profile }),
    btcMemo: buildBTCMemo({ btc, btcSleeves, btcSleevePlan, riskState }),
    guardrails: [
      "Advisor output is reporting only and does not control funds.",
      "Every allocation still requires TreasuryPolicyEngine checks.",
      "BTC-denominated sleeve recommendations are reporting-only until a guarded BTC execution handler is deployed and broadcast-validated for the treasury.",
      "Automation may only execute bounded restore/de-risk workflows already approved onchain.",
    ],
  };

  report.cfoPacket = buildCfoPacket(report, snapshot);
  return report;
}

export function formatAdvisorReport(report) {
  const lines = [];
  lines.push(`Treasury Advisor: ${report.treasuryName}`);
  lines.push("");
  lines.push(`Treasury profile: ${report.profile.label}${report.profile.demoOnly ? " (demo-only)" : ""}`);
  lines.push(`Profile memo: ${report.profile.memo}`);
  lines.push("");
  lines.push(`Risk state: ${report.summary.riskState}`);
  lines.push(`Idle MUSD: ${formatMUSD(report.summary.idleMUSD)}`);
  lines.push(`Required buffer: ${formatMUSD(report.summary.requiredBufferMUSD)}`);
  lines.push(`Allocatable surplus: ${formatMUSD(report.summary.surplusMUSD)}`);
  lines.push(`Buffer shortfall: ${formatMUSD(report.summary.bufferShortfallMUSD)}`);
  lines.push("");
  lines.push("BTC reserve view:");
  lines.push(`Idle BTC reserve: ${formatBTC(report.btc.idleBTC)}`);
  lines.push(`BTC collateral: ${formatBTC(report.btc.collateralBTC)}`);
  lines.push(`Emergency BTC reserve: ${formatBTC(report.btc.emergencyBTCReserve)}`);
  lines.push(`BTC yield-active exposure: ${formatBTC(report.btc.yieldActiveBTC)}`);
  lines.push(`Pending BTC sleeve withdrawals: ${formatBTC(report.btc.pendingWithdrawBTC)}`);
  lines.push(`BTC accounted: ${formatBTC(report.btc.totalAccountedBTC)}`);
  if (report.btc.minIdleReserveBTC > 0) {
    lines.push(`Minimum idle BTC reserve: ${formatBTC(report.btc.minIdleReserveBTC)}`);
    lines.push(`Idle BTC reserve surplus: ${formatBTC(report.btc.surplusReserveBTC)}`);
    lines.push(`Idle BTC reserve shortfall: ${formatBTC(report.btc.reserveShortfallBTC)}`);
  }
  lines.push("");
  lines.push("Sleeves:");

  for (const sleeve of report.sleeves) {
    lines.push(
      `- ${sleeve.label}: ${sleeve.status}, risk ${sleeve.riskTier}, ${formatMUSD(
        sleeve.allocatedMUSD,
      )} allocated, ${formatMUSD(sleeve.remainingCapacityMUSD)} capacity, ${formatBps(sleeve.annualYieldBps)} assumed APY`,
    );
  }

  if (report.btcSleeves.length > 0) {
    lines.push("");
    lines.push("BTC sleeve candidates:");
    for (const sleeve of report.btcSleeves) {
      lines.push(
        `- ${sleeve.label}: ${sleeve.status}, ${formatBTC(sleeve.allocatedBTC)} allocated, ${
          sleeve.executable ? "execution path live" : "reporting only"
        }, risk ${sleeve.riskClass}, approval ${sleeve.approvalLevel}, price impact ${formatBps(
          sleeve.swapPriceImpactBps,
        )}, slippage ${formatBps(sleeve.slippageBps)}, ${sleeve.withdrawalConstraint}`,
      );
    }
  }

  if (report.btcSleevePlan) {
    lines.push("");
    lines.push(
      `BTC sleeve plan: ${report.btcSleevePlan.policy?.allowed ? "ALLOW" : "BLOCK"} (${
        report.btcSleevePlan.policy?.reason ?? "unknown"
      }) for ${formatBTC(report.btcSleevePlan.requestedPrincipalBTC)} into ${
        report.btcSleevePlan.candidate?.label ?? "BTC sleeve"
      }`,
    );
  }

  lines.push("");
  lines.push("Opportunity review:");
  if (report.opportunityReview.length === 0) {
    lines.push("- No external opportunity metadata was provided; using configured sleeves only.");
  } else {
    for (const opportunity of report.opportunityReview) {
      lines.push(`- ${opportunity.label}: ${opportunity.decision} - ${opportunity.reason}`);
    }
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
  lines.push("BTC memo:");
  lines.push(report.btcMemo);
  lines.push("");
  lines.push("Guardrails:");
  for (const guardrail of report.guardrails) lines.push(`- ${guardrail}`);

  return lines.join("\n");
}

export function formatCfoPacket(packet) {
  const lines = [];
  lines.push(`AI-CFO packet: ${packet.recommendationId}`);
  lines.push(`Mode: ${packet.mode}`);
  lines.push(`Treasury account: ${packet.treasuryAccount ?? "unknown"}`);
  lines.push(`Profile: ${packet.profile}`);
  lines.push(`Source of truth: ${packet.sourceOfTruth}`);
  lines.push("");
  lines.push("Prepared actions:");

  if (packet.preparedActions.length === 0) {
    lines.push("- No transaction proposal prepared.");
  } else {
    for (const action of packet.preparedActions) {
      lines.push(`- ${action.type}: ${action.status}`);
      lines.push(`  Target: ${action.target}`);
      lines.push(`  Value: ${action.value}`);
      lines.push(`  Signature: ${action.signature}`);
      lines.push(`  Args: ${action.args.join(", ")}`);
      lines.push(`  Human amount: ${action.humanAmount}`);
      lines.push(`  Approval path: ${action.approvalPath}`);
      lines.push(`  Reason: ${action.reason}`);
      lines.push(`  Calldata helper: ${action.castCalldataCommand}`);
    }
  }

  lines.push("");
  lines.push("Blocked or watch-only opportunities:");
  if (packet.blockedOpportunities.length === 0) {
    lines.push("- None.");
  } else {
    for (const opportunity of packet.blockedOpportunities) {
      lines.push(`- ${opportunity.label}: ${opportunity.decision} - ${opportunity.reason}`);
    }
  }

  lines.push("");
  lines.push("Execution boundary:");
  for (const boundary of packet.executionBoundary) lines.push(`- ${boundary}`);
  return lines.join("\n");
}

function buildCfoPacket(report, snapshot) {
  const preparedActions = [
    ...buildAllocationProposalActions(report, snapshot),
    ...buildAutomationProposalActions(report),
  ];
  const blockedOpportunities = report.opportunityReview.filter((opportunity) =>
    ["BLOCK_FOR_NOW", "WATCH_ONLY", "CONFIGURE_BEFORE_USE"].includes(opportunity.decision),
  );
  const recommendationPayload = {
    treasuryName: report.treasuryName,
    treasuryAccount: report.treasuryAccount,
    profile: report.profile.key,
    summary: report.summary,
    allocationPlan: report.allocationPlan.map((row) => ({
      destination: row.destination,
      amountMUSD: row.amountMUSD,
    })),
    automationAction: report.automationAction.action,
    blockedOpportunities,
  };

  return {
    recommendationId: `cfo-${createHash("sha256")
      .update(JSON.stringify(recommendationPayload))
      .digest("hex")
      .slice(0, 16)}`,
    mode: "advisory_proposal",
    treasuryName: report.treasuryName,
    treasuryAccount: report.treasuryAccount,
    profile: report.profile.key,
    sourceOfTruth: "deterministic advisor report plus onchain TreasuryOS policy checks",
    preparedActions,
    blockedOpportunities,
    executionBoundary: [
      "AI-CFO does not sign, custody, broadcast, or bypass policy.",
      "Prepared owner actions must be executed by the TreasuryAccount owner, TreasuryMultisig, Safe, or external custody path.",
      "Keeper actions must go through TreasuryAutomationExecutor and remain capped, allowlisted, and policy-checked.",
      "BTC principal movement stays proposal-only unless the guarded BTC handler path is validated for the treasury.",
    ],
  };
}

function buildAllocationProposalActions(report, snapshot) {
  if (!report.treasuryAccount || report.allocationPlan.length === 0) return [];

  const approvalThresholdMUSD = asNumber(snapshot.composition?.approvalThresholdMUSD);
  return report.allocationPlan
    .filter((row) => row.destination)
    .map((row) => {
      const amountUnits = decimalToUnits(row.amountMUSD);
      const approvalPath = approvalThresholdMUSD > 0 && row.amountMUSD <= approvalThresholdMUSD
        ? "TreasuryAccount policy-approved actor; multisig remains acceptable"
        : "treasury owner or multisig approval";
      return {
        type: "ALLOCATE_SURPLUS_MUSD",
        status: "prepared_not_executed",
        target: report.treasuryAccount,
        value: "0",
        signature: "allocate(address,uint256)",
        args: [row.destination, amountUnits],
        humanAmount: formatMUSD(row.amountMUSD),
        approvalPath,
        reason: row.reason,
        castCalldataCommand: buildCastCalldataCommand("allocate(address,uint256)", [row.destination, amountUnits]),
      };
    });
}

function buildAutomationProposalActions(report) {
  const action = report.automationAction;
  if (!action || action.action === "NO_AUTOMATION_NEEDED") return [];

  return [
    {
      type: action.action,
      status: "handoff_to_risk_keeper_proposal",
      target: "TreasuryAutomationExecutor",
      value: "0",
      signature: "see risk keeper proposal mode",
      args: [],
      humanAmount: action.amountMUSD == null ? "n/a" : formatMUSD(action.amountMUSD),
      approvalPath: "allowlisted keeper or multisig proposal through TreasuryAutomationExecutor",
      reason: action.reason,
      castCalldataCommand: "RISK_KEEPER_MODE=propose npm run risk-keeper:demo",
    },
  ];
}

function buildAllocationPlan(surplusMUSD, riskState, sleeves, profile) {
  if (surplusMUSD <= 0 || riskState !== "healthy") return [];

  const plan = [];
  let remaining = surplusMUSD;
  const stableLpBudget = surplusMUSD * profile.maxStableLpShareBps / 10_000;
  let stableLpAllocated = 0;

  for (const sleeve of sleeves) {
    if (remaining <= 0) break;
    const sleeveBudget = isStableLp(sleeve) ? Math.max(0, stableLpBudget - stableLpAllocated) : remaining;
    const amount = Math.min(remaining, sleeve.remainingCapacityMUSD, sleeveBudget);
    if (amount <= 0) continue;

    plan.push({
      label: sleeve.label,
      destination: sleeve.destination,
      amountMUSD: amount,
      annualYieldBps: sleeve.annualYieldBps,
      projectedYieldMUSD: projectYield(amount, sleeve.annualYieldBps),
      reason: allocationReason(sleeve, profile),
    });
    remaining -= amount;
    if (isStableLp(sleeve)) stableLpAllocated += amount;
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

function buildMemo({ riskState, surplusMUSD, bufferShortfallMUSD, allocationPlan, automationAction, sleeves, profile }) {
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

  const savings = sleeves.find((sleeve) => /savings|vault/i.test(sleeve.label));
  const stableLp = sleeves.find((sleeve) => /musdc|stable/i.test(sleeve.label));
  const sleeveNotes = [];

  if (savings) sleeveNotes.push(`${savings.label} is the primary conservative MUSD sleeve`);
  if (stableLp) sleeveNotes.push(`${stableLp.label} is optional stablecoin LP capacity within policy caps`);

  const suffix = sleeveNotes.length > 0 ? ` ${sleeveNotes.join("; ")}.` : "";

  return `${profile.label}: idle MUSD exceeds buffer by ${formatMUSD(
    surplusMUSD,
  )}. Allocate across approved sleeves according to caps and risk ranking.${suffix}`;
}

function buildBTCMemo({ btc, btcSleeves, btcSleevePlan, riskState }) {
  const notes = [];

  if (btc.totalAccountedBTC <= 0 && btcSleeves.length === 0) {
    return "No BTC reserve or BTC-denominated sleeve data is present in this snapshot.";
  }

  if (btc.collateralBTC > 0) {
    notes.push(
      `Keep ${formatBTC(btc.collateralBTC)} of BTC collateral governed by collateral-health policy before chasing yield.`,
    );
  }

  if (btc.idleBTC > 0) {
    notes.push(
      `Keep idle BTC reserve accounting separate from MUSD surplus allocation; MUSD sleeve capacity does not make BTC reserve allocatable.`,
    );
  }

  if (btc.reserveShortfallBTC > 0) {
    notes.push(`Idle BTC reserve is below target by ${formatBTC(btc.reserveShortfallBTC)}.`);
  }

  if (btc.emergencyBTCReserve > 0) {
    notes.push(`${formatBTC(btc.emergencyBTCReserve)} is tagged as emergency BTC reserve and should not be allocated.`);
  }

  if (btc.yieldActiveBTC > 0 || btc.pendingWithdrawBTC > 0) {
    notes.push(
      `BTC yield accounting shows ${formatBTC(btc.yieldActiveBTC)} active and ${formatBTC(
        btc.pendingWithdrawBTC,
      )} pending withdrawal; do not treat pending withdrawals as available reserve.`,
    );
  }

  if (riskState !== "healthy") {
    notes.push("Collateral health is not healthy, so BTC yield deployment should be paused or escalated.");
  }

  if (btcSleevePlan) {
    const allowed = Boolean(btcSleevePlan.policy?.allowed);
    const reason = btcSleevePlan.policy?.reason ?? "unknown";
    const approval = btcSleevePlan.policy?.requiredApprovalLevel ?? btcSleevePlan.candidate?.approvalLevel ?? "MULTISIG";
    const principal = btcSleevePlan.requestedPrincipalBTC ?? "0";
    notes.push(
      `BTC sleeve planner proposes ${formatBTC(principal)} from idle BTC into ${
        btcSleevePlan.candidate?.label ?? "the BTC-correlated sleeve"
      }; policy ${allowed ? "allows" : "blocks"} it with reason ${reason} and approval ${approval}.`,
    );

    if (!allowed && reason === "SwapPriceImpactExceeded") {
      notes.push(
        "The mcbBTC/BTC candidate is BTC-correlated, but current liquidity creates excessive entry price impact.",
      );
      notes.push(
        "TreasuryOS blocks BTC principal movement under policy; recommended action is to keep BTC idle, preserve collateral defense, and wait for deeper liquidity or a lower-impact route.",
      );
    } else if (!allowed) {
      notes.push("TreasuryOS keeps this BTC sleeve as a planning memo until the policy block is resolved.");
    } else {
      notes.push(
        "Treat the allowed BTC sleeve plan as a multisig proposal preview until V1.5 guarded execution has controlled broadcast validation.",
      );
    }
  }

  const executable = btcSleeves.filter((sleeve) => sleeve.executable && sleeve.approved);
  if (executable.length === 0) {
    notes.push(
      "No approved BTC-denominated sleeve has a live execution path in this V1 snapshot; treat BTC sleeve ideas as policy previews and planning inputs only.",
    );
  }

  const directional = btcSleeves.find(
    (sleeve) => sleeve.riskClass.includes("stable") || sleeve.riskClass.includes("directional"),
  );
  if (directional) {
    notes.push(
      `${directional.label} changes pure BTC exposure and should require higher approval than BTC-correlated or wrapper-BTC sleeves.`,
    );
  }

  const wrapperCandidate = btcSleeves.find((sleeve) => sleeve.riskClass.includes("correlated"));
  if (wrapperCandidate) {
    notes.push(
      `${wrapperCandidate.label} is the cleaner Bitcoin-yield direction because it preserves BTC-denominated exposure better than BTC/stable LP.`,
    );
    if (wrapperCandidate.swapPriceImpactBps > 0) {
      notes.push(
        `Its configured entry price impact is ${formatBps(
          wrapperCandidate.swapPriceImpactBps,
        )}, so large allocations should be blocked or escalated until liquidity improves.`,
      );
    }
    if (wrapperCandidate.approvalLevel && !/multisig/i.test(wrapperCandidate.approvalLevel)) {
      notes.push("BTC principal movement should require multisig approval, not operator-only automation.");
    }
  }

  return notes.join(" ");
}

function buildOpportunityReview({ sleeves, btcSleeves, btcSleevePlan, opportunities, profile, riskState, surplusMUSD }) {
  const reviews = [];

  for (const opportunity of opportunities) {
    if (opportunity.kind === "musd-savings") {
      const sleeve = sleeves.find((candidate) => /savings|vault/i.test(candidate.label));
      reviews.push({
        label: opportunity.label,
        decision: sleeve?.approved ? "USE_AS_PRIMARY_MUSD_SLEEVE" : "CONFIGURE_BEFORE_USE",
        reason: sleeve?.approved
          ? `${profile.label} can use this as the default idle-MUSD sleeve; capacity ${formatMUSD(sleeve.remainingCapacityMUSD)}.`
          : "Savings vault exists, but it is not approved in the current TreasuryAccount policy snapshot.",
      });
      continue;
    }

    if (opportunity.kind === "stable-lp") {
      const sleeve = sleeves.find((candidate) => /musdc|stable|lp/i.test(candidate.label));
      const healthy = riskState === "healthy" && surplusMUSD > 0;
      const profileAllows = profile.maxStableLpShareBps > 0;
      const decision = sleeve?.approved && healthy && profileAllows ? "OPTIONAL_LIMITED_ALLOCATION" : "WATCH_ONLY";
      reviews.push({
        label: opportunity.label,
        decision,
        reason: decision === "OPTIONAL_LIMITED_ALLOCATION"
          ? `${profile.label} may allocate a limited share to stable LP after route/liquidity checks; cap share ${formatBps(profile.maxStableLpShareBps)}.`
          : "Do not allocate unless collateral health is healthy, surplus exists, and the destination is approved with route liquidity validated.",
      });
      continue;
    }

    if (opportunity.kind === "btc-correlated") {
      const sleeve = btcSleeves.find((candidate) => /mcbbtc|btc/i.test(candidate.label));
      const planBlocked = btcSleevePlan && !btcSleevePlan.policy?.allowed;
      const hasQuoteImpact = opportunity.priceImpactBps != null;
      const shallow = hasQuoteImpact && opportunity.priceImpactBps >= 500;
      const noExecution = !sleeve?.executable && !opportunity.executionValidated;
      const decision = profile.btcYieldEnabled && !planBlocked && !shallow && !noExecution
        ? "MULTISIG_PREVIEW_ONLY"
        : "BLOCK_FOR_NOW";
      const blockers = [];
      if (opportunity.quoteError) blockers.push(`live quote failed: ${opportunity.quoteError}`);
      if (shallow) blockers.push(describeShallowBTCLiquidity(opportunity));
      if (planBlocked) blockers.push(`BTC policy blocks with ${btcSleevePlan.policy?.reason ?? "unknown"}`);
      if (noExecution) blockers.push("main demo treasury has no validated live BTC sleeve execution path");
      reviews.push({
        label: opportunity.label,
        decision,
        reason: blockers.length > 0
          ? `Do not use for current testnet execution: ${blockers.join("; ")}. Keep as guarded Bitcoin-yield research.`
          : "BTC-correlated sleeve can be prepared as a multisig preview, but should not be keeper-executed.",
      });
    }
  }

  return reviews;
}

function compareSleevesForAllocation(left, right, profile) {
  const leftScore = allocationScore(left, profile);
  const rightScore = allocationScore(right, profile);
  return rightScore - leftScore || right.remainingCapacityMUSD - left.remainingCapacityMUSD;
}

function allocationScore(sleeve, profile) {
  const riskScore = RISK_WEIGHT[sleeve.riskTier] ?? RISK_WEIGHT.medium;
  const capPenalty = sleeve.capPressure >= 0.9 ? 3 : sleeve.capPressure >= 0.75 ? 1 : 0;
  const savingsBonus = /savings|vault/i.test(sleeve.label) ? profile.savingsWeight : 0;
  const stableLpBonus = isStableLp(sleeve) ? profile.stableLpWeight : 0;
  return sleeve.annualYieldBps / 100 + riskScore * 4 + savingsBonus + stableLpBonus - capPenalty - sleeve.unwindDays / 10;
}

function allocationReason(sleeve, profile) {
  if (sleeve.capPressure >= 0.75) return "approved but capacity-constrained";
  if (sleeve.riskTier === "low") return `${profile.label} prefers this low-risk approved sleeve`;
  if (isStableLp(sleeve)) return `${profile.label} allows limited stable LP exposure when route health is acceptable`;
  return "approved sleeve with available cap and higher yield assumption";
}

function isStableLp(sleeve) {
  return /musdc|musdt|stable|lp/i.test(sleeve.label) && !/savings|vault/i.test(sleeve.label);
}

function resolveProfile(name) {
  const key = String(name ?? "balanced").toLowerCase();
  return {
    key: TREASURY_PROFILES[key] ? key : "balanced",
    ...(TREASURY_PROFILES[key] ?? TREASURY_PROFILES.balanced),
  };
}

function normalizeOpportunities(opportunities) {
  if (Array.isArray(opportunities)) return opportunities.map(normalizeOpportunity);
  if (Array.isArray(opportunities?.items)) return opportunities.items.map(normalizeOpportunity);
  return [];
}

function normalizeOpportunity(opportunity) {
  return {
    label: opportunity.label ?? "Mezo opportunity",
    kind: String(opportunity.kind ?? "unknown").toLowerCase(),
    address: opportunity.address ?? null,
    priceImpactBps: opportunity.priceImpactBps == null ? null : asNumber(opportunity.priceImpactBps),
    quoteError: opportunity.quoteError ?? null,
    executionValidated: Boolean(opportunity.executionValidated),
    reserve0: opportunity.reserve0 ?? null,
    reserve1: opportunity.reserve1 ?? null,
    token0Symbol: opportunity.token0Symbol ?? null,
    token1Symbol: opportunity.token1Symbol ?? null,
    quoteInputBTC: opportunity.quoteInputBTC ?? null,
    quoteOutputMCBTC: opportunity.quoteOutputMCBTC ?? null,
    note: opportunity.note ?? "",
  };
}

function describeShallowBTCLiquidity(opportunity) {
  const reserves = opportunity.reserve0 != null && opportunity.reserve1 != null
    ? `pool liquidity is shallow (${opportunity.reserve0} ${opportunity.token0Symbol ?? "token0"} and ${
      opportunity.reserve1
    } ${opportunity.token1Symbol ?? "token1"})`
    : "pool liquidity is shallow";
  const quote = opportunity.quoteInputBTC != null && opportunity.quoteOutputMCBTC != null
    ? `; ${opportunity.quoteInputBTC} BTC quotes to ${opportunity.quoteOutputMCBTC} mcbBTC`
    : "";
  return `${reserves}${quote}, creating ${formatBps(opportunity.priceImpactBps)} live quote impact versus a near 1:1 BTC-correlated route`;
}

function normalizeBTC(snapshot, btcSleeves) {
  const composition = snapshot.composition ?? {};
  const position = snapshot.position ?? {};
  const policy = snapshot.btcReservePolicy ?? {};
  const buckets = snapshot.btcReserveBuckets ?? {};
  const allocatedBTC = btcSleeves.reduce((sum, sleeve) => sum + sleeve.allocatedBTC, 0);
  const idleBTC = asNumber(buckets.idleBTCReserve, asNumber(composition.idleBTC));
  const collateralBTC = asNumber(buckets.collateralBTC, asNumber(position.collateralBTC));
  const emergencyBTCReserve = asNumber(buckets.emergencyBTCReserve);
  const yieldActiveBTC = asNumber(buckets.yieldActiveBTC, allocatedBTC);
  const pendingWithdrawBTC = asNumber(buckets.pendingWithdrawBTC);
  const minIdleReserveBTC = asNumber(policy.minIdleBTCReserve, asNumber(policy.minIdleReserveBTC));
  const surplusReserveBTC = Math.max(0, idleBTC - minIdleReserveBTC);
  const reserveShortfallBTC = Math.max(0, minIdleReserveBTC - idleBTC);

  return {
    idleBTC,
    collateralBTC,
    allocatedBTC,
    emergencyBTCReserve,
    yieldActiveBTC,
    pendingWithdrawBTC,
    totalAccountedBTC: idleBTC + collateralBTC + emergencyBTCReserve + yieldActiveBTC + pendingWithdrawBTC,
    minIdleReserveBTC,
    surplusReserveBTC,
    reserveShortfallBTC,
  };
}

function normalizeBTCSleeves(sleeves) {
  return sleeves.map((sleeve, index) => {
    const approved = Boolean(sleeve.approved ?? false);
    const executable = Boolean(sleeve.executable ?? false);
    const status = String(sleeve.status ?? (approved ? "approved" : "candidate")).toLowerCase();

    return {
      label: sleeve.label ?? `BTC sleeve ${index + 1}`,
      destination: sleeve.destination ?? null,
      principalAsset: sleeve.principalAsset ?? "BTC",
      receiptAsset: sleeve.receiptAsset ?? null,
      approved,
      executable,
      status,
      allocatedBTC: asNumber(sleeve.allocatedBTC),
      capBTC: asNumber(sleeve.capBTC),
      riskClass: String(sleeve.riskClass ?? "btc-denominated").toLowerCase(),
      approvalLevel: String(sleeve.approvalLevel ?? "MULTISIG").toLowerCase(),
      swapPriceImpactBps: asNumber(sleeve.swapPriceImpactBps),
      slippageBps: asNumber(sleeve.slippageBps),
      withdrawalConstraint: sleeve.withdrawalConstraint ?? "requires separate BTC accounting and approval path",
    };
  });
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

function decimalToUnits(value, decimals = 18) {
  const [wholeRaw, fractionRaw = ""] = String(value).split(".");
  const whole = wholeRaw || "0";
  const fraction = fractionRaw.padEnd(decimals, "0").slice(0, decimals);
  const units = BigInt(whole) * 10n ** BigInt(decimals) + BigInt(fraction || "0");
  return units.toString();
}

function buildCastCalldataCommand(signature, args) {
  return `cast calldata "${signature}" ${args.map((arg) => quoteShell(String(arg))).join(" ")}`;
}

function quoteShell(value) {
  return `'${value.replaceAll("'", "'\\''")}'`;
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
