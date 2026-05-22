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

This command reads the current treasury snapshot from `draft/internal/live-fixed-stack-after-keeper-repay-snapshot.json`
and fetches live Mezo testnet opportunity metadata before rendering the recommendation:

- MUSD Savings vault compatibility and capacity context
- Tigris MUSD/mUSDC pool compatibility and reserve/liquidity warning
- Tigris mcbBTC/BTC reserves, BTC -> mcbBTC quote, quote impact, and BTC sleeve validation status

`services/treasury-advisor/mezo-testnet-opportunities.json` remains a deterministic fixture for offline tests or
fallback demos. The final demo command uses `--live-opportunities`, so the mcbBTC/BTC block reason is based on the
current quote/validation read, not a hardcoded advisor conclusion.

## What Is Dynamic

`make advisor-opportunities` combines:

- current treasury state from the latest snapshot: idle MUSD, buffer, collateral, debt health, sleeve balances, and caps
- live Mezo testnet reads: Savings vault metadata, Tigris pool reserves, BTC -> mcbBTC quote, and validation manifest status
- selected profile: conservative, balanced, active, or aggressive-demo
- deterministic policy rules: buffer preservation, risk state, sleeve approval/caps, quote impact, and execution validation

The deterministic advisor decides the recommendation first. `make advisor-opportunities-ai` then asks OpenAI to write a
memo from that deterministic report. The AI memo is checked by prompt constraints, but the source of truth remains the
printed deterministic advisor section above it.

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
