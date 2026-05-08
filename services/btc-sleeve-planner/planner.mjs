const BPS_DENOMINATOR = 10_000n;
const WAD_DECIMALS = 18;

const APPROVAL_RANK = {
  operator: 0,
  approver: 1,
  multisig: 2,
  multisig_with_risk_override: 3,
  disabled: 4,
};

export function buildBTCSleevePlan(snapshot, options = {}) {
  const target = snapshot.btcSleeveTarget ?? firstCorrelatedSleeve(snapshot.btcSleeves ?? []);
  if (!target) {
    return {
      treasuryName: snapshot.treasuryName ?? "Mezo TreasuryOS Treasury",
      sourceBucket: "idleBTC",
      status: "blocked",
      policy: {
        allowed: false,
        reason: "NoBTCSleeveTarget",
        warnings: ["No BTC-correlated sleeve target is present in the snapshot."],
      },
    };
  }

  const btcDecimals = Number(target.decimals?.btc ?? 18);
  const mcbtcDecimals = Number(target.decimals?.mcbtc ?? 8);
  const lpDecimals = Number(target.decimals?.lp ?? 18);
  const requestedBTC = decimalToUnits(
    options.requestedBTC ?? snapshot.requestedBTC ?? snapshot.requestedPrincipalBTC ?? "0",
    btcDecimals,
  );
  const buckets = normalizeBuckets(snapshot);
  const policyConfig = snapshot.btcReservePolicy ?? {};
  const currentSleeveExposureBTC = decimalToUnits(target.allocatedBTC ?? "0", btcDecimals);
  const totalAccountedBTC = sumBuckets(buckets);
  const minIdleBTC = decimalToUnits(policyConfig.minIdleBTCReserve ?? policyConfig.minIdleReserveBTC ?? "0", btcDecimals);
  const requiredEmergencyBTC = decimalToUnits(policyConfig.emergencyBTCReserve ?? "0", btcDecimals);
  const availableBTC = buckets.idleBTCReserve > minIdleBTC ? buckets.idleBTCReserve - minIdleBTC : 0n;
  const slippageBps = BigInt(target.slippageBps ?? policyConfig.maxSlippageBps ?? 100);

  const calculation = buildSplitCalculation({
    target,
    requestedBTC,
    btcDecimals,
    mcbtcDecimals,
    lpDecimals,
    slippageBps,
  });
  const policy = evaluatePolicy({
    target,
    policyConfig,
    requestedBTC,
    availableBTC,
    buckets,
    totalAccountedBTC,
    currentSleeveExposureBTC,
    calculation,
    slippageBps,
  });
  const status = policy.allowed ? (target.executable ? "experimental-executable" : "proposal-preview") : "blocked";
  const recommendation = buildRecommendation({ calculation, policy });

  return {
    treasuryName: snapshot.treasuryName ?? "Mezo TreasuryOS Treasury",
    sourceBucket: "idleBTC",
    status,
    requestedPrincipalBTC: formatUnits(requestedBTC, btcDecimals),
    idleBTCReserve: formatUnits(buckets.idleBTCReserve, btcDecimals),
    minIdleBTCReserve: formatUnits(minIdleBTC, btcDecimals),
    emergencyBTCReserve: formatUnits(buckets.emergencyBTCReserve, btcDecimals),
    availableBTC: formatUnits(availableBTC, btcDecimals),
    candidate: {
      label: target.label ?? "Tigris mcbBTC/BTC stable pool candidate",
      pool: target.destination ?? target.pool ?? null,
      router: target.router ?? null,
      gauge: target.gauge ?? null,
      riskClass: target.riskClass ?? "BTC_CORRELATED",
      approvalLevel: target.approvalLevel ?? "MULTISIG",
      executable: Boolean(target.executable),
      status: target.status ?? "preview",
    },
    calculation,
    policy,
    execution: {
      mode: target.executable && policy.allowed ? "experimental-multisig-only" : "preview-only",
      principalMovement: Boolean(target.executable && policy.allowed),
      proposalOnly: !target.executable || policy.requiredApprovalLevel !== "OPERATOR",
      stakingIncluded: Boolean(target.stakingIncluded),
      note:
        "Planner does not move BTC. Principal movement should be executed only through a multisig-reviewed BTC handler.",
    },
    recommendation,
    memo: buildMemo({ calculation, policy, recommendation }),
  };
}

export function formatBTCSleevePlan(plan) {
  const lines = [];
  lines.push(`BTC Treasury Sleeve Planner: ${plan.treasuryName}`);
  lines.push("");
  lines.push(`Source bucket: ${plan.sourceBucket}`);
  lines.push(`Requested BTC principal: ${btc(plan.requestedPrincipalBTC)}`);
  lines.push(`Idle BTC reserve: ${btc(plan.idleBTCReserve)}`);
  lines.push(`Minimum idle BTC reserve: ${btc(plan.minIdleBTCReserve)}`);
  lines.push(`Emergency BTC reserve: ${btc(plan.emergencyBTCReserve)}`);
  lines.push(`Available BTC for yield: ${btc(plan.availableBTC)}`);
  lines.push("");
  lines.push("Candidate:");
  lines.push(`- ${plan.candidate.label}`);
  lines.push(`- Risk class: ${plan.candidate.riskClass}`);
  lines.push(`- Required approval: ${plan.policy.requiredApprovalLevel}`);
  lines.push(`- Execution mode: ${plan.execution.mode}`);

  if (plan.calculation.available) {
    lines.push("");
    lines.push("BTC sleeve plan:");
    lines.push(`- Swap estimate: ${btc(plan.calculation.swapBTC)} BTC -> ${plan.calculation.expectedMCBTCOut} mcbBTC`);
    lines.push(`- LP deposit estimate: ${btc(plan.calculation.remainingBTCForLP)} BTC + ${plan.calculation.expectedMCBTCOut} mcbBTC`);
    lines.push(`- Expected LP: ${plan.calculation.expectedLPTokens} sAMM-mcbBTC/BTC`);
    lines.push(`- Min mcbBTC out: ${plan.calculation.minMCBTCOut}`);
    lines.push(`- Min LP out: ${plan.calculation.minLPTokens}`);
    lines.push(`- Estimated price impact: ${bps(plan.calculation.priceImpactBps)}`);
    lines.push(`- Max slippage: ${bps(plan.calculation.slippageBps)}`);
  }

  lines.push("");
  lines.push(`Policy result: ${plan.policy.allowed ? "ALLOW" : "BLOCK"} (${plan.policy.reason})`);
  lines.push(`Required approval: ${plan.policy.requiredApprovalLevel}`);
  for (const warning of plan.policy.warnings) lines.push(`- ${warning}`);
  lines.push("");
  lines.push("Recommendation:");
  lines.push(plan.recommendation);
  lines.push("");
  lines.push("Memo:");
  lines.push(plan.memo);

  return lines.join("\n");
}

function buildSplitCalculation({ target, requestedBTC, btcDecimals, mcbtcDecimals, lpDecimals, slippageBps }) {
  const reserveBTC = decimalToUnits(target.reserves?.btc ?? target.reserveBTC ?? "0", btcDecimals);
  const reserveMCBTC = decimalToUnits(target.reserves?.mcbtc ?? target.reserveMCBTC ?? "0", mcbtcDecimals);
  const lpTotalSupply = decimalToUnits(target.totalSupplyLP ?? target.totalSupply ?? "0", lpDecimals);
  const quoteInputBTC = decimalToUnits(target.quote?.inputBTC ?? target.quoteInputBTC ?? "0", btcDecimals);
  const quoteOutputMCBTC = decimalToUnits(target.quote?.outputMCBTC ?? target.quoteOutputMCBTC ?? "0", mcbtcDecimals);

  if (
    requestedBTC === 0n || reserveBTC === 0n || reserveMCBTC === 0n || quoteInputBTC === 0n || quoteOutputMCBTC === 0n
      || lpTotalSupply === 0n
  ) {
    return {
      available: false,
      reason: "QuoteOrReserveUnavailable",
      requestedBTC: formatUnits(requestedBTC, btcDecimals),
      slippageBps: Number(slippageBps),
    };
  }

  const swapBTC = (requestedBTC * quoteInputBTC * reserveMCBTC) / (quoteOutputMCBTC * reserveBTC + quoteInputBTC * reserveMCBTC);
  const expectedMCBTCOut = (swapBTC * quoteOutputMCBTC) / quoteInputBTC;
  const remainingBTCForLP = requestedBTC - swapBTC;
  const expectedLPFromMCBTC = (expectedMCBTCOut * lpTotalSupply) / reserveMCBTC;
  const expectedLPFromBTC = (remainingBTCForLP * lpTotalSupply) / reserveBTC;
  const expectedLPTokens = expectedLPFromMCBTC < expectedLPFromBTC ? expectedLPFromMCBTC : expectedLPFromBTC;
  const minMCBTCOut = applySlippage(expectedMCBTCOut, slippageBps);
  const minLPTokens = applySlippage(expectedLPTokens, slippageBps);
  const priceImpactBps = estimatePriceImpactBps({
    quoteInputBTC,
    quoteOutputMCBTC,
    btcDecimals,
    mcbtcDecimals,
    referenceMcbtcPerBtc: target.referenceMcbtcPerBtc ?? "1",
  });
  const poolShareBps = expectedLPTokens === 0n ? 0n : (expectedLPTokens * BPS_DENOMINATOR) / (lpTotalSupply + expectedLPTokens);

  return {
    available: true,
    requestedBTC: formatUnits(requestedBTC, btcDecimals),
    swapBTC: formatUnits(swapBTC, btcDecimals),
    remainingBTCForLP: formatUnits(remainingBTCForLP, btcDecimals),
    expectedMCBTCOut: formatUnits(expectedMCBTCOut, mcbtcDecimals),
    expectedLPTokens: formatUnits(expectedLPTokens, lpDecimals),
    minMCBTCOut: formatUnits(minMCBTCOut, mcbtcDecimals),
    minLPTokens: formatUnits(minLPTokens, lpDecimals),
    quoteInputBTC: formatUnits(quoteInputBTC, btcDecimals),
    quoteOutputMCBTC: formatUnits(quoteOutputMCBTC, mcbtcDecimals),
    quoteMCBTCPerBTC: scaledRatioToDecimal(
      (quoteOutputMCBTC * 10n ** BigInt(btcDecimals) * 10n ** 18n) / (quoteInputBTC * 10n ** BigInt(mcbtcDecimals)),
    ),
    reserveBTC: formatUnits(reserveBTC, btcDecimals),
    reserveMCBTC: formatUnits(reserveMCBTC, mcbtcDecimals),
    priceImpactBps: Number(priceImpactBps),
    slippageBps: Number(slippageBps),
    poolShareBps: Number(poolShareBps),
    minOutNonzero: minMCBTCOut > 0n && minLPTokens > 0n,
  };
}

function evaluatePolicy({
  target,
  policyConfig,
  requestedBTC,
  availableBTC,
  buckets,
  totalAccountedBTC,
  currentSleeveExposureBTC,
  calculation,
  slippageBps,
}) {
  const warnings = [];
  const requiredApprovalLevel = normalizeApproval(target.approvalLevel ?? "MULTISIG");
  const riskClass = String(target.riskClass ?? "BTC_CORRELATED").toUpperCase();
  const maxYieldBps = BigInt(policyConfig.maxYieldBTCBps ?? 0);
  const configuredPerSleeveBps = policyConfig.maxPerSleeveBTCBps ?? 0;
  const sleeveCapBps = target.sleeveCapBps ?? configuredPerSleeveBps;
  const maxPerSleeveBps = BigInt(minNumeric(configuredPerSleeveBps, sleeveCapBps) ?? 0);
  const maxPriceImpactBps = BigInt(target.maxPriceImpactBps ?? policyConfig.maxSwapPriceImpactBps ?? 0);
  const maxSlippageBps = BigInt(policyConfig.maxSlippageBps ?? target.maxSlippageBps ?? slippageBps);

  if (!target.executable) {
    warnings.push("BTC sleeve execution is not live; output should be treated as a multisig proposal preview.");
  }

  const reason = firstBlockingReason({
    target,
    requestedBTC,
    availableBTC,
    buckets,
    policyConfig,
    riskClass,
    requiredApprovalLevel,
    totalAccountedBTC,
    currentSleeveExposureBTC,
    calculation,
    maxYieldBps,
    maxPerSleeveBps,
    maxPriceImpactBps,
    maxSlippageBps,
    slippageBps,
  });

  if (calculation.available && calculation.priceImpactBps > 0) {
    warnings.push(`Estimated BTC->mcbBTC price impact is ${formatBps(calculation.priceImpactBps)}.`);
  }
  if (riskClass === "BTC_CORRELATED") {
    warnings.push("mcbBTC/BTC preserves BTC-correlated exposure better than BTC/MUSD, but still has wrapper, liquidity, and LP risks.");
  }
  if (target.testnetAPRNote !== false) {
    warnings.push("APR and emissions assumptions are testnet/demo data, not a production guarantee.");
  }

  return {
    allowed: reason === "Allowed",
    reason,
    requiredApprovalLevel: requiredApprovalLevel.toUpperCase(),
    maxPriceImpactBps: Number(maxPriceImpactBps),
    maxSlippageBps: Number(maxSlippageBps),
    availableBTC: formatUnits(availableBTC, 18),
    warnings,
  };
}

function firstBlockingReason({
  target,
  requestedBTC,
  availableBTC,
  buckets,
  policyConfig,
  riskClass,
  requiredApprovalLevel,
  totalAccountedBTC,
  currentSleeveExposureBTC,
  calculation,
  maxYieldBps,
  maxPerSleeveBps,
  maxPriceImpactBps,
  maxSlippageBps,
  slippageBps,
}) {
  if (policyConfig.btcYieldPaused) return "YieldPaused";
  if (requestedBTC === 0n) return "ZeroAmount";
  if (!target.approved) return "SleeveDisabled";
  if (riskClass !== "BTC_CORRELATED") return riskClass === "SPECULATIVE" ? "SpeculativeDisabled" : "UnsupportedRiskClass";
  if (buckets.emergencyBTCReserve < decimalToUnits(policyConfig.emergencyBTCReserve ?? "0", 18)) {
    return "EmergencyReserveShortfall";
  }
  if (availableBTC < requestedBTC) return "InsufficientIdleBTCReserve";
  if (isApprovalBelow(requiredApprovalLevel, "multisig")) return "ApprovalLevelTooLow";
  if (totalAccountedBTC === 0n) return "NoAccountedBTC";
  if (maxYieldBps > 0n && buckets.yieldActiveBTC + requestedBTC > capAmount(totalAccountedBTC, maxYieldBps)) {
    return "TotalYieldCapExceeded";
  }
  if (maxPerSleeveBps > 0n && currentSleeveExposureBTC + requestedBTC > capAmount(totalAccountedBTC, maxPerSleeveBps)) {
    return "PerSleeveCapExceeded";
  }
  if (!calculation.available) return calculation.reason;
  if (!calculation.minOutNonzero) return "DustAmount";
  if (maxPriceImpactBps > 0n && BigInt(calculation.priceImpactBps) > maxPriceImpactBps) {
    return "SwapPriceImpactExceeded";
  }
  if (maxSlippageBps > 0n && slippageBps > maxSlippageBps) return "SlippageExceeded";
  return "Allowed";
}

function buildRecommendation({ calculation, policy }) {
  if (!calculation.available) {
    return "Keep BTC idle until pool reserves, router quote, and LP supply are available for a real execution plan.";
  }

  if (!policy.allowed && policy.reason === "SwapPriceImpactExceeded") {
    return "Keep BTC idle, preserve collateral defense, and wait for deeper mcbBTC/BTC liquidity or a lower-impact route before multisig execution.";
  }

  if (!policy.allowed && policy.reason === "InsufficientIdleBTCReserve") {
    return "Keep the BTC reserve floor intact; do not allocate idle BTC below the configured minimum reserve.";
  }

  if (!policy.allowed && policy.reason === "ApprovalLevelTooLow") {
    return "Escalate to multisig approval before any BTC principal movement is proposed.";
  }

  if (!policy.allowed) {
    return `Do not execute; resolve BTC reserve policy block ${policy.reason} before preparing a transaction.`;
  }

  return "Use this as a multisig-reviewed proposal only; V1.5 execution should wait for controlled broadcast validation of swap, LP, unwind, stake, and reward paths.";
}

function buildMemo({ calculation, policy, recommendation }) {
  if (!calculation.available) {
    return "The BTC sleeve cannot be planned because reserve, quote, or LP supply data is missing. Keep BTC idle or use it as collateral until the route can be quoted.";
  }

  const base = `Allocate ${btc(calculation.requestedBTC)} idle BTC only through the BTC reserve path: swap ${btc(
    calculation.swapBTC,
  )} BTC into ${calculation.expectedMCBTCOut} mcbBTC, pair ${btc(
    calculation.remainingBTCForLP,
  )} BTC with that mcbBTC, and require at least ${calculation.minLPTokens} LP tokens.`;

  if (!policy.allowed) {
    return `${base} Current policy blocks the plan with reason ${policy.reason}; keep this as a proposal memo, not an execution. ${recommendation}`;
  }

  return `${base} Policy allows the preview, but principal movement should remain ${policy.requiredApprovalLevel}-approved and proposal-only unless the guarded BTC handler is deployed and transaction-tested. ${recommendation}`;
}

function normalizeBuckets(snapshot) {
  const composition = snapshot.composition ?? {};
  const position = snapshot.position ?? {};
  const buckets = snapshot.btcReserveBuckets ?? {};
  return {
    idleBTCReserve: decimalToUnits(buckets.idleBTCReserve ?? composition.idleBTC ?? "0", 18),
    collateralBTC: decimalToUnits(buckets.collateralBTC ?? position.collateralBTC ?? "0", 18),
    emergencyBTCReserve: decimalToUnits(buckets.emergencyBTCReserve ?? "0", 18),
    yieldActiveBTC: decimalToUnits(buckets.yieldActiveBTC ?? "0", 18),
    pendingWithdrawBTC: decimalToUnits(buckets.pendingWithdrawBTC ?? "0", 18),
  };
}

function firstCorrelatedSleeve(sleeves) {
  return sleeves.find((sleeve) => String(sleeve.riskClass ?? "").toUpperCase().includes("BTC_CORRELATED"));
}

function sumBuckets(buckets) {
  return buckets.idleBTCReserve + buckets.collateralBTC + buckets.emergencyBTCReserve + buckets.yieldActiveBTC
    + buckets.pendingWithdrawBTC;
}

function minNumeric(left, right) {
  const a = Number(left);
  const b = Number(right);
  if (!Number.isFinite(a) || a <= 0) return right;
  if (!Number.isFinite(b) || b <= 0) return left;
  return a < b ? left : right;
}

function capAmount(total, capBps) {
  return (total * capBps) / BPS_DENOMINATOR;
}

function applySlippage(amount, slippageBps) {
  return (amount * (BPS_DENOMINATOR - slippageBps)) / BPS_DENOMINATOR;
}

function estimatePriceImpactBps({ quoteInputBTC, quoteOutputMCBTC, btcDecimals, mcbtcDecimals, referenceMcbtcPerBtc }) {
  const quoteRateScaled =
    (quoteOutputMCBTC * 10n ** BigInt(btcDecimals) * 10n ** 18n) / (quoteInputBTC * 10n ** BigInt(mcbtcDecimals));
  const referenceScaled = decimalToUnits(referenceMcbtcPerBtc, WAD_DECIMALS);
  const delta = quoteRateScaled > referenceScaled ? quoteRateScaled - referenceScaled : referenceScaled - quoteRateScaled;
  return (delta * BPS_DENOMINATOR) / referenceScaled;
}

function normalizeApproval(value) {
  return String(value ?? "MULTISIG").toLowerCase();
}

function isApprovalBelow(actual, minimum) {
  return (APPROVAL_RANK[actual] ?? -1) < (APPROVAL_RANK[minimum] ?? 0);
}

function decimalToUnits(value, decimals) {
  const raw = String(value ?? "0").trim();
  if (!/^-?\d+(\.\d+)?$/u.test(raw)) throw new Error(`Invalid decimal value: ${value}`);
  const negative = raw.startsWith("-");
  const unsigned = negative ? raw.slice(1) : raw;
  const [whole, fraction = ""] = unsigned.split(".");
  const padded = fraction.padEnd(decimals, "0").slice(0, decimals);
  const units = BigInt(whole || "0") * 10n ** BigInt(decimals) + BigInt(padded || "0");
  return negative ? -units : units;
}

function formatUnits(value, decimals) {
  const negative = value < 0n;
  const absolute = negative ? -value : value;
  const base = 10n ** BigInt(decimals);
  const whole = absolute / base;
  const fraction = absolute % base;
  const sign = negative ? "-" : "";
  if (fraction === 0n) return `${sign}${whole}`;
  return `${sign}${whole}.${fraction.toString().padStart(decimals, "0").replace(/0+$/u, "")}`;
}

function scaledRatioToDecimal(value) {
  return formatUnits(value, 18);
}

function btc(value) {
  return `${Number(value ?? 0).toLocaleString("en-US", { maximumFractionDigits: 8 })}`;
}

function bps(value) {
  return `${(Number(value ?? 0) / 100).toFixed(2)}%`;
}

function formatBps(value) {
  return `${(Number(value ?? 0) / 100).toFixed(2)}%`;
}
