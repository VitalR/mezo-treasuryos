import assert from "node:assert/strict";
import test from "node:test";

import { buildTreasuryAdvisorReport } from "./advisor.mjs";

const BASE_SNAPSHOT = {
  treasuryName: "Test Treasury",
  composition: {
    idleMUSD: "1000",
    liquidityBufferMUSD: "500",
    deployableSurplusMUSD: "500",
  },
  position: {
    totalDebtMUSD: "1200",
  },
  health: {
    belowWarningRatio: false,
    belowCriticalRatio: false,
  },
  sleeves: [
    {
      label: "Savings",
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
      label: "Term Sleeve",
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
};

test("buildTreasuryAdvisorReport allocates surplus across approved sleeves within caps", () => {
  const report = buildTreasuryAdvisorReport(BASE_SNAPSHOT);

  assert.equal(report.summary.riskState, "healthy");
  assert.equal(report.allocationPlan.length, 1);
  assert.equal(report.allocationPlan[0].label, "Savings");
  assert.equal(report.allocationPlan[0].amountMUSD, 500);
  assert.equal(report.automationAction.action, "NO_AUTOMATION_NEEDED");
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
  assert.equal(report.automationAction.sleeve, "Savings");
  assert.equal(report.automationAction.amountMUSD, 100);
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
