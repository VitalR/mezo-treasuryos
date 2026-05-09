import assert from "node:assert/strict";
import test from "node:test";

import { buildRiskKeeperReport } from "./keeper.mjs";

const BASE_SNAPSHOT = {
  treasuryName: "Risk Keeper Test Treasury",
  composition: {
    idleMUSD: "320000",
    idleBTC: "1.10",
    liquidityBufferMUSD: "250000",
  },
  position: {
    collateralBTC: "8",
    totalDebtMUSD: "500000",
  },
  btcReserveBuckets: {
    idleBTCReserve: "1.10",
    collateralBTC: "8",
    emergencyBTCReserve: "0.25",
  },
  health: {
    collateralRatioBps: "16000",
    warningCollateralRatioBps: "18000",
    criticalCollateralRatioBps: "15000",
  },
  sleeves: [
    {
      label: "MUSD Savings Vault",
      allocatedMUSD: "180000",
      riskTier: "low",
      unwindDays: "0",
      supportsSavingsRate: true,
      automationEligible: true,
    },
    {
      label: "Tigris Basic Stable MUSD/mUSDC",
      allocatedMUSD: "60000",
      riskTier: "medium",
      unwindDays: "1",
      automationEligible: false,
    },
  ],
  riskKeeper: {
    strategyProfile: "balanced",
    btcPriceMUSD: "100000",
  },
};

test("balanced profile recommends idle BTC collateral top-up when it is the least disruptive defense path", () => {
  const report = buildRiskKeeperReport(BASE_SNAPSHOT);

  assert.equal(report.health.state, "WARNING");
  assert.equal(report.recommendation.type, "ADD_IDLE_BTC_TO_COLLATERAL");
  assert.ok(Math.abs(report.recommendation.amountBTC - 0.25) < 1e-9);
  assert.match(report.recommendation.memo, /accounted idle BTC reserve/);
});

test("active profile prefers MUSD repayment paths before idle BTC collateral top-up", () => {
  const report = buildRiskKeeperReport({
    ...BASE_SNAPSHOT,
    riskKeeper: {
      strategyProfile: "active",
      btcPriceMUSD: "100000",
    },
  });

  assert.equal(report.recommendation.type, "REPAY_FROM_IDLE_MUSD");
  assert.ok(Math.abs(report.recommendation.amountMUSD - 29411.76470588235) < 1e-9);
});

test("keeper counts immediately withdrawable MUSD Savings as defense capacity with haircut", () => {
  const report = buildRiskKeeperReport(BASE_SNAPSHOT);

  assert.equal(report.inputs.fastWithdrawableMUSD, 180000);
  assert.equal(report.defenseCapacity.fastMUSDSleeves, 171000);
  assert.equal(report.requiredDefense.recoverableToTarget, true);
});

test("keeper blocks new risk when post-stress position is not recoverable to target", () => {
  const report = buildRiskKeeperReport({
    ...BASE_SNAPSHOT,
    health: {
      collateralRatioBps: "20000",
      warningCollateralRatioBps: "18000",
      criticalCollateralRatioBps: "15000",
    },
    composition: {
      idleMUSD: "250000",
      idleBTC: "0.25",
      liquidityBufferMUSD: "250000",
    },
    btcReserveBuckets: {
      idleBTCReserve: "0.25",
      collateralBTC: "8",
      emergencyBTCReserve: "0.25",
    },
    sleeves: [],
    riskKeeper: {
      strategyProfile: "balanced",
      btcPriceMUSD: "100000",
      overrides: {
        minPostStressCollateralRatioBps: 18000,
      },
    },
  });

  assert.equal(report.health.state, "BLOCK_NEW_RISK");
  assert.equal(report.requiredDefense.recoverableToTarget, false);
  assert.equal(report.recommendation.type, "BLOCK_NEW_RISK");
});

test("keeper preserves operating MUSD buffer and idle BTC reserve in defense capacity math", () => {
  const report = buildRiskKeeperReport(BASE_SNAPSHOT);

  assert.equal(report.defenseCapacity.idleMUSD, 70000);
  assert.ok(Math.abs(report.defenseCapacity.idleBTCValue - 76500) < 1e-9);
});
