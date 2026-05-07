import assert from "node:assert/strict";
import test from "node:test";

import { buildTermYieldPlan } from "./planner.mjs";

const BASE_SNAPSHOT = {
  treasuryName: "Test Treasury",
  termYieldPlanner: {
    asOfDate: "2026-05-08",
    plannedOperatingDisbursementsMUSD: "100",
    reserveAboveBufferMUSD: "50",
  },
  composition: {
    idleMUSD: "1000",
    idleBTC: "0.25",
    liquidityBufferMUSD: "400",
    deployableSurplusMUSD: "600",
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
      capMUSD: "500",
      remainingCapacityMUSD: "400",
      annualYieldBps: "400",
      riskTier: "low",
      unwindDays: "0",
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
    },
  ],
  btcSleeves: [
    {
      label: "Tigris mcbBTC/BTC stable pool candidate",
      approved: false,
      executable: false,
      riskClass: "BTC_CORRELATED",
    },
  ],
};

test("buildTermYieldPlan allocates only surplus after buffer and operating reserves", () => {
  const plan = buildTermYieldPlan(BASE_SNAPSHOT);

  assert.equal(plan.posture, "planning");
  assert.equal(plan.inputs.allocatableMUSD, 450);
  assert.equal(plan.plans.length, 3);
  assert.equal(plan.plans[0].termDays, 7);
  assert.equal(plan.plans[0].reviewDate, "2026-05-14");
  assert.equal(plan.plans[0].allocations.length, 2);
  assert.equal(plan.plans[0].allocations[0].label, "MUSD Savings Vault");
  assert.equal(plan.plans[0].allocations[0].amountMUSD, 400);
  assert.equal(plan.plans[0].allocations[1].label, "Tigris Basic Stable MUSD/mUSDC");
  assert.equal(plan.plans[0].allocations[1].amountMUSD, 50);
});

test("buildTermYieldPlan blocks new allocation when buffer would be breached", () => {
  const plan = buildTermYieldPlan({
    ...BASE_SNAPSHOT,
    composition: {
      idleMUSD: "300",
      liquidityBufferMUSD: "400",
      deployableSurplusMUSD: "0",
    },
  });

  assert.equal(plan.posture, "blocked");
  assert.match(plan.plans[0].blockedReason, /below the required operating buffer/);
  assert.equal(plan.plans[0].allocations.length, 0);
});

test("buildTermYieldPlan blocks new allocation when collateral health is weak", () => {
  const plan = buildTermYieldPlan({
    ...BASE_SNAPSHOT,
    health: {
      belowWarningRatio: true,
      belowCriticalRatio: false,
    },
  });

  assert.equal(plan.posture, "blocked");
  assert.match(plan.plans[0].blockedReason, /warning state/);
});

test("buildTermYieldPlan respects term unwind constraints", () => {
  const plan = buildTermYieldPlan({
    ...BASE_SNAPSHOT,
    termYieldPlanner: {
      asOfDate: "2026-05-08",
      windowsDays: [3, 30],
    },
    sleeves: [
      {
        label: "Fast Savings Sleeve",
        approved: true,
        capMUSD: "100",
        remainingCapacityMUSD: "100",
        annualYieldBps: "300",
        riskTier: "low",
        unwindDays: "0",
      },
      {
        label: "Fourteen Day Vault",
        approved: true,
        capMUSD: "500",
        remainingCapacityMUSD: "500",
        annualYieldBps: "1000",
        riskTier: "medium",
        unwindDays: "14",
      },
    ],
  });

  assert.deepEqual(
    plan.plans[0].allocations.map((allocation) => allocation.label),
    ["Fast Savings Sleeve"],
  );
  assert.deepEqual(
    plan.plans[1].allocations.map((allocation) => allocation.label),
    ["Fourteen Day Vault", "Fast Savings Sleeve"],
  );
});

test("buildTermYieldPlan keeps BTC sleeve candidates out of MUSD allocation plans", () => {
  const plan = buildTermYieldPlan(BASE_SNAPSHOT);

  assert.equal(
    plan.plans.some((windowPlan) =>
      windowPlan.allocations.some((allocation) => /btc/i.test(allocation.label)),
    ),
    false,
  );
  assert.match(plan.btcPlanningNotes.join(" "), /BTC-correlated candidate/);
  assert.match(plan.btcPlanningNotes.join(" "), /not part of MUSD term-yield allocatable surplus/);
});
