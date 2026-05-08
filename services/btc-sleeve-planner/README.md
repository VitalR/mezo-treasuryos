# BTC Sleeve Planner

Preview-only planner for the Tigris `mcbBTC/BTC` BTC-correlated sleeve.

The planner answers: if the treasury proposes allocating `X` idle BTC into the `mcbBTC/BTC` sleeve, how much BTC should be swapped to mcbBTC, how much BTC remains for the LP side, what minimum outputs should be required, and whether the BTC reserve policy should allow the proposal.

It does not move funds.

Run the sample:

```sh
npm run demo:btc-sleeve-plan
```

The split is reserve-ratio aware:

1. Read pool reserves for mcbBTC and BTC.
2. Read or provide a BTC -> mcbBTC quote.
3. Solve for the BTC swap amount that leaves the post-swap mcbBTC and remaining BTC aligned with the pool reserve ratio.
4. Estimate LP tokens from the limiting side of the deposit.
5. Apply slippage to produce `minMCBTCOut` and `minLPTokens`.
6. Evaluate BTC policy guardrails: idle BTC reserve, emergency reserve, sleeve cap, aggregate yield cap, approval level, price impact, and slippage.

Execution remains V1.5 until a guarded handler is transaction-tested for swap, add liquidity, remove liquidity, optional staking, unstaking, and reward claim.
