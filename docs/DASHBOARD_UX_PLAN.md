# TreasuryOS Dashboard UX Plan

## Decision

Build a small read-only command center now that maps directly to the validated CLI and service outputs. Do not build a
transaction UI in V1.

The current scope is a lightweight operator dashboard backed by:

- deployed contract reads through the selected Mezo RPC provider;
- Goldsky-indexed event history once addresses, ABIs, and start blocks are filled;
- existing service outputs from `spectrum-state`, `yield-console`, `treasury-risk-keeper`, and `treasury-advisor`.
- generated dashboard JSON at `dashboard/public/data/dashboard-data.json`.

Run:

```bash
make dashboard-data
make dashboard-dev
```

## Product Boundary

The dashboard must preserve the same control story as the contracts:

- AI explains; it does not sign or bypass policy.
- The keeper proposes or executes only whitelisted, capped defensive actions.
- BTC principal movement is owner/multisig scoped.
- MUSD Savings is the reliable final demo sleeve.
- MUSD/mUSDC is optional and route-health dependent.
- mcbBTC/BTC is an advanced guarded path unless tiny broadcast validation has passed.
- Protocol fees are visible as disabled infrastructure, not active extraction.

## First Screen

Start with a working treasury console, not a landing page.

Primary panels:

- Treasury setup: Treasury Account, owner mode, operator, approver, keeper, strategy profile.
- BTC treasury plan: available BTC, collateral BTC, idle BTC reserve, emergency reserve, BTC sleeve candidate, approval requirement.
- Borrow position and risk: debt, collateral, current CR, target CR, warning/critical thresholds, post-stress CR, threshold BTC prices.
- Yield console: idle MUSD, required buffer, allocatable surplus, MUSD Savings exposure, optional MUSD/mUSDC exposure, estimated 7/30/60-day yield.
- Risk keeper: state, recommended action, reason, proposed calldata, policy result, expected post-action CR.
- AI treasury memo: summary, recommended action, allowed/blocked reason, approval path, risk notes.
- Activity timeline: account creation, funding, borrow, allocation, keeper action, policy block, fee/subscription event if any.

## CLI Mapping

Use current commands as the first data contract:

```bash
make demo-status
npm run demo:yield-console
npm run risk-keeper:demo
npm run risk-keeper:propose
npm run advisor:demo
npm run demo:btc-sleeve-plan
npm run state:probe
```

Dashboard widgets should be thin renderers over those same fields first. Contract reads and Goldsky indexing can replace static snapshots incrementally after deployment.

## Demo UX Priorities

1. Show a deployed Treasury Account and policy in one view.
2. Show BTC collateral, MUSD debt, idle MUSD, and idle BTC as separate buckets.
3. Show why surplus MUSD can or cannot be allocated.
4. Show one risk keeper recommendation and the exact executor calldata.
5. Show AI memo output next to the deterministic keeper output.
6. Show an event timeline that makes automation auditable.

## Deferred

- No frontend transaction builder until deployment addresses and manifest shape are stable.
- No live BTC sleeve execution UI until controlled broadcast validation exists.
- No fee payment UI while fees are disabled.
- No MEZO utility UI until it supports the core treasury workflow.
