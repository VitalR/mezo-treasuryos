# Treasury Advisor

Deterministic advisory layer for TreasuryOS reporting and demo flows.

It consumes the same snapshot shape produced by `services/spectrum-state` and produces:

- policy-aware allocation recommendations across approved MUSD-denominated sleeves
- 7/30/60-day projected yield assumptions
- buffer shortfall and collateral-health recommendations
- BTC reserve, BTC collateral, and BTC-denominated sleeve-candidate notes
- bounded automation suggestions such as buffer restoration or de-risk repayment

BTC sleeve notes are advisory and reporting-only unless a snapshot explicitly marks a BTC sleeve as approved and executable. V1 keeps BTC reserve accounting separate from MUSD sleeve allocation.

Run the sample:

```sh
npm run advisor:demo
```

Run tests:

```sh
npm run advisor:test
```

This is not an execution agent. It does not sign transactions, call contracts, bypass `TreasuryPolicyEngine`, or control funds.
