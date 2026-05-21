# Final Demo Runbook

## Goal

Show TreasuryOS as a policy-governed BTC treasury operating layer on Mezo:

- client treasury is owned by a TreasuryMultisig, not an EOA
- BTC collateral backs a Mezo MUSD position
- MUSD operating capital is split between idle buffer and MUSD Savings
- policy blocks unsafe or over-threshold actions
- keeper can propose warning/critical actions
- keeper can execute one bounded live restore action while holding only gas
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
- live keeper restore transaction
- advisory memo summary

The command is read-only. It does not move funds.

## Live Transactions

| Scenario | Tx |
| --- | --- |
| Open fresh TreasuryOS position | `0xe0fe153b870514833ca3962bd38052cc2fbbd3ab659d298c0f3604614905c21a` |
| Allocate MUSD to Savings via `TreasuryAccount.allocate` | `0x7e730bb74b46b20585890124a458aa0fe7d4414caf1cac83e0826061f4ebd96b` |
| Multisig operating disbursement to create buffer shortfall | `0xc5e12729a6f2faa17d3f54e435d3ab930d9e6143d63779014c742615768dd641` |
| Keeper restores buffer from MUSD Savings | `0x88006ce0bdbb0c1e433b9df31f99d11b85ccd2e0cd89e4e059112d88bf7087be` |

## Current Live State

After keeper restore:

- BTC collateral: `0.05 BTC`
- total debt: about `2,001.8 MUSD`
- idle MUSD: `500 MUSD`
- MUSD Savings allocation: `900 MUSD`
- keeper action: `restoreBufferFromSavings`
- fees: disabled

## Scenario Coverage

1. Healthy live treasury
   - keeper result: `MONITOR`
   - no transaction needed

2. Warning replay
   - keeper result: `REPAY_DEBT_FROM_IDLE_MUSD`
   - proposal/calldata generated
   - live execution intentionally not used because Mezo minimum net-debt floor blocks repayment on the tiny demo trove

3. Critical replay
   - keeper result: `WITHDRAW_FAST_MUSD_SLEEVE_AND_REPAY`
   - proposal/calldata generated
   - demonstrates sleeve-funded defense logic

4. Live bounded automation
   - keeper EOA calls `TreasuryAutomationExecutor`
   - executor calls `TreasuryAccount.restoreLiquidityBuffer`
   - MUSD moves from Savings back to TreasuryAccount
   - keeper never custodies BTC, MUSD, sMUSD, or LP tokens

## Supporting Commands

```bash
make demo-status
make verify-mezo-testnet-status
npm run state:snapshot -- --manifest deployments/mezo-testnet-client.json --out draft/internal/live-latest-snapshot.json
node services/yield-console/render.mjs draft/internal/live-fixed-stack-after-keeper-restore-snapshot.json
node services/treasury-advisor/run.mjs draft/internal/live-fixed-stack-after-keeper-restore-snapshot.json
```

## Narrative Boundaries

- AI/advisor recommends and explains; it does not sign or move funds.
- The keeper is not trusted with assets. It is allowlisted only for bounded executor functions.
- Emergency/defense actions are not fee-charged.
- Protocol fees are deployed for future monetization but disabled for the hackathon demo.
- BTC sleeve execution remains advanced/guarded; final demo should rely on MUSD Savings as the reliable live sleeve.
