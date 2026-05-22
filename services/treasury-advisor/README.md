# Treasury Advisor

Deterministic advisory layer for TreasuryOS reporting and demo flows.

It consumes the same snapshot shape produced by `services/spectrum-state` and produces:

- policy-aware allocation recommendations across approved MUSD-denominated sleeves
- 7/30/60-day projected yield assumptions
- buffer shortfall and collateral-health recommendations
- BTC reserve, BTC collateral, and BTC-denominated sleeve-candidate notes
- bounded automation suggestions such as buffer restoration or de-risk repayment
- profile-aware opportunity review across MUSD Savings, Tigris MUSD/mUSDC, and mcbBTC/BTC
- optional OpenAI-written memo generated from deterministic advisor facts

BTC sleeve notes are advisory and reporting-only unless a snapshot explicitly marks a BTC sleeve as approved and executable. V1 keeps BTC reserve accounting separate from MUSD sleeve allocation.

Run the sample:

```sh
npm run advisor:demo
```

Run the live demo opportunity advisor:

```sh
make advisor-opportunities
```

Run the same advisor with an AI-written memo, if `OPENAI_API_KEY` is configured:

```sh
make advisor-opportunities-ai
```

Profiles can be selected with `--profile conservative`, `--profile balanced`, `--profile active`, or
`--profile aggressive-demo`. The profile changes the recommendation posture; it does not bypass policy or execute
transactions.

Run tests:

```sh
npm run advisor:test
```

This is not an execution agent. It does not sign transactions, call contracts, bypass `TreasuryPolicyEngine`, or control
funds. The AI memo is a narrative layer over deterministic facts; it is not trusted for policy decisions.
