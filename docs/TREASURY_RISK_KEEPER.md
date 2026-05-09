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

`TreasuryPolicyEngine` stores the hard limits across risk controls and automation settings:

- `minOpenCollateralRatioBps`
- `targetCollateralRatioBps`
- `stressDropBps`
- `minPostStressCollateralRatioBps`
- `minIdleBTCReserve`
- `maxAutoIdleBTCTopUp`
- `allowAutomationBTCTopUp`
- `maxAutoDebtRepay`
- `allowAutoDebtRepay`

`TreasuryAccount` calls `validateProjectedPosition` before opening a trove, borrowing more MUSD, withdrawing collateral, or adjusting into a weaker position. Purely risk-reducing actions are not blocked by projected-position checks.

`TreasuryAccount.addIdleBTCToCollateral` moves accounted `idleBTC` into Mezo collateral. Plain `receive()` still does not mutate `idleBTC`; reserve accounting changes only through explicit treasury flows such as `fundIdleBTC`, position withdrawals, close, BTC sleeve settlement, or the new top-up path.

`TreasuryAutomationExecutor.topUpCollateralFromIdleBTC` can call that path only when:

- the automation caller is authorized
- the account policy points to the executor
- automation BTC top-up is enabled
- the amount is within `maxAutoIdleBTCTopUp`
- the post-action idle BTC reserve remains above `minIdleBTCReserve`

`TreasuryAutomationExecutor.repayDebtFromIdleMUSD` is the simplest defensive action. It lets an allowlisted keeper repay Mezo debt from idle MUSD already held by the Treasury Account. The keeper pays gas only; MUSD never leaves the Treasury Account except into the Mezo repayment flow. `TreasuryPolicyEngine` reuses `maxAutoDebtRepay` and `allowAutoDebtRepay` for this path.

## Offchain Keeper

The keeper is deterministic and dry-run first:

```sh
npm run risk-keeper:demo
npm run risk-keeper:propose
```

It supports three modes:

- `dry-run`: print state, defense capacity, recommendation, and expected action.
- `propose`: print the executor target, function signature, args, and `cast calldata` helper for a multisig proposal.
- `execute`: send one whitelisted `TreasuryAutomationExecutor` transaction from an allowlisted keeper EOA, only when `RISK_KEEPER_EXECUTE_CONFIRM=true`.

Required execution env:

- `RISK_KEEPER_PRIVATE_KEY`
- `TREASURY_AUTOMATION_EXECUTOR` or `RISK_KEEPER_AUTOMATION_EXECUTOR`
- `RISK_KEEPER_TREASURY_ACCOUNT` or `TREASURY_ACCOUNT`
- `ACTIVE_MEZO_RPC_URL` or `MEZO_RPC_URL`
- `RISK_KEEPER_EXECUTE_CONFIRM=true`
- `RISK_KEEPER_MAX_ACTIONS_PER_RUN=1`
- `RISK_KEEPER_UPPER_HINT` and `RISK_KEEPER_LOWER_HINT` when Mezo sorted-trove hints are available

`npm run risk-keeper:demo` uses `sample-warning-repay-snapshot.json`, a WARNING-state fixture where active treasury policy prefers direct idle-MUSD repayment. `RISK_KEEPER_MODE=propose npm run risk-keeper:demo` prints the exact executor target, signature, args, and calldata helper. Execute mode remains intentionally narrow: one run can send exactly one whitelisted executor call.

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
4. Run `npm run risk-keeper:demo` and show a WARNING state.
5. Simulate a BTC price drop in the snapshot.
6. Keeper recommends direct idle-MUSD repayment when that is the least disruptive defense action.
7. Run `RISK_KEEPER_MODE=propose npm run risk-keeper:demo` to show the multisig-ready calldata.
8. If configured and explicitly confirmed, `TreasuryAutomationExecutor` executes exactly one allowlisted repayment, capped by `maxAutoDebtRepay`.
9. Advisor/reporting explains why the system blocked new risky allocation and how the position was defended.

## AI Boundary

AI can summarize the keeper output, explain tradeoffs, and draft a treasury memo. It must not sign, bypass `TreasuryPolicyEngine`, or move funds directly.
