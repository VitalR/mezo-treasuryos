# Goldsky Indexing Scaffold

Goldsky can power the TreasuryOS reporting layer on Mezo testnet:

- treasury activity timeline
- policy configuration and pause history
- idle versus allocated MUSD history
- sleeve deposit/withdraw/yield events
- automation history
- multisig proposal and batch execution history
- future AI treasury memo context

Target network slug:

```text
mezo-testnet
```

## Current Status

This is a scaffold, not a published indexer.

Before publishing:

1. Deploy TreasuryOS core/client contracts.
2. Copy deployed addresses into `subgraph.yaml`.
3. Copy ABI JSON files from `contracts/out/**` into `indexer/goldsky/abis/`.
4. Set realistic `startBlock` values from deployment manifests.
5. Run Goldsky codegen/build/deploy commands for the target environment.

The scaffold indexes real events that exist today. It does not invent missing policy-decision events.

The `TreasuryAccount` template is created from `TreasuryAccountFactory.TreasuryAccountDeployed`. The `TreasuryMultisig` template is included for client-control history, but the current contracts do not emit a factory event that reveals every multisig address. For the final demo, either add the deployed multisig as a static data source in `subgraph.yaml` or add a minimal discovery event to the onboarding/deployment surface before publishing.

## Existing Useful Events

Core:

- `TreasuryAccountFactory.TreasuryAccountDeployed`
- `TreasuryPolicyEngine.AccountPolicyInitialized`
- `TreasuryPolicyEngine.PauseUpdated`
- `TreasuryPolicyEngine.AutomationExecutorUpdated`
- `TreasuryPolicyEngine.AutomationLimitsUpdated`
- `TreasuryPolicyEngine.DestinationPolicyUpdated`
- `TreasuryAccount.PositionOpened`
- `TreasuryAccount.TreasuryDisbursed`
- `TreasuryAccount.AllocationExecuted`
- `TreasuryAccount.WithdrawalExecuted`
- `TreasuryAccount.YieldClaimedFromDestination`
- `TreasuryAccount.LiquidityBufferRestored`
- `TreasuryAccount.SleeveUnwoundAndDebtRepaid`

Sleeves:

- `MUSDSavingsRateHandler.SavingsDepositRouted`
- `MUSDSavingsRateHandler.SavingsWithdrawalRouted`
- `MUSDSavingsRateHandler.SavingsYieldClaimed`
- `TigrisStablePoolHandler.StablePoolDepositRouted`
- `TigrisStablePoolHandler.StablePoolWithdrawalRouted`

Automation:

- `TreasuryAutomationExecutor.BufferRestoreExecuted`
- `TreasuryAutomationExecutor.DeRiskRepaymentExecuted`

Multisig:

- `TreasuryMultisig.TransactionProposed`
- `TreasuryMultisig.TransactionConfirmed`
- `TreasuryMultisig.TransactionExecuted`
- `TreasuryMultisig.BatchProposed`
- `TreasuryMultisig.BatchConfirmed`
- `TreasuryMultisig.BatchExecuted`

## Missing Events Worth Adding Later

Do not add these unless they materially improve the final reporting demo:

- deterministic `PolicyDecisionPreviewed` is not appropriate onchain because previews are reads
- explicit blocked-action events would require catchable execution wrappers or offchain logging
- term-plan events should remain offchain/reporting in V1

For V1, the reporting layer can combine onchain events with read-model snapshots from `services/spectrum-state`.
