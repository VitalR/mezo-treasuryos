# Treasury Risk Keeper

Deterministic liquidation-defense service for the TreasuryOS demo.

It does not replace onchain policy. It reads a treasury snapshot, applies the selected strategy profile, computes weighted defense capacity, and recommends the least disruptive allowed defense action.

```sh
npm run risk-keeper:demo
npm run risk-keeper:test
```

## Model

The keeper treats defense liquidity by how quickly it can protect a BTC-backed MUSD position:

- idle MUSD above the operating buffer counts directly
- immediately withdrawable MUSD Savings-style sleeves count with a small haircut
- MUSD LP sleeves count with a larger haircut
- idle BTC above the reserve floor counts as collateral top-up capacity with a haircut
- offchain withdrawn MUSD does not count unless explicitly imported into the snapshot

The action choice is strategy-aware. Balanced and conservative treasuries can prefer adding idle BTC to collateral before unwinding MUSD Savings. Active treasuries can prefer MUSD repayment first. Critical or unrecoverable states block new borrow, MUSD allocation, and BTC yield allocation.

## Boundaries

The keeper is dry-run/reporting-first. Execution must go through `TreasuryAutomationExecutor`, `TreasuryAccount`, and `TreasuryPolicyEngine` hard caps. AI memo layers may explain the recommendation, but they cannot bypass policy or move funds.
