import assert from "node:assert/strict";
import test from "node:test";

import { buildBTCSleevePlan } from "./planner.mjs";

const BASE_SNAPSHOT = {
  treasuryName: "Test Treasury",
  requestedPrincipalBTC: "0.05",
  composition: {
    idleBTC: "0.42",
  },
  position: {
    collateralBTC: "18.5",
  },
  btcReserveBuckets: {
    idleBTCReserve: "0.42",
    collateralBTC: "18.5",
    emergencyBTCReserve: "0.25",
    yieldActiveBTC: "0",
    pendingWithdrawBTC: "0",
  },
  btcReservePolicy: {
    minIdleBTCReserve: "0.25",
    emergencyBTCReserve: "0.25",
    maxYieldBTCBps: "3000",
    maxPerSleeveBTCBps: "1000",
    maxSwapPriceImpactBps: "5000",
    maxSlippageBps: "100",
    btcYieldPaused: false,
  },
  btcSleeveTarget: {
    label: "Tigris mcbBTC/BTC stable pool candidate",
    destination: "0xc8BA1027e1D4f9C646B9963Eab89B1e7CF2A476E",
    approved: true,
    executable: false,
    riskClass: "BTC_CORRELATED",
    approvalLevel: "MULTISIG",
    sleeveCapBps: "1000",
    slippageBps: "100",
    referenceMcbtcPerBtc: "1",
    decimals: {
      btc: 18,
      mcbtc: 8,
      lp: 18,
    },
    reserves: {
      mcbtc: "0.05710118",
      btc: "0.30473538847054415",
    },
    quote: {
      inputBTC: "0.0001",
      outputMCBTC: "0.00005142",
    },
    totalSupplyLP: "0.000001700507993075",
  },
};

test("buildBTCSleevePlan computes a reserve-ratio-aware BTC to mcbBTC split", () => {
  const plan = buildBTCSleevePlan(BASE_SNAPSHOT);

  assert.equal(plan.policy.allowed, true);
  assert.equal(plan.execution.mode, "preview-only");
  assert.notEqual(plan.calculation.swapBTC, "0.025");
  assert.equal(plan.calculation.swapBTC, "0.01335412000638805");
  assert.equal(plan.calculation.remainingBTCForLP, "0.03664587999361195");
  assert.equal(plan.calculation.expectedMCBTCOut, "0.00686668");
  assert.equal(plan.calculation.minOutNonzero, true);
});

test("buildBTCSleevePlan blocks when idle BTC reserve is insufficient", () => {
  const plan = buildBTCSleevePlan({
    ...BASE_SNAPSHOT,
    requestedPrincipalBTC: "0.3",
  });

  assert.equal(plan.policy.allowed, false);
  assert.equal(plan.policy.reason, "InsufficientIdleBTCReserve");
});

test("buildBTCSleevePlan blocks price impact above policy cap", () => {
  const plan = buildBTCSleevePlan({
    ...BASE_SNAPSHOT,
    btcReservePolicy: {
      ...BASE_SNAPSHOT.btcReservePolicy,
      maxSwapPriceImpactBps: "500",
    },
  });

  assert.equal(plan.policy.allowed, false);
  assert.equal(plan.policy.reason, "SwapPriceImpactExceeded");
});

test("buildBTCSleevePlan blocks slippage above policy cap", () => {
  const plan = buildBTCSleevePlan({
    ...BASE_SNAPSHOT,
    btcSleeveTarget: {
      ...BASE_SNAPSHOT.btcSleeveTarget,
      slippageBps: "150",
    },
  });

  assert.equal(plan.policy.allowed, false);
  assert.equal(plan.policy.reason, "SlippageExceeded");
});

test("buildBTCSleevePlan blocks missing quotes instead of faking execution", () => {
  const plan = buildBTCSleevePlan({
    ...BASE_SNAPSHOT,
    btcSleeveTarget: {
      ...BASE_SNAPSHOT.btcSleeveTarget,
      quote: {
        inputBTC: "0",
        outputMCBTC: "0",
      },
    },
  });

  assert.equal(plan.policy.allowed, false);
  assert.equal(plan.policy.reason, "QuoteOrReserveUnavailable");
});
