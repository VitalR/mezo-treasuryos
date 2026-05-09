# Treasury Risk Keeper

Deterministic liquidation-defense service for the TreasuryOS demo.

It does not replace onchain policy. It reads a treasury snapshot, applies the selected strategy profile, computes weighted defense capacity, and recommends the least disruptive allowed defense action.

```sh
npm run risk-keeper:demo
npm run risk-keeper:propose
npm run risk-keeper:test
```

Modes:

```sh
RISK_KEEPER_MODE=dry-run npm run risk-keeper:demo
RISK_KEEPER_MODE=propose npm run risk-keeper:demo
RISK_KEEPER_MODE=execute RISK_KEEPER_EXECUTE_CONFIRM=true npm run risk-keeper:demo
```

`risk-keeper:demo` uses `sample-warning-repay-snapshot.json`, where an active treasury is in WARNING and direct idle-MUSD repayment is preferred. Execute mode shells out to one `cast send` against `TreasuryAutomationExecutor`. It requires `RISK_KEEPER_PRIVATE_KEY`, `TREASURY_AUTOMATION_EXECUTOR` or `RISK_KEEPER_AUTOMATION_EXECUTOR`, `RISK_KEEPER_TREASURY_ACCOUNT` or `TREASURY_ACCOUNT`, `ACTIVE_MEZO_RPC_URL` or `MEZO_RPC_URL`, and `RISK_KEEPER_MAX_ACTIONS_PER_RUN=1`. The key should be an allowlisted keeper EOA with gas only. It should not custody BTC, MUSD, receipt tokens, or LP tokens.

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
