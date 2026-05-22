import assert from "node:assert/strict";
import test from "node:test";

import { buildTreasuryAdvisorReport } from "./advisor.mjs";

const BASE_SNAPSHOT = {
  treasuryName: "Test Treasury",
  treasuryAccount: "0x0000000000000000000000000000000000000abc",
  composition: {
    idleMUSD: "1000",
    idleBTC: "0.25",
    liquidityBufferMUSD: "500",
    deployableSurplusMUSD: "500",
  },
  position: {
    collateralBTC: "2",
    totalDebtMUSD: "1200",
  },
  btcReserveBuckets: {
    idleBTCReserve: "0.25",
    collateralBTC: "2",
    emergencyBTCReserve: "0.05",
    yieldActiveBTC: "0",
    pendingWithdrawBTC: "0",
  },
  health: {
    belowWarningRatio: false,
    belowCriticalRatio: false,
  },
  sleeves: [
    {
      label: "MUSD Savings Vault",
      destination: "0x1",
      approved: true,
      allocatedMUSD: "100",
      capMUSD: "600",
      remainingCapacityMUSD: "500",
      annualYieldBps: "400",
      riskTier: "low",
      unwindDays: "0",
      automationEligible: true,
    },
    {
      label: "Tigris Basic Stable MUSD/mUSDC",
      destination: "0x2",
      approved: true,
      allocatedMUSD: "0",
      capMUSD: "300",
      remainingCapacityMUSD: "300",
      annualYieldBps: "800",
      riskTier: "medium",
      unwindDays: "7",
      automationEligible: false,
    },
  ],
  btcReservePolicy: {
    minIdleReserveBTC: "0.1",
  },
  btcSleeves: [
    {
      label: "Tigris mcbBTC/BTC stable pool candidate",
      approved: false,
      executable: false,
      status: "research",
      allocatedBTC: "0",
      riskClass: "btc-correlated",
      withdrawalConstraint: "requires verified Mezo testnet handler",
    },
  ],
};

test("buildTreasuryAdvisorReport allocates surplus across approved sleeves within caps", () => {
  const report = buildTreasuryAdvisorReport(BASE_SNAPSHOT);

  assert.equal(report.summary.riskState, "healthy");
  assert.equal(report.allocationPlan.length, 1);
  assert.equal(report.allocationPlan[0].label, "MUSD Savings Vault");
  assert.equal(report.allocationPlan[0].amountMUSD, 500);
  assert.match(report.cfoPacket.recommendationId, /^cfo-[a-f0-9]{16}$/);
  assert.equal(report.cfoPacket.preparedActions.length, 1);
  assert.equal(report.cfoPacket.preparedActions[0].type, "ALLOCATE_SURPLUS_MUSD");
  assert.equal(report.cfoPacket.preparedActions[0].target, BASE_SNAPSHOT.treasuryAccount);
  assert.equal(report.cfoPacket.preparedActions[0].signature, "allocate(address,uint256)");
  assert.equal(report.cfoPacket.preparedActions[0].args[1], "500000000000000000000");
  assert.match(report.cfoPacket.preparedActions[0].castCalldataCommand, /cast calldata/);
  assert.equal(report.automationAction.action, "NO_AUTOMATION_NEEDED");
  assert.match(report.memo, /primary conservative MUSD sleeve/);
});

test("buildTreasuryAdvisorReport recommends buffer restoration during shortfall", () => {
  const report = buildTreasuryAdvisorReport({
    ...BASE_SNAPSHOT,
    composition: {
      idleMUSD: "300",
      liquidityBufferMUSD: "500",
      deployableSurplusMUSD: "0",
    },
  });

  assert.equal(report.summary.bufferShortfallMUSD, 200);
  assert.equal(report.allocationPlan.length, 0);
  assert.equal(report.automationAction.action, "RESTORE_BUFFER_FROM_SLEEVE");
  assert.equal(report.automationAction.sleeve, "MUSD Savings Vault");
  assert.equal(report.automationAction.amountMUSD, 100);
  assert.equal(report.cfoPacket.preparedActions[0].type, "RESTORE_BUFFER_FROM_SLEEVE");
  assert.equal(report.cfoPacket.preparedActions[0].status, "handoff_to_risk_keeper_proposal");
});

test("buildTreasuryAdvisorReport blocks new allocation when collateral health weakens", () => {
  const report = buildTreasuryAdvisorReport({
    ...BASE_SNAPSHOT,
    health: {
      belowWarningRatio: true,
      belowCriticalRatio: false,
    },
  });

  assert.equal(report.summary.riskState, "warning");
  assert.equal(report.allocationPlan.length, 0);
  assert.equal(report.automationAction.action, "PREPARE_DE_RISK_REPAYMENT");
});

test("buildTreasuryAdvisorReport separates BTC reserve and collateral from MUSD allocation", () => {
  const report = buildTreasuryAdvisorReport(BASE_SNAPSHOT);

  assert.equal(report.btc.idleBTC, 0.25);
  assert.equal(report.btc.collateralBTC, 2);
  assert.equal(report.btc.emergencyBTCReserve, 0.05);
  assert.equal(report.btc.yieldActiveBTC, 0);
  assert.equal(report.btc.minIdleReserveBTC, 0.1);
  assert.equal(report.btc.surplusReserveBTC, 0.15);
  assert.equal(report.btcSleeves[0].executable, false);
  assert.match(report.btcMemo, /MUSD sleeve capacity does not make BTC reserve allocatable/);
  assert.match(report.btcMemo, /emergency BTC reserve/);
  assert.match(report.btcMemo, /cleaner Bitcoin-yield direction/);
  assert.equal(report.allocationPlan[0].label, "MUSD Savings Vault");
});

test("buildTreasuryAdvisorReport keeps pending BTC withdrawals out of available reserve", () => {
  const report = buildTreasuryAdvisorReport({
    ...BASE_SNAPSHOT,
    btcReserveBuckets: {
      idleBTCReserve: "0.25",
      collateralBTC: "2",
      emergencyBTCReserve: "0.05",
      yieldActiveBTC: "0.2",
      pendingWithdrawBTC: "0.1",
    },
  });

  assert.equal(report.btc.yieldActiveBTC, 0.2);
  assert.equal(report.btc.pendingWithdrawBTC, 0.1);
  assert.match(report.btcMemo, /pending withdrawal/);
});

test("buildTreasuryAdvisorReport flags directional BTC stable LP candidates", () => {
  const report = buildTreasuryAdvisorReport({
    ...BASE_SNAPSHOT,
    btcSleeves: [
      {
        label: "Tigris MUSD/BTC directional pool candidate",
        approved: false,
        executable: false,
        status: "research",
        allocatedBTC: "0",
        riskClass: "directional-btc-stable-lp",
        withdrawalConstraint: "requires separate BTC sleeve accounting and elevated approval",
      },
    ],
  });

  assert.match(report.btcMemo, /changes pure BTC exposure/);
  assert.equal(report.btcSleeves[0].status, "research");
});

test("buildTreasuryAdvisorReport applies profile-specific stable LP appetite", () => {
  const conservative = buildTreasuryAdvisorReport(BASE_SNAPSHOT, { profileName: "conservative" });
  const active = buildTreasuryAdvisorReport(BASE_SNAPSHOT, { profileName: "active" });

  assert.equal(conservative.profile.key, "conservative");
  assert.equal(conservative.allocationPlan[0].label, "MUSD Savings Vault");
  assert.equal(active.profile.key, "active");
  assert.equal(active.profile.maxStableLpShareBps, 4000);
});

test("buildTreasuryAdvisorReport reviews live Mezo opportunities without treating BTC sleeve as executable", () => {
  const report = buildTreasuryAdvisorReport(BASE_SNAPSHOT, {
    profileName: "aggressive-demo",
    opportunities: {
      items: [
        { label: "MUSD Savings Vault", kind: "musd-savings" },
        { label: "Tigris Basic Stable MUSD/mUSDC", kind: "stable-lp" },
        {
          label: "Tigris mcbBTC/BTC",
          kind: "btc-correlated",
          reserve0: "0.05717113",
          reserve1: "0.30459953420169977",
          token0Symbol: "mcbBTC",
          token1Symbol: "BTC",
          quoteInputBTC: "0.0001",
          quoteOutputMCBTC: "0.00005149",
          priceImpactBps: 4851,
        },
      ],
    },
  });

  assert.equal(report.profile.key, "aggressive-demo");
  assert.equal(report.opportunityReview.length, 3);
  assert.equal(report.opportunityReview[0].decision, "USE_AS_PRIMARY_MUSD_SLEEVE");
  assert.equal(report.opportunityReview[1].decision, "OPTIONAL_LIMITED_ALLOCATION");
  assert.equal(report.opportunityReview[2].decision, "BLOCK_FOR_NOW");
  assert.match(report.opportunityReview[2].reason, /48.51%/);
  assert.match(report.opportunityReview[2].reason, /live quote impact/);
  assert.match(report.opportunityReview[2].reason, /pool liquidity is shallow/);
  assert.match(report.opportunityReview[2].reason, /0.0001 BTC quotes to 0.00005149 mcbBTC/);
  assert.equal(report.cfoPacket.blockedOpportunities.length, 1);
  assert.equal(report.cfoPacket.blockedOpportunities[0].label, "Tigris mcbBTC/BTC");
});
