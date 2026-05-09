const BPS = 10_000;

export const STRATEGY_PROFILES = {
  conservative: {
    label: "Conservative Treasury",
    targetCollateralRatioBps: 24_000,
    warningCollateralRatioBps: 20_000,
    criticalCollateralRatioBps: 16_000,
    stressDropBps: 3_000,
    minPostStressCollateralRatioBps: 15_000,
    minIdleBTCReserve: 0.5,
    musdOperatingBuffer: 500_000,
    savingsDefenseHaircutBps: 9_500,
    lpDefenseHaircutBps: 7_000,
    btcDefenseHaircutBps: 9_000,
    preferIdleBTCForCollateralTopUp: true,
    maxAutoIdleBTCTopUp: 0.5,
  },
  balanced: {
    label: "Balanced Treasury",
    targetCollateralRatioBps: 20_000,
    warningCollateralRatioBps: 18_000,
    criticalCollateralRatioBps: 15_000,
    stressDropBps: 2_500,
    minPostStressCollateralRatioBps: 14_000,
    minIdleBTCReserve: 0.25,
    musdOperatingBuffer: 250_000,
    savingsDefenseHaircutBps: 9_500,
    lpDefenseHaircutBps: 7_500,
    btcDefenseHaircutBps: 9_000,
    preferIdleBTCForCollateralTopUp: true,
    maxAutoIdleBTCTopUp: 0.25,
  },
  active: {
    label: "Active Treasury",
    targetCollateralRatioBps: 17_000,
    warningCollateralRatioBps: 16_000,
    criticalCollateralRatioBps: 14_000,
    stressDropBps: 2_000,
    minPostStressCollateralRatioBps: 13_000,
    minIdleBTCReserve: 0.1,
    musdOperatingBuffer: 100_000,
    savingsDefenseHaircutBps: 9_000,
    lpDefenseHaircutBps: 6_500,
    btcDefenseHaircutBps: 8_500,
    preferIdleBTCForCollateralTopUp: false,
    maxAutoIdleBTCTopUp: 0.1,
  },
  aggressive_demo: {
    label: "Aggressive Demo Only",
    targetCollateralRatioBps: 14_000,
    warningCollateralRatioBps: 13_500,
    criticalCollateralRatioBps: 12_500,
    stressDropBps: 1_000,
    minPostStressCollateralRatioBps: 12_000,
    minIdleBTCReserve: 0,
    musdOperatingBuffer: 25_000,
    savingsDefenseHaircutBps: 8_500,
    lpDefenseHaircutBps: 5_500,
    btcDefenseHaircutBps: 8_000,
    preferIdleBTCForCollateralTopUp: false,
    maxAutoIdleBTCTopUp: 0.05,
    demoOnly: true,
  },
};

export function buildRiskKeeperReport(snapshot) {
  const profileName = snapshot.riskKeeper?.strategyProfile ?? "balanced";
  const baseProfile = STRATEGY_PROFILES[profileName] ?? STRATEGY_PROFILES.balanced;
  const profile = {
    ...baseProfile,
    ...withoutUndefined(snapshot.riskKeeper?.overrides ?? {}),
  };

  const composition = snapshot.composition ?? {};
  const position = snapshot.position ?? {};
  const sleeves = snapshot.sleeves ?? [];
  const btcPrice = numberAt(snapshot.riskKeeper?.btcPriceMUSD, 100_000);
  const idleMUSD = numberAt(composition.idleMUSD);
  const idleBTC = numberAt(snapshot.btcReserveBuckets?.idleBTCReserve, numberAt(composition.idleBTC));
  const collateralBTC = numberAt(snapshot.btcReserveBuckets?.collateralBTC, numberAt(position.collateralBTC));
  const debtMUSD = numberAt(position.totalDebtMUSD);
  const currentCR = numberAt(snapshot.health?.collateralRatioBps, collateralRatioBps(collateralBTC, debtMUSD, btcPrice));
  const warningCR = numberAt(snapshot.health?.warningCollateralRatioBps, profile.warningCollateralRatioBps);
  const criticalCR = numberAt(snapshot.health?.criticalCollateralRatioBps, profile.criticalCollateralRatioBps);
  const postStressPrice = btcPrice * (BPS - profile.stressDropBps) / BPS;
  const postStressCR = collateralRatioBps(collateralBTC, debtMUSD, postStressPrice);

  const fastSleeves = sleeves.filter((sleeve) => isFastMUSDSleeve(sleeve));
  const lpSleeves = sleeves.filter((sleeve) => isSlowerMUSDSleeve(sleeve));
  const fastWithdrawableMUSD = sum(fastSleeves.map((sleeve) => numberAt(sleeve.allocatedMUSD)));
  const lpWithdrawableMUSD = sum(lpSleeves.map((sleeve) => numberAt(sleeve.allocatedMUSD)));
  const idleMUSDForDefense = Math.max(0, idleMUSD - profile.musdOperatingBuffer);
  const idleBTCForDefense = Math.max(0, idleBTC - profile.minIdleBTCReserve);

  const defenseCapacity = {
    idleMUSD: idleMUSDForDefense,
    fastMUSDSleeves: fastWithdrawableMUSD * profile.savingsDefenseHaircutBps / BPS,
    liquidMUSDLP: lpWithdrawableMUSD * profile.lpDefenseHaircutBps / BPS,
    idleBTCValue: idleBTCForDefense * btcPrice * profile.btcDefenseHaircutBps / BPS,
  };
  defenseCapacity.totalMUSD = defenseCapacity.idleMUSD + defenseCapacity.fastMUSDSleeves
    + defenseCapacity.liquidMUSDLP + defenseCapacity.idleBTCValue;

  const repayNeededToTarget = requiredRepayToTarget(collateralBTC, debtMUSD, btcPrice, profile.targetCollateralRatioBps);
  const btcTopUpNeededToTarget =
    requiredBTCTopUpToTarget(collateralBTC, debtMUSD, btcPrice, profile.targetCollateralRatioBps);
  const recoverableToTarget = defenseCapacity.totalMUSD >= Math.min(repayNeededToTarget, btcTopUpNeededToTarget * btcPrice);

  const state = riskState({
    currentCR,
    warningCR,
    criticalCR,
    postStressCR,
    minPostStressCR: profile.minPostStressCollateralRatioBps,
    recoverableToTarget,
  });
  const actions = candidateActions({
    profile,
    idleMUSDForDefense,
    idleBTCForDefense,
    fastWithdrawableMUSD,
    lpWithdrawableMUSD,
    repayNeededToTarget,
    btcTopUpNeededToTarget,
    debtMUSD,
    collateralBTC,
    btcPrice,
    fastSleeves,
    lpSleeves,
  });
  const recommendation = chooseAction({ state, profile, actions });

  return {
    treasuryName: snapshot.treasuryName ?? "TreasuryOS Treasury",
    strategyProfile: profileName,
    profile,
    health: {
      currentCollateralRatioBps: Math.trunc(currentCR),
      warningCollateralRatioBps: Math.trunc(warningCR),
      criticalCollateralRatioBps: Math.trunc(criticalCR),
      targetCollateralRatioBps: Math.trunc(profile.targetCollateralRatioBps),
      postStressCollateralRatioBps: Math.trunc(postStressCR),
      minPostStressCollateralRatioBps: Math.trunc(profile.minPostStressCollateralRatioBps),
      state,
    },
    inputs: {
      btcPriceMUSD: btcPrice,
      idleMUSD,
      idleBTC,
      collateralBTC,
      debtMUSD,
      fastWithdrawableMUSD,
      lpWithdrawableMUSD,
    },
    defenseCapacity,
    requiredDefense: {
      repayNeededToTargetMUSD: repayNeededToTarget,
      btcTopUpNeededToTarget,
      recoverableToTarget,
    },
    candidateActions: actions,
    recommendation,
  };
}

export function renderRiskKeeperReport(report) {
  const lines = [];
  lines.push(`Treasury Risk Keeper: ${report.treasuryName}`);
  lines.push(`Strategy: ${report.profile.label}${report.profile.demoOnly ? " (demo/high-risk)" : ""}`);
  lines.push(`Current CR: ${formatBps(report.health.currentCollateralRatioBps)}`);
  lines.push(`Target CR: ${formatBps(report.health.targetCollateralRatioBps)}`);
  lines.push(`Post-stress CR: ${formatBps(report.health.postStressCollateralRatioBps)}`);
  lines.push(`State: ${report.health.state}`);
  lines.push("");
  lines.push("Defense capacity:");
  lines.push(`- Idle MUSD above operating buffer: ${formatMUSD(report.defenseCapacity.idleMUSD)}`);
  lines.push(`- Fast MUSD sleeves after haircut: ${formatMUSD(report.defenseCapacity.fastMUSDSleeves)}`);
  lines.push(`- MUSD LP after haircut: ${formatMUSD(report.defenseCapacity.liquidMUSDLP)}`);
  lines.push(`- Idle BTC collateral value after haircut: ${formatMUSD(report.defenseCapacity.idleBTCValue)}`);
  lines.push(`- Effective total: ${formatMUSD(report.defenseCapacity.totalMUSD)}`);
  lines.push("");
  lines.push(`Recommended action: ${report.recommendation.type}`);
  lines.push(report.recommendation.memo);
  if (report.recommendation.amountMUSD != null) lines.push(`MUSD amount: ${formatMUSD(report.recommendation.amountMUSD)}`);
  if (report.recommendation.amountBTC != null) lines.push(`BTC amount: ${formatBTC(report.recommendation.amountBTC)}`);
  return lines.join("\n");
}

function candidateActions(input) {
  const candidates = [];

  if (input.idleBTCForDefense > 0 && input.btcTopUpNeededToTarget > 0) {
    const maxTopUp = input.profile.maxAutoIdleBTCTopUp > 0
      ? input.profile.maxAutoIdleBTCTopUp
      : input.idleBTCForDefense;
    const amountBTC = Math.min(input.idleBTCForDefense, input.btcTopUpNeededToTarget, maxTopUp);
    candidates.push({
      type: "ADD_IDLE_BTC_TO_COLLATERAL",
      amountBTC,
      expectedCollateralRatioBps: collateralRatioBps(input.collateralBTC + amountBTC, input.debtMUSD, input.btcPrice),
      memo: "Top up collateral from accounted idle BTC reserve without unwinding MUSD yield sleeves; amount is capped by strategy policy.",
    });
  }

  if (input.idleMUSDForDefense > 0 && input.repayNeededToTarget > 0) {
    const amountMUSD = Math.min(input.idleMUSDForDefense, input.repayNeededToTarget);
    candidates.push({
      type: "REPAY_FROM_IDLE_MUSD",
      amountMUSD,
      expectedCollateralRatioBps: collateralRatioBps(input.collateralBTC, input.debtMUSD - amountMUSD, input.btcPrice),
      memo: "Repay debt from idle MUSD above the operating buffer.",
    });
  }

  if (input.fastWithdrawableMUSD > 0 && input.repayNeededToTarget > 0) {
    const amountMUSD = Math.min(input.fastWithdrawableMUSD, input.repayNeededToTarget);
    candidates.push({
      type: "WITHDRAW_FAST_MUSD_SLEEVE_AND_REPAY",
      amountMUSD,
      sleeve: input.fastSleeves[0]?.label ?? "fast MUSD sleeve",
      expectedCollateralRatioBps: collateralRatioBps(input.collateralBTC, input.debtMUSD - amountMUSD, input.btcPrice),
      memo: "Withdraw from a fast MUSD sleeve and repay debt; use when idle BTC reserve should be preserved.",
    });
  }

  if (input.lpWithdrawableMUSD > 0 && input.repayNeededToTarget > 0) {
    const amountMUSD = Math.min(input.lpWithdrawableMUSD, input.repayNeededToTarget);
    candidates.push({
      type: "WITHDRAW_SLOWER_MUSD_LP_AND_REPAY",
      amountMUSD,
      sleeve: input.lpSleeves[0]?.label ?? "MUSD LP sleeve",
      expectedCollateralRatioBps: collateralRatioBps(input.collateralBTC, input.debtMUSD - amountMUSD, input.btcPrice),
      memo: "Unwind a slower MUSD LP sleeve only if less disruptive defense paths are insufficient.",
    });
  }

  return candidates;
}

function chooseAction({ state, profile, actions }) {
  if (state === "HEALTHY") {
    return { type: "MONITOR", memo: "Position is inside target and post-stress policy. No action required." };
  }

  if (state === "BLOCK_NEW_RISK") {
    return {
      type: "BLOCK_NEW_RISK",
      memo: "Block new borrow, MUSD allocation, and BTC yield allocation until defense capacity improves.",
    };
  }

  const byType = new Map(actions.map((action) => [action.type, action]));
  const preference = profile.preferIdleBTCForCollateralTopUp
    ? [
        "ADD_IDLE_BTC_TO_COLLATERAL",
        "REPAY_FROM_IDLE_MUSD",
        "WITHDRAW_FAST_MUSD_SLEEVE_AND_REPAY",
        "WITHDRAW_SLOWER_MUSD_LP_AND_REPAY",
      ]
    : [
        "REPAY_FROM_IDLE_MUSD",
        "WITHDRAW_FAST_MUSD_SLEEVE_AND_REPAY",
        "ADD_IDLE_BTC_TO_COLLATERAL",
        "WITHDRAW_SLOWER_MUSD_LP_AND_REPAY",
      ];

  for (const type of preference) {
    if (byType.has(type)) return byType.get(type);
  }

  return {
    type: "ALERT_OR_MULTISIG_PROPOSAL",
    memo: "No deterministic keeper action has enough available defense capacity. Generate a multisig proposal or pause risky flows.",
  };
}

function riskState({ currentCR, warningCR, criticalCR, postStressCR, minPostStressCR, recoverableToTarget }) {
  if (currentCR < criticalCR) return "CRITICAL";
  if (currentCR < warningCR) return "WARNING";
  if (postStressCR < minPostStressCR && !recoverableToTarget) return "BLOCK_NEW_RISK";
  if (postStressCR < minPostStressCR) return "WATCH";
  return "HEALTHY";
}

function requiredRepayToTarget(collateralBTC, debtMUSD, btcPrice, targetBps) {
  if (collateralBTC <= 0 || debtMUSD <= 0 || btcPrice <= 0 || targetBps <= 0) return 0;
  const targetDebt = collateralBTC * btcPrice * BPS / targetBps;
  return Math.max(0, debtMUSD - targetDebt);
}

function requiredBTCTopUpToTarget(collateralBTC, debtMUSD, btcPrice, targetBps) {
  if (debtMUSD <= 0 || btcPrice <= 0 || targetBps <= 0) return 0;
  const targetCollateral = debtMUSD * targetBps / (btcPrice * BPS);
  return Math.max(0, targetCollateral - collateralBTC);
}

function collateralRatioBps(collateralBTC, debtMUSD, btcPrice) {
  if (collateralBTC <= 0 || debtMUSD <= 0 || btcPrice <= 0) return 0;
  return collateralBTC * btcPrice * BPS / debtMUSD;
}

function isFastMUSDSleeve(sleeve) {
  const unwindDays = numberAt(sleeve.unwindDays, numberAt(sleeve.withdrawalDelayDays));
  const delaySeconds = numberAt(sleeve.withdrawalDelaySec);
  return Boolean(sleeve.supportsSavingsRate || sleeve.riskTier === "low" || sleeve.automationEligible)
    && unwindDays === 0
    && delaySeconds === 0;
}

function isSlowerMUSDSleeve(sleeve) {
  return !isFastMUSDSleeve(sleeve) && numberAt(sleeve.allocatedMUSD) > 0 && !/btc/i.test(sleeve.label ?? "");
}

function numberAt(value, fallback = 0) {
  if (value == null || value === "") return fallback;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function sum(values) {
  return values.reduce((total, value) => total + value, 0);
}

function withoutUndefined(value) {
  return Object.fromEntries(Object.entries(value).filter(([, entry]) => entry !== undefined));
}

function formatBps(value) {
  return `${(Number(value) / 100).toFixed(2)}%`;
}

function formatMUSD(value) {
  return `${Math.round(Number(value)).toLocaleString("en-US")} MUSD`;
}

function formatBTC(value) {
  return `${Number(value).toFixed(6)} BTC`;
}
