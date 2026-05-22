# Final Demo Runbook

## Goal

Show TreasuryOS as a policy-governed BTC treasury operating layer on Mezo:

- client treasury is owned by a TreasuryMultisig, not an EOA
- BTC collateral backs a Mezo MUSD position
- MUSD operating capital is split between idle buffer and MUSD Savings
- policy blocks unsafe or over-threshold actions
- keeper can propose warning/critical actions
- keeper can execute bounded live restore and debt-repayment actions while holding only gas
- AI/advisor output is explanatory only
- protocol fees are deployed but disabled

## Primary Proof Command

```bash
make scenario-proof
```

This prints the judge-facing scenario matrix from the current live/internal snapshots:

- live deployed addresses
- Spectrum-backed snapshot metadata
- current BTC collateral, MUSD debt, idle MUSD, and Savings exposure
- policy-block proof
- keeper `MONITOR`, warning, and critical cases
- live keeper restore and idle-MUSD repayment transactions
- advisory memo summary

The command is read-only. It does not move funds.

## Judge Flow

Run this sequence for the final proof. Steps 1-5 are read-only and are the preferred judge flow.

```bash
make demo-status
make scenario-proof
make advisor-opportunities
node services/yield-console/render.mjs draft/internal/live-fixed-stack-after-keeper-repay-snapshot.json
make risk-keeper-propose-critical
```

Optional AI memo:

```bash
make advisor-opportunities-ai
```

The AI memo uses the deterministic advisor report as source data. It is a narrative layer only; it does not calculate
policy, sign, custody, or execute.

Talk track:

1. `make demo-status`
   - Shows Spectrum RPC on Mezo testnet, deployed fee contracts, MUSD Savings readiness, BTC sleeve status, and keeper readiness.
   - State clearly that fees are deployed but disabled, and BTC sleeve execution is not part of the core live demo.

2. `make scenario-proof`
   - Shows the live TreasuryAccount, multisig ownership, deployed addresses, active MUSD debt, MUSD Savings exposure, policy block, and live keeper tx proof.
   - Anchor the narrative on the execution boundary: TreasuryAccount owns positions and assets; keeper only calls bounded executor methods.

3. Advisor memo
   - Shows the advisor can explain current state and recommend allocation using policy-aware facts and the selected `balanced` profile.
   - Reads live Mezo opportunity metadata for MUSD Savings, Tigris MUSD/mUSDC, and Tigris mcbBTC/BTC.
   - Explains why mcbBTC/BTC is or is not usable from the current live quote, BTC policy/validation state, and treasury profile.
   - State clearly: the advisor is reporting only. It does not sign, custody, or bypass policy.

4. Yield console
   - Shows idle MUSD, required buffer, approved sleeve caps, current allocation, and BTC reserve/collateral split.
   - Use this to explain operating capital vs collateral vs BTC sleeve planning.

5. Critical keeper proposal
   - Shows the read-only calldata/proposal for `deRiskByRepayingFromSleeve`.
   - Uses `.env` to resolve `TREASURY_AUTOMATION_EXECUTOR`, `TREASURY_ACCOUNT`, and the MUSD Savings destination.
   - Do not execute this on the live tiny position; it is a proposal proof for the critical scenario, while live execution has already proven `restoreBufferFromSavings` and `repayDebtFromIdleMUSD`.

## Live Transactions

| Scenario | Tx |
| --- | --- |
| Open fresh TreasuryOS position | `0xe0fe153b870514833ca3962bd38052cc2fbbd3ab659d298c0f3604614905c21a` |
| Allocate MUSD to Savings via `TreasuryAccount.allocate` | `0x7e730bb74b46b20585890124a458aa0fe7d4414caf1cac83e0826061f4ebd96b` |
| Multisig operating disbursement to create buffer shortfall | `0xc5e12729a6f2faa17d3f54e435d3ab930d9e6143d63779014c742615768dd641` |
| Keeper restores buffer from MUSD Savings | `0x88006ce0bdbb0c1e433b9df31f99d11b85ccd2e0cd89e4e059112d88bf7087be` |
| Multisig draw creates repayment headroom | `0x721de359cf1e00def213f4024a6a37ea359f9fe6a4f8497c5b53986f0176490b` |
| Keeper repays debt from idle MUSD | `0x25441e1ec5309673d6515f63d628913350741192c1ec23f9f62a0a557d984933` |

## Current Live State

After keeper idle-MUSD repayment:

- BTC collateral: `0.05 BTC`
- total debt: about `2,026.86 MUSD`
- close debt: about `1,826.86 MUSD`
- idle MUSD: `525 MUSD`
- MUSD Savings allocation: `900 MUSD`
- keeper actions: `restoreBufferFromSavings`, then `repayDebtFromIdleMUSD`
- fees: disabled

## Scenario Coverage

1. Healthy live treasury
   - keeper result: `MONITOR`
   - no transaction needed

2. Warning replay
   - keeper result: `REPAY_DEBT_FROM_IDLE_MUSD`
   - proposal/calldata generated
   - live idle-MUSD repayment also executed after a small multisig-approved draw created protocol-floor headroom

3. Critical replay
   - keeper result: `WITHDRAW_FAST_MUSD_SLEEVE_AND_REPAY`
   - proposal/calldata generated
   - demonstrates sleeve-funded defense logic

4. Live bounded automation
   - keeper EOA calls `TreasuryAutomationExecutor`
   - executor calls `TreasuryAccount.restoreLiquidityBuffer`
   - MUSD moves from Savings back to TreasuryAccount
   - executor calls `TreasuryAccount.repayMUSD`
   - idle MUSD repays Mezo debt directly from the TreasuryAccount
   - keeper never custodies BTC, MUSD, sMUSD, or LP tokens

## Supporting Commands

```bash
make demo-status
make verify-mezo-testnet-status
npm run state:snapshot -- --manifest deployments/mezo-testnet-client.json --out draft/internal/live-latest-snapshot.json
node services/yield-console/render.mjs draft/internal/live-fixed-stack-after-keeper-repay-snapshot.json
node services/treasury-advisor/run.mjs draft/internal/live-fixed-stack-after-keeper-repay-snapshot.json
```

## Narrative Boundaries

- AI/advisor recommends and explains; it does not sign or move funds.
- The keeper is not trusted with assets. It is allowlisted only for bounded executor functions.
- Emergency/defense actions are not fee-charged.
- Protocol fees are deployed for future monetization but disabled for the hackathon demo.
- BTC sleeve execution remains advanced/guarded; final demo should rely on MUSD Savings as the reliable live sleeve.
