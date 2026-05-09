# Treasury Risk Keeper

TreasuryOS should protect a BTC-backed MUSD position before it chases yield.

The V1 risk keeper adds the missing liquidation-defense layer:

- pre-borrow and adjust checks for projected collateral ratio
- post-stress checks for BTC price-drop scenarios
- weighted defense-capacity modeling across idle MUSD, fast MUSD sleeves, slower LP sleeves, and idle BTC
- a canonical idle BTC collateral top-up path
- bounded automation through `TreasuryAutomationExecutor`
- strategy-aware offchain recommendations for operators and reviewer memos

## Onchain Controls

`TreasuryPolicyEngine.RiskControlConfig` stores the hard limits:

- `minOpenCollateralRatioBps`
- `targetCollateralRatioBps`
- `stressDropBps`
- `minPostStressCollateralRatioBps`
- `minIdleBTCReserve`
- `maxAutoIdleBTCTopUp`
- `allowAutomationBTCTopUp`

`TreasuryAccount` calls `validateProjectedPosition` before opening a trove, borrowing more MUSD, withdrawing collateral, or adjusting into a weaker position. Purely risk-reducing actions are not blocked by projected-position checks.

`TreasuryAccount.addIdleBTCToCollateral` moves accounted `idleBTC` into Mezo collateral. Plain `receive()` still does not mutate `idleBTC`; reserve accounting changes only through explicit treasury flows such as `fundIdleBTC`, position withdrawals, close, BTC sleeve settlement, or the new top-up path.

`TreasuryAutomationExecutor.topUpCollateralFromIdleBTC` can call that path only when:

- the automation caller is authorized
- the account policy points to the executor
- automation BTC top-up is enabled
- the amount is within `maxAutoIdleBTCTopUp`
- the post-action idle BTC reserve remains above `minIdleBTCReserve`

## Offchain Keeper

The keeper is deterministic and dry-run first:

```sh
npm run risk-keeper:demo
```

It computes:

```text
effectiveDefenseCapacity =
  idleMUSD above operating buffer
+ fast MUSD sleeves * savings haircut
+ liquid MUSD LP * LP haircut
+ idle BTC value for collateral top-up * BTC haircut
```

The model intentionally does not assume offchain withdrawn MUSD is available. If a business has already used borrowed MUSD for payroll, vendors, or settlement, only explicitly reported/imported balances should count.

## Strategy Profiles

V1 profiles:

- Conservative Treasury: high target CR, large idle BTC reserve, MUSD Savings preferred, BTC yield capped or disabled.
- Balanced Treasury: target around 200%, MUSD Savings allowed, limited stable LP, idle BTC top-up allowed.
- Active Treasury: lower target, more MUSD deployment, stronger keeper response, repayment paths can be preferred before BTC top-up.
- Aggressive Demo Only: testnet/high-risk posture for stress demos, not an institutional default.

The action choice is not a fixed ladder. A balanced treasury can prefer adding idle BTC collateral before unwinding MUSD Savings. An active treasury can prefer idle MUSD or fast-sleeve repayment first. If the position is unrecoverable under stress, the keeper blocks new borrow, MUSD allocation, and BTC yield allocation.

## Demo Scenario

The recommended demo story:

1. Open a BTC-backed MUSD position above policy minimum CR.
2. Allocate some surplus MUSD to MUSD Savings.
3. Keep explicit idle BTC as emergency reserve.
4. Run `npm run risk-keeper:demo` and show a healthy or warning state.
5. Simulate a BTC price drop in the snapshot.
6. Keeper recommends the best allowed defense action.
7. If configured, `TreasuryAutomationExecutor` can add a bounded amount of idle BTC to collateral.
8. Advisor/reporting explains why the system blocked new risky allocation and how the position was defended.

## AI Boundary

AI can summarize the keeper output, explain tradeoffs, and draft a treasury memo. It must not sign, bypass `TreasuryPolicyEngine`, or move funds directly.
