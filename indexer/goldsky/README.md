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

- `TreasuryAccountFactory.TreasuryAdminApprovalUpdated`
- `TreasuryAccountFactory.TreasuryAccountDeployed`
- `TreasuryPolicyEngine.AccountPolicyInitialized`
- `TreasuryPolicyEngine.PauseUpdated`
- `TreasuryPolicyEngine.AutomationExecutorUpdated`
- `TreasuryPolicyEngine.AutomationThresholdsUpdated`
- `TreasuryPolicyEngine.AutomationLimitsUpdated`
- `TreasuryPolicyEngine.AutomationCapabilitiesUpdated`
- `TreasuryPolicyEngine.DestinationPolicyUpdated`
- `TreasuryPolicyEngine.AutomationEnabledUpdated`
- `TreasuryPolicyEngine.TreasuryAdminUpdated`
- `BTCReservePolicy.BTCReservePolicyConfigured`
- `BTCReservePolicy.BTCReserveBucketsUpdated`
- `BTCReservePolicy.BTCSleeveConfigured`
- `BTCReservePolicy.BTCSleeveExposureUpdated`
- `BTCReservePolicy.BTCDirectionalExposureUpdated`
- `BTCReservePolicy.BTCAllocationPreviewed`
- `BTCReservePolicy.BTCYieldAllocationBlocked`
- `BTCReservePolicy.BTCYieldAllocationApproved`

BTC policy events include reserve floors, sleeve caps, risk class, approval level, price-impact/slippage metadata, and recorded allow/block previews. Guarded BTC handler events are included for V1.5 reporting once the handler is deployed and controlled broadcast validation has passed.
- `TreasuryAccount.BorrowerOperationsUpdated`
- `TreasuryAccount.AllocationRouterUpdated`
- `TreasuryAccount.BTCReserveRouterUpdated`
- `TreasuryAccount.TreasuryAdminSynced`
- `TreasuryAccount.PositionOpened`
- `TreasuryAccount.CollateralDeposited`
- `TreasuryAccount.CollateralWithdrawn`
- `TreasuryAccount.DebtDrawn`
- `TreasuryAccount.DebtRepaid`
- `TreasuryAccount.PositionAdjusted`
- `TreasuryAccount.PositionClosed`
- `TreasuryAccount.TreasuryDisbursed`
- `TreasuryAccount.AllocationExecuted`
- `TreasuryAccount.WithdrawalExecuted`
- `TreasuryAccount.YieldClaimedFromDestination`
- `TreasuryAccount.IdleMUSDFunded`
- `TreasuryAccount.IdleBTCFunded`
- `TreasuryAccount.BTCAllocationExecuted`
- `TreasuryAccount.BTCWithdrawalSettled`
- `TreasuryAccount.WithdrawalSettledFromDestination`
- `TreasuryAccount.LiquidityBufferRestored`
- `TreasuryAccount.SleeveUnwoundAndDebtRepaid`

Sleeves:

- `MUSDSavingsRateHandler.SavingsDepositRouted`
- `MUSDSavingsRateHandler.SavingsWithdrawalRouted`
- `MUSDSavingsRateHandler.SavingsYieldClaimed`
- `TigrisStablePoolHandler.StablePoolDepositRouted`
- `TigrisStablePoolHandler.StablePoolWithdrawalRouted`
- `BTCReserveRouter.BTCHandlerRegistered`
- `BTCReserveRouter.BTCHandlerRemoved`
- `TigrisBTCStablePoolHandler.BTCStablePoolDepositRouted`
- `TigrisBTCStablePoolHandler.BTCStablePoolWithdrawalRouted`

Automation:

- `TreasuryAutomationExecutor.AutomationOperatorAuthorizationUpdated`
- `TreasuryAutomationExecutor.BufferRestoreExecuted`
- `TreasuryAutomationExecutor.DeRiskRepaymentExecuted`

Multisig:

- `TreasuryMultisig.TreasuryMultisigInitialized`
- `TreasuryMultisig.TransactionProposed`
- `TreasuryMultisig.TransactionConfirmed`
- `TreasuryMultisig.TransactionExecuted`
- `TreasuryMultisig.ConfirmationRevoked`
- `TreasuryMultisig.TransactionRejected`
- `TreasuryMultisig.RejectionRevoked`
- `TreasuryMultisig.TransactionCancelled`
- `TreasuryMultisig.BatchProposed`
- `TreasuryMultisig.BatchConfirmed`
- `TreasuryMultisig.BatchExecuted`
- `TreasuryMultisig.BatchConfirmationRevoked`
- `TreasuryMultisig.BatchRejected`
- `TreasuryMultisig.BatchRejectionRevoked`
- `TreasuryMultisig.BatchCancelled`
- `TreasuryMultisig.OwnerAdded`
- `TreasuryMultisig.OwnerRemoved`
- `TreasuryMultisig.OwnerSwapped`
- `TreasuryMultisig.ThresholdChanged`
- `TreasuryMultisig.TimingUpdated`
- `TreasuryMultisig.SensitiveSelectorUpdated`
- `TreasuryMultisig.NativeValueReceived`

## Missing Events Worth Adding Later

Do not add these unless they materially improve the final reporting demo:

- deterministic `PolicyDecisionPreviewed` is not appropriate onchain because previews are reads
- explicit blocked-action events would require catchable execution wrappers or offchain logging
- term-plan events should remain offchain/reporting in V1
- executable BTC sleeve events should wait until native BTC/ERC20 BTC handling and BTC receipt accounting are implemented

For V1, the reporting layer can combine onchain events with read-model snapshots from `services/spectrum-state`.
