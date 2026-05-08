# BTC Reserve And Yield Sleeves

## Product Boundary

TreasuryOS manages two related but separate treasury balance sheets:

- **MUSD operating capital:** borrowed working capital that must preserve a liquid MUSD operating buffer before allocation.
- **BTC-denominated treasury exposure:** idle BTC reserve, BTC collateral, and future BTC-correlated yield positions.

These should not share the same accounting path. V1 MUSD sleeves are policy-governed destinations for surplus MUSD. BTC sleeves need a separate BTC-principal policy and reporting model before they can become executable.

The product line is:

**TreasuryOS is not a wrapper around yield protocols. It is the institutional treasury operating layer that decides, controls, accounts for, automates, and reports how BTC treasury capital is deployed.**

## Why MUSD And BTC Sleeves Differ

MUSD sleeves:

- manage borrowed operating capital;
- preserve the required MUSD operating buffer;
- support disbursement, repayment preparation, and buffer-restoration workflows;
- can use the current MUSD `AllocationRouter` and `TreasuryPolicyEngine` accounting.

BTC sleeves:

- manage retained BTC-denominated or BTC-correlated treasury exposure;
- should not be mixed with MUSD buffer accounting;
- require separate reporting for BTC principal, BTC receipt assets, BTC-correlated LP exposure, and withdrawal constraints;
- need BTC reserve floors, collateral-health constraints, sleeve caps in BTC terms, and elevated approvals for directional LPs.

## BTC Reserve Buckets

`BTCReservePolicy` tracks BTC-denominated reporting buckets separately from MUSD allocation accounting:

- `idleBTCReserve`: BTC held idle and potentially available only after reserve floors are met.
- `collateralBTC`: BTC committed to the Mezo borrow position.
- `emergencyBTCReserve`: BTC explicitly reserved for emergency liquidity and not available for yield allocation.
- `yieldActiveBTC`: BTC principal already active in BTC-denominated sleeve exposure.
- `pendingWithdrawBTC`: BTC requested for withdrawal but not yet returned to idle reserve.

These buckets are accounting and policy inputs. They do not move BTC. They let TreasuryOS explain whether a proposed BTC sleeve allocation would be permitted before any future router/handler touches principal.

`TreasuryAccount.fundIdleBTC()` is the explicit way to add idle BTC reserve inventory to a Treasury Account. Direct native BTC receives are accepted but do not increment `idleBTC`, which avoids double-counting BTC returned by Mezo borrow lifecycle calls or accidental transfers.

## V1 BTC Policy Scaffold

`BTCReservePolicy` is a V1 scaffold, not an execution router. It supports:

- reserve policy configuration: `minIdleBTCReserve`, `emergencyBTCReserve`, `maxYieldBTCBps`, `maxPerSleeveBTCBps`, `maxDirectionalBTCBps`, `maxBTCAssetDepegBps`, `maxSwapPriceImpactBps`, `maxSlippageBps`, `collateralWarningCRBps`, and `btcYieldPaused`;
- sleeve risk classes: `BTC_CORRELATED`, `BTC_DIRECTIONAL_LP`, `SPECULATIVE`, `EXTERNAL_VAULT`, and `DISABLED`;
- approval levels: `OPERATOR`, `APPROVER`, `MULTISIG`, `MULTISIG_WITH_RISK_OVERRIDE`, and `DISABLED`;
- preview-only BTC allocation decisions with `allowed`, `reason`, `availableBTC`, `projectedYieldActiveBTC`, `requiredApproval`, and `requiredApprovalLevel`;
- indexable events for reserve policy, bucket updates, sleeve configuration, exposure updates, and allocation previews.

The policy intentionally requires treasury-admin configuration. BTC-correlated sleeves such as `mcbBTC/BTC` require multisig-level approval. Directional BTC LPs require a multisig risk override. Automation must not move BTC principal in V1.

## V1 Testnet Targets

### MUSD Savings Vault

- Address: `0x6f461c68B2c5492C0F5CCEc5a264d692aA7A8e16`
- Deposit token: MUSD
- Receipt token: `sMUSD`
- V1 role: primary conservative MUSD operating-capital sleeve

Live ABI inspection shows the vault supports the current `MUSDSavingsRateHandler` surface: `deposit(uint256)`, `withdraw(uint256)`, `claimYield()`, `yieldToken()`, ERC20 receipt balances, and claimable-yield accounting. Testnet APR should be treated as demo data, not as a production guarantee.

### Tigris Basic Stable MUSD/mUSDC

- Pool: `0x525F049A4494dA0a6c87E3C4df55f9929765Dc3e`
- Type: Basic Stable
- Token path: MUSD / mUSDC
- Stable flag: `true`
- V1 role: optional stablecoin LP sleeve for surplus MUSD operating capital

This is the primary Tigris V1 candidate. It belongs in the existing MUSD allocation path because the treasury contributes MUSD, keeps a MUSD buffer, accounts for a MUSD-denominated destination cap, and unwinds back to MUSD for buffer/debt workflows.

Current validation status: `make mezo-yield-fork-test` passes a live Mezo testnet fork simulation for TreasuryOS handler deposit and withdrawal against this pool. The handler uses router quotes for swap output, add-liquidity token minimums, remove-liquidity token minimums, and LP liquidity minted, which matters because testnet `mUSDC` has different decimals and the pool can be very imbalanced. This is not a broadcast transaction test. Re-check pool reserves before the final demo and keep MUSD Savings Vault as the reliable primary sleeve if Tigris liquidity is thin.

### Tigris Basic Stable mcbBTC/BTC

- Pool: `0xc8BA1027e1D4f9C646B9963Eab89B1e7CF2A476E`
- Type: Basic Stable
- Token0: `mcbBTC` at `0x2278cAAe0009E8A325A346FeA573eF23C5756dbF`, 8 decimals
- Token1: ERC20 `BTC` at `0x7b7C000000000000000000000000000000000000`, 18 decimals
- Stable flag: `true`
- V1 role: BTC-denominated / BTC-correlated sleeve candidate

This is the strongest testnet bridge to the Bitcoin Yield & Investment angle because it preserves BTC-correlated exposure better than a BTC/stable LP. It should not be routed through the MUSD `TigrisStablePoolHandler` because the accounting unit, reserve constraints, and approval posture are different. Treat it as V1 reporting/scaffold unless a separate BTC policy and handler are implemented and tested.

Current validation status:

- Manual Mezo testnet transactions show `BTC` is represented by the BTCCaller/precompile address `0x7b7C000000000000000000000000000000000000`.
- The observed BTC swap and add-liquidity transactions have `msg.value = 0`, use the live Tigris router ABI, and emit ERC20-style `Transfer` logs from the BTC precompile address.
- The add-liquidity selector is `addLiquidity(address,address,bool,uint256,uint256,uint256,uint256,address,uint256)`.
- The swap selector is `swapExactTokensForTokens(uint256,uint256,(address,address,bool,address)[],address,uint256)`.
- The observed BTC pool router in the UI transactions is `0xd245bec6836d85e159763a5d2bfce7cbc3488e03`; the configured Tigris router may differ, so BTC experiments should configure the router explicitly.
- The observed LP gauge is `0x65d875b9ac9b50f3561544f83dd5f90043f5862b` and uses `deposit(uint256,address)`.

This reduces the blocker from "native BTC mechanics are unknown" to a narrower execution-readiness blocker: BTC sleeve execution requires BTCReservePolicy limits, BTC-denominated exposure accounting, mcbBTC swap min-out controls, LP min-liquidity controls, receipt/staked-LP accounting, and multisig approval. It still should not be a default V1 execution path until a tiny controlled deposit, withdraw, stake, unstake, and reward-claim flow has been broadcast and reviewed.

Useful inspection command:

```sh
make btc-sleeve-targets
```

Useful planner command:

```sh
npm run demo:btc-sleeve-plan
```

The planner is reserve-ratio aware. It does not assume a naive 50/50 BTC split. Given a requested idle BTC amount, current mcbBTC/BTC reserves, and a BTC -> mcbBTC quote, it solves for the BTC swap amount that leaves the expected mcbBTC output and remaining BTC aligned with the pool reserve ratio. It then estimates LP tokens, applies slippage to produce `minMCBTCOut` and `minLPTokens`, and evaluates BTC policy guardrails.

## Risk Classification

- **MUSD Savings Vault:** conservative operating-capital yield. It is the reliable V1 sleeve for the demo, subject to policy caps and buffer checks.
- **MUSD/mUSDC Basic Stable:** stablecoin LP operating-capital yield. It adds protocol differentiation but should be used only with min-out/slippage checks and healthy testnet liquidity.
- **mcbBTC/BTC Basic Stable:** BTC-denominated / BTC-correlated yield candidate. It maps to `BTC_CORRELATED` in the policy scaffold.
- **BTC/MUSD or MUSD/BTC:** directional active treasury LP. This is not a conservative default sleeve; it may be useful for a treasury intentionally accepting partial stablecoin exposure or trying to accumulate BTC during downside moves.
- **BTC/MEZO or similar pools:** speculative BTC exposure. These map to `SPECULATIVE` and are disabled by default.

## Roadmap Classification

### V1

- MUSD Savings Vault as the primary allocation sleeve.
- MUSD/mUSDC Basic Stable after live-fork validation and a final liquidity sanity check.
- BTC-denominated accounting and policy scaffold through `BTCReservePolicy`.
- mcbBTC/BTC research/scaffold in docs and reporting, marked experimental until the BTC execution handler is transaction-tested.
- BTC sleeve planner that uses idle BTC reserve, pool reserves, and a BTC -> mcbBTC quote to calculate a proposal-only LP entry plan.
- AI memo that distinguishes MUSD operating capital from BTC reserve/collateral.

### V1 If Time

- mcbBTC/BTC preview flow wired into reviewer reporting through `BTCReservePolicy`.
- BTC sleeve reporting fields for principal asset, receipt token, current exposure, risk class, and withdrawal constraints.
- `IBTCYieldSleeveHandler` preview interface for future BTC sleeve handlers.

### V1.5

- mcbBTC/BTC guarded execution after controlled testnet broadcast validation.
- `BTCYieldIntent` that creates multisig proposals rather than direct autonomous execution.
- BTC treasury risk profiles: conservative, balanced, active.
- BTC sleeve reporting and BTC-denominated exposure/PnL accounting.
- BTC/stable LP classification with elevated approval rules.
- BTC sleeve automation proposals, not uncontrolled execution.
- LP gauge staking and reward claiming, with reward claims optionally operator-executable only when no BTC principal moves.

### V2 / Production

- veBTC integration.
- Mellow / Mezo vault integrations if accessible.
- Enclave or institutional BTC yield integration if accessible.
- `BTCYieldRouter` and `BTCYieldPositionRegistry`.
- BTC lock-duration and withdrawal-delay aware automation.
- richer investment committee reporting.
- multi-sleeve BTC allocation strategy.

## Future Onchain Shape

Add executable BTC sleeves only when there is a real target and a separate accounting path.

Minimal future components:

- `IBTCYieldSleeveHandler`
- `BTCReservePolicy`
- `BTCReserveAllocationRouter`
- `BTCYieldPositionRegistry`

Minimal handler interface:

- deposit native BTC or approved BTC-correlated ERC20 asset;
- withdraw;
- claim rewards if supported;
- preview BTC-equivalent exposure;
- report principal asset, receipt asset, receipt balance, allocated BTC, claimable rewards, lock duration, withdrawal delay, and risk class.

Minimal policy checks:

- keep minimum idle BTC reserve;
- do not touch BTC collateral needed for position health;
- cap each BTC sleeve in BTC terms;
- require elevated approval for BTC/stable LP;
- block automation when collateral health weakens;
- treat long-lock sleeves as proposal-only.

## veBTC Notes

Mezo testnet also exposes a veBTC lock flow. Manual UI testing shows BTC approval followed by `createLock`, with lock duration, voting power, and withdraw/manage flows. This is real and strategically relevant, but it is not a V1 execution target. It belongs in V1.5/V2 because it introduces lock-duration accounting, withdrawal constraints, transfer/merge behavior, and principal immobility that the current buffer-restoration automation must not ignore.

## Reporting And AI Memo Rules

Treasury reports should distinguish:

- idle MUSD, required buffer, allocatable surplus, allocated MUSD, MUSD Savings Vault exposure, MUSD/mUSDC LP exposure, estimated net carry, and ability to restore buffer;
- native BTC reserve, BTC collateral, BTC allocated to BTC-correlated sleeve candidates, receipt or LP tokens, risk class, and withdrawal constraints.

AI memo output may recommend or explain:

- keep a BTC reserve floor unallocated;
- use BTC as collateral before chasing yield when health is weakening;
- route only surplus MUSD into approved MUSD sleeves;
- prefer mcbBTC/BTC over BTC/MUSD when the objective is BTC-correlated exposure;
- require stronger approval for directional BTC/stable LPs.

AI must not execute funds directly or bypass policy.
