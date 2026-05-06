import { Address, BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";

import {
  TreasuryAdminApprovalUpdated,
  TreasuryAccountDeployed,
} from "../generated/TreasuryAccountFactory/TreasuryAccountFactory";
import {
  AccountPolicyInitialized,
  AutomationCapabilitiesUpdated,
  AutomationEnabledUpdated,
  AutomationExecutorUpdated,
  AutomationLimitsUpdated,
  AutomationThresholdsUpdated,
  DestinationPolicyUpdated,
  PauseUpdated,
  TreasuryAdminUpdated,
} from "../generated/TreasuryPolicyEngine/TreasuryPolicyEngine";
import { HandlerRegistered, HandlerRemoved } from "../generated/AllocationRouter/AllocationRouter";
import {
  AutomationOperatorAuthorizationUpdated,
  BufferRestoreExecuted,
  DeRiskRepaymentExecuted,
} from "../generated/TreasuryAutomationExecutor/TreasuryAutomationExecutor";
import {
  AllocationRouterUpdated,
  AllocationExecuted,
  BorrowerOperationsUpdated,
  CollateralDeposited,
  CollateralWithdrawn,
  DebtDrawn,
  DebtRepaid,
  IdleMUSDFunded,
  LiquidityBufferRestored,
  PositionAdjusted,
  PositionClosed,
  PositionOpened,
  SleeveUnwoundAndDebtRepaid,
  TreasuryAdminSynced,
  TreasuryDisbursed,
  WithdrawalExecuted,
  WithdrawalSettledFromDestination,
  YieldClaimedFromDestination,
} from "../generated/templates/TreasuryAccount/TreasuryAccount";
import {
  BatchCancelled,
  BatchConfirmed,
  BatchConfirmationRevoked,
  BatchExecuted,
  BatchProposed,
  BatchRejected,
  BatchRejectionRevoked,
  ConfirmationRevoked,
  NativeValueReceived,
  OwnerAdded,
  OwnerRemoved,
  OwnerSwapped,
  RejectionRevoked,
  SensitiveSelectorUpdated,
  ThresholdChanged,
  TimingUpdated,
  TransactionConfirmed,
  TransactionCancelled,
  TransactionExecuted,
  TransactionProposed,
  TransactionRejected,
  TreasuryMultisigInitialized,
} from "../generated/templates/TreasuryMultisig/TreasuryMultisig";
import {
  SavingsDepositRouted,
  SavingsWithdrawalRouted,
  SavingsYieldClaimed,
} from "../generated/MUSDSavingsRateHandler/MUSDSavingsRateHandler";
import {
  StablePoolDepositRouted,
  StablePoolWithdrawalRouted,
} from "../generated/TigrisStablePoolHandler/TigrisStablePoolHandler";
import { TreasuryAccount as TreasuryAccountTemplate } from "../generated/templates";
import {
  AutomationAction,
  MultisigProposal,
  PolicyConfig,
  SleeveExposure,
  TreasuryAccount,
  TreasuryActivity,
} from "../generated/schema";

export function handleTreasuryAdminApprovalUpdated(event: TreasuryAdminApprovalUpdated): void {
  recordActivity(
    event,
    null,
    event.params.treasuryAdmin,
    null,
    "factory",
    event.params.approved ? "TreasuryAdminApproved" : "TreasuryAdminRevoked",
    null,
    null,
  );
}

export function handleTreasuryAccountDeployed(event: TreasuryAccountDeployed): void {
  TreasuryAccountTemplate.create(event.params.treasuryAccount);

  const account = new TreasuryAccount(event.params.treasuryAccount.toHexString());
  account.treasuryAdmin = event.params.treasuryAdmin;
  account.deployer = event.params.deployer;
  account.operator = event.params.operator;
  account.approver = event.params.approver;
  account.createdAt = event.block.timestamp;
  account.createdTx = event.transaction.hash;
  account.save();

  recordActivity(
    event,
    event.params.treasuryAccount,
    event.params.deployer,
    event.params.treasuryAccount,
    "account",
    "TreasuryAccountDeployed",
    null,
    null,
  );
}

export function handleAccountPolicyInitialized(event: AccountPolicyInitialized): void {
  const policy = loadPolicy(event.params.account);
  policy.treasuryAdmin = event.params.treasuryAdmin;
  policy.operator = event.params.operator;
  policy.approver = event.params.approver;
  policy.liquidityBuffer = event.params.liquidityBuffer;
  policy.approvalThreshold = event.params.approvalThreshold;
  policy.automationEnabled = event.params.automationEnabled;
  policy.paused = event.params.startPaused;
  policy.updatedAt = event.block.timestamp;
  policy.updatedTx = event.transaction.hash;
  policy.save();

  recordActivity(
    event,
    event.params.account,
    event.params.treasuryAdmin,
    null,
    "policy",
    "AccountPolicyInitialized",
    event.params.liquidityBuffer,
    event.params.approvalThreshold,
  );
}

export function handlePauseUpdated(event: PauseUpdated): void {
  const policy = loadPolicy(event.params.account);
  policy.paused = event.params.paused;
  policy.updatedAt = event.block.timestamp;
  policy.updatedTx = event.transaction.hash;
  policy.save();

  recordActivity(event, event.params.account, null, null, "policy", "PauseUpdated", null, null);
}

export function handleAutomationExecutorUpdated(event: AutomationExecutorUpdated): void {
  recordActivity(
    event,
    event.params.account,
    event.params.newExecutor,
    event.params.previousExecutor,
    "policy",
    "AutomationExecutorUpdated",
    null,
    null,
  );
}

export function handleAutomationThresholdsUpdated(event: AutomationThresholdsUpdated): void {
  recordActivity(
    event,
    event.params.account,
    null,
    null,
    "policy",
    "AutomationThresholdsUpdated",
    event.params.warningCollateralRatioBps,
    event.params.criticalCollateralRatioBps,
  );
}

export function handleAutomationLimitsUpdated(event: AutomationLimitsUpdated): void {
  recordActivity(
    event,
    event.params.account,
    null,
    null,
    "policy",
    "AutomationLimitsUpdated",
    event.params.maxAutoBufferRestore,
    event.params.maxAutoDebtRepay,
  );
}

export function handleAutomationCapabilitiesUpdated(event: AutomationCapabilitiesUpdated): void {
  recordActivity(
    event,
    event.params.account,
    null,
    null,
    "policy",
    "AutomationCapabilitiesUpdated",
    null,
    null,
  );
}

export function handleDestinationPolicyUpdated(event: DestinationPolicyUpdated): void {
  recordActivity(
    event,
    event.params.account,
    event.params.actor,
    event.params.destination,
    "policy",
    event.params.approved ? "DestinationApproved" : "DestinationRevoked",
    event.params.cap,
    null,
  );
}

export function handleAutomationEnabledUpdated(event: AutomationEnabledUpdated): void {
  const policy = loadPolicy(event.params.account);
  policy.automationEnabled = event.params.automationEnabled;
  policy.updatedAt = event.block.timestamp;
  policy.updatedTx = event.transaction.hash;
  policy.save();

  recordActivity(
    event,
    event.params.account,
    null,
    null,
    "policy",
    event.params.automationEnabled ? "AutomationEnabled" : "AutomationDisabled",
    null,
    null,
  );
}

export function handleTreasuryAdminUpdated(event: TreasuryAdminUpdated): void {
  const policy = loadPolicy(event.params.account);
  policy.treasuryAdmin = event.params.newTreasuryAdmin;
  policy.updatedAt = event.block.timestamp;
  policy.updatedTx = event.transaction.hash;
  policy.save();

  recordActivity(
    event,
    event.params.account,
    event.params.newTreasuryAdmin,
    event.params.previousTreasuryAdmin,
    "policy",
    "TreasuryAdminUpdated",
    null,
    null,
  );
}

export function handleBorrowerOperationsUpdated(event: BorrowerOperationsUpdated): void {
  recordActivity(
    event,
    event.address,
    null,
    event.params.borrowerOperations,
    "account",
    "BorrowerOperationsUpdated",
    null,
    null,
  );
}

export function handleAllocationRouterUpdated(event: AllocationRouterUpdated): void {
  recordActivity(
    event,
    event.address,
    null,
    event.params.allocationRouter,
    "account",
    "AllocationRouterUpdated",
    null,
    null,
  );
}

export function handleTreasuryAdminSynced(event: TreasuryAdminSynced): void {
  recordActivity(
    event,
    event.address,
    event.params.newTreasuryAdmin,
    event.params.previousTreasuryAdmin,
    "account",
    "TreasuryAdminSynced",
    null,
    null,
  );
}

export function handlePositionOpened(event: PositionOpened): void {
  recordActivity(
    event,
    event.address,
    event.address,
    null,
    "borrow",
    "PositionOpened",
    event.params.musdBorrowed,
    event.params.collateralDeposited,
  );
}

export function handleCollateralDeposited(event: CollateralDeposited): void {
  recordActivity(
    event,
    event.address,
    event.address,
    null,
    "borrow",
    "CollateralDeposited",
    event.params.amount,
    event.params.positionCollateralAfter,
  );
}

export function handleCollateralWithdrawn(event: CollateralWithdrawn): void {
  recordActivity(
    event,
    event.address,
    event.address,
    null,
    "borrow",
    "CollateralWithdrawn",
    event.params.amount,
    event.params.idleBTCAfter,
  );
}

export function handleDebtDrawn(event: DebtDrawn): void {
  recordActivity(
    event,
    event.address,
    event.address,
    null,
    "borrow",
    "DebtDrawn",
    event.params.amount,
    event.params.idleMUSDAfter,
  );
}

export function handleDebtRepaid(event: DebtRepaid): void {
  recordActivity(
    event,
    event.address,
    event.address,
    null,
    "borrow",
    "DebtRepaid",
    event.params.amount,
    event.params.positionDebtAfter,
  );
}

export function handlePositionAdjusted(event: PositionAdjusted): void {
  recordActivity(
    event,
    event.address,
    event.address,
    null,
    "borrow",
    event.params.debtIncreased ? "PositionAdjustedDebtIncreased" : "PositionAdjustedDebtReduced",
    event.params.debtChange,
    event.params.positionDebtAfter,
  );
}

export function handlePositionClosed(event: PositionClosed): void {
  recordActivity(
    event,
    event.address,
    event.address,
    null,
    "borrow",
    "PositionClosed",
    event.params.debtRepaidToClose,
    event.params.collateralReleased,
  );
}

export function handleTreasuryDisbursed(event: TreasuryDisbursed): void {
  recordActivity(
    event,
    event.address,
    event.params.actor,
    event.params.recipient,
    "disbursement",
    "TreasuryDisbursed",
    event.params.amount,
    event.params.idleBalanceAfter,
  );
}

export function handleAllocationExecuted(event: AllocationExecuted): void {
  updateSleeve(event.address, event.params.destination, event.params.allocationAfter, event);
  recordActivity(
    event,
    event.address,
    event.address,
    event.params.destination,
    "allocation",
    "AllocationExecuted",
    event.params.amount,
    event.params.allocationAfter,
  );
}

export function handleWithdrawalExecuted(event: WithdrawalExecuted): void {
  updateSleeve(event.address, event.params.destination, event.params.allocationAfter, event);
  recordActivity(
    event,
    event.address,
    event.address,
    event.params.destination,
    "allocation",
    "WithdrawalExecuted",
    event.params.amount,
    event.params.allocationAfter,
  );
}

export function handleYieldClaimedFromDestination(event: YieldClaimedFromDestination): void {
  recordActivity(
    event,
    event.address,
    event.address,
    event.params.destination,
    "yield",
    "YieldClaimedFromDestination",
    event.params.amount,
    event.params.idleBalanceAfter,
  );
}

export function handleIdleMUSDFunded(event: IdleMUSDFunded): void {
  recordActivity(
    event,
    event.address,
    event.params.funder,
    null,
    "funding",
    "IdleMUSDFunded",
    event.params.amount,
    event.params.idleBalanceAfter,
  );
}

export function handleWithdrawalSettledFromDestination(event: WithdrawalSettledFromDestination): void {
  updateSleeve(event.address, event.params.destination, event.params.allocationAfter, event);
  recordActivity(
    event,
    event.address,
    event.address,
    event.params.destination,
    "allocation",
    "WithdrawalSettledFromDestination",
    event.params.allocationAmount,
    event.params.idleMUSDIncrease,
  );
}

export function handleLiquidityBufferRestored(event: LiquidityBufferRestored): void {
  recordActivity(
    event,
    event.address,
    event.params.actor,
    event.params.destination,
    "automation",
    "LiquidityBufferRestored",
    event.params.restoredAmount,
    event.params.shortfall,
  );
}

export function handleSleeveUnwoundAndDebtRepaid(event: SleeveUnwoundAndDebtRepaid): void {
  recordActivity(
    event,
    event.address,
    event.params.actor,
    event.params.destination,
    "automation",
    "SleeveUnwoundAndDebtRepaid",
    event.params.actualRepaidAmount,
    event.params.actualWithdrawAmount,
  );
}

export function handleHandlerRegistered(event: HandlerRegistered): void {
  recordActivity(
    event,
    null,
    event.params.handler,
    event.params.destination,
    "router",
    "HandlerRegistered",
    null,
    null,
  );
}

export function handleHandlerRemoved(event: HandlerRemoved): void {
  recordActivity(
    event,
    null,
    event.params.handler,
    event.params.destination,
    "router",
    "HandlerRemoved",
    null,
    null,
  );
}

export function handleAutomationOperatorAuthorizationUpdated(event: AutomationOperatorAuthorizationUpdated): void {
  recordActivity(
    event,
    null,
    event.params.operator,
    null,
    "automation",
    event.params.authorized ? "AutomationOperatorAuthorized" : "AutomationOperatorRevoked",
    null,
    null,
  );
}

export function handleBufferRestoreExecuted(event: BufferRestoreExecuted): void {
  recordAutomation(
    event,
    event.params.treasuryAccount,
    event.params.operator,
    event.params.destination,
    "BufferRestoreExecuted",
    event.params.requestedMaxAmount,
    event.params.restoredAmount,
  );
}

export function handleDeRiskRepaymentExecuted(event: DeRiskRepaymentExecuted): void {
  recordAutomation(
    event,
    event.params.treasuryAccount,
    event.params.operator,
    event.params.destination,
    "DeRiskRepaymentExecuted",
    event.params.requestedWithdrawAmount,
    event.params.actualRepaidAmount,
  );
}

export function handleSavingsDepositRouted(event: SavingsDepositRouted): void {
  recordActivity(
    event,
    event.params.treasuryAccount,
    event.params.actor,
    event.address,
    "sleeve",
    "SavingsDepositRouted",
    event.params.amount,
    event.params.shares,
  );
}

export function handleSavingsWithdrawalRouted(event: SavingsWithdrawalRouted): void {
  recordActivity(
    event,
    event.params.treasuryAccount,
    event.params.actor,
    event.address,
    "sleeve",
    "SavingsWithdrawalRouted",
    event.params.amount,
    event.params.shares,
  );
}

export function handleSavingsYieldClaimed(event: SavingsYieldClaimed): void {
  recordActivity(
    event,
    event.params.treasuryAccount,
    event.params.actor,
    event.address,
    "yield",
    "SavingsYieldClaimed",
    event.params.amount,
    null,
  );
}

export function handleStablePoolDepositRouted(event: StablePoolDepositRouted): void {
  recordActivity(
    event,
    event.params.treasuryAccount,
    event.params.actor,
    event.params.destination,
    "sleeve",
    "StablePoolDepositRouted",
    event.params.musdIn,
    event.params.liquidityMinted,
  );
}

export function handleStablePoolWithdrawalRouted(event: StablePoolWithdrawalRouted): void {
  recordActivity(
    event,
    event.params.treasuryAccount,
    event.params.actor,
    event.params.destination,
    "sleeve",
    "StablePoolWithdrawalRouted",
    event.params.allocationReduced,
    event.params.musdReturned,
  );
}

export function handleTreasuryMultisigInitialized(event: TreasuryMultisigInitialized): void {
  recordActivity(
    event,
    null,
    event.address,
    null,
    "multisig",
    "TreasuryMultisigInitialized",
    event.params.threshold,
    event.params.maxPending,
  );
}

export function handleTransactionProposed(event: TransactionProposed): void {
  const proposal = new MultisigProposal(proposalId(event.address, "tx", event.params.txId));
  proposal.multisig = event.address;
  proposal.proposalType = "transaction";
  proposal.internalId = event.params.txId;
  proposal.proposer = event.params.proposer;
  proposal.target = event.params.target;
  proposal.selector = event.params.selector;
  proposal.txIdOffchain = event.params.txIdOffchain;
  proposal.confirmations = BigInt.fromI32(1);
  proposal.executed = false;
  proposal.proposedAt = event.params.proposedAt;
  proposal.executedAt = null;
  proposal.txHash = event.transaction.hash;
  proposal.save();

  recordMultisigActivity(event, event.params.proposer, event.params.target, "TransactionProposed", event.params.txId);
}

export function handleTransactionConfirmed(event: TransactionConfirmed): void {
  const proposal = MultisigProposal.load(proposalId(event.address, "tx", event.params.txId));
  if (proposal == null) return;
  proposal.confirmations = event.params.confirmationCount;
  proposal.save();

  recordMultisigActivity(event, event.params.signer, null, "TransactionConfirmed", event.params.txId);
}

export function handleTransactionExecuted(event: TransactionExecuted): void {
  const proposal = MultisigProposal.load(proposalId(event.address, "tx", event.params.txId));
  if (proposal == null) return;
  proposal.executed = true;
  proposal.executedAt = event.block.timestamp;
  proposal.txHash = event.transaction.hash;
  proposal.save();

  recordMultisigActivity(event, event.params.executor, event.params.target, "TransactionExecuted", event.params.txId);
}

export function handleConfirmationRevoked(event: ConfirmationRevoked): void {
  recordMultisigActivity(event, event.params.signer, null, "ConfirmationRevoked", event.params.txId);
}

export function handleTransactionRejected(event: TransactionRejected): void {
  recordMultisigActivity(event, event.params.signer, null, "TransactionRejected", event.params.txId);
}

export function handleRejectionRevoked(event: RejectionRevoked): void {
  recordMultisigActivity(event, event.params.signer, null, "RejectionRevoked", event.params.txId);
}

export function handleTransactionCancelled(event: TransactionCancelled): void {
  recordMultisigActivity(event, event.params.caller, null, "TransactionCancelled", event.params.txId);
}

export function handleBatchProposed(event: BatchProposed): void {
  const proposal = new MultisigProposal(proposalId(event.address, "batch", event.params.batchId));
  proposal.multisig = event.address;
  proposal.proposalType = "batch";
  proposal.internalId = event.params.batchId;
  proposal.proposer = event.params.proposer;
  proposal.target = null;
  proposal.selector = null;
  proposal.txIdOffchain = event.params.txIdOffchain;
  proposal.confirmations = BigInt.fromI32(1);
  proposal.executed = false;
  proposal.proposedAt = event.params.proposedAt;
  proposal.executedAt = null;
  proposal.txHash = event.transaction.hash;
  proposal.save();

  recordMultisigActivity(event, event.params.proposer, null, "BatchProposed", event.params.batchId);
}

export function handleBatchConfirmed(event: BatchConfirmed): void {
  const proposal = MultisigProposal.load(proposalId(event.address, "batch", event.params.batchId));
  if (proposal == null) return;
  proposal.confirmations = event.params.confirmationCount;
  proposal.save();

  recordMultisigActivity(event, event.params.signer, null, "BatchConfirmed", event.params.batchId);
}

export function handleBatchExecuted(event: BatchExecuted): void {
  const proposal = MultisigProposal.load(proposalId(event.address, "batch", event.params.batchId));
  if (proposal == null) return;
  proposal.executed = true;
  proposal.executedAt = event.block.timestamp;
  proposal.txHash = event.transaction.hash;
  proposal.save();

  recordMultisigActivity(event, event.params.executor, null, "BatchExecuted", event.params.batchId);
}

export function handleBatchConfirmationRevoked(event: BatchConfirmationRevoked): void {
  recordMultisigActivity(event, event.params.signer, null, "BatchConfirmationRevoked", event.params.batchId);
}

export function handleBatchRejected(event: BatchRejected): void {
  recordMultisigActivity(event, event.params.signer, null, "BatchRejected", event.params.batchId);
}

export function handleBatchRejectionRevoked(event: BatchRejectionRevoked): void {
  recordMultisigActivity(event, event.params.signer, null, "BatchRejectionRevoked", event.params.batchId);
}

export function handleBatchCancelled(event: BatchCancelled): void {
  recordMultisigActivity(event, event.params.caller, null, "BatchCancelled", event.params.batchId);
}

export function handleOwnerAdded(event: OwnerAdded): void {
  recordActivity(event, null, event.params.owner, event.address, "multisig", "OwnerAdded", null, null);
}

export function handleOwnerRemoved(event: OwnerRemoved): void {
  recordActivity(event, null, event.params.owner, event.address, "multisig", "OwnerRemoved", null, null);
}

export function handleOwnerSwapped(event: OwnerSwapped): void {
  recordActivity(event, null, event.params.oldOwner, event.params.newOwner, "multisig", "OwnerSwapped", null, null);
}

export function handleThresholdChanged(event: ThresholdChanged): void {
  recordActivity(event, null, event.address, null, "multisig", "ThresholdChanged", event.params.threshold, null);
}

export function handleTimingUpdated(event: TimingUpdated): void {
  recordActivity(event, null, event.address, null, "multisig", "TimingUpdated", event.params.sigDelay, event.params.maxPending);
}

export function handleSensitiveSelectorUpdated(event: SensitiveSelectorUpdated): void {
  recordActivity(
    event,
    null,
    event.address,
    event.params.target,
    "multisig",
    event.params.sensitive ? "SensitiveSelectorEnabled" : "SensitiveSelectorDisabled",
    null,
    null,
  );
}

export function handleNativeValueReceived(event: NativeValueReceived): void {
  recordActivity(
    event,
    null,
    event.params.sender,
    event.address,
    "multisig",
    "NativeValueReceived",
    event.params.value,
    null,
  );
}

function loadPolicy(account: Address): PolicyConfig {
  const id = account.toHexString();
  let policy = PolicyConfig.load(id);
  if (policy == null) {
    policy = new PolicyConfig(id);
    policy.account = account;
    policy.updatedAt = BigInt.zero();
    policy.updatedTx = Bytes.empty();
  }
  return policy;
}

function updateSleeve(account: Address, destination: Address, allocatedMUSD: BigInt, event: ethereum.Event): void {
  const id = account.toHexString() + "-" + destination.toHexString();
  let sleeve = SleeveExposure.load(id);
  if (sleeve == null) {
    sleeve = new SleeveExposure(id);
    sleeve.account = account;
    sleeve.destination = destination;
  }
  sleeve.allocatedMUSD = allocatedMUSD;
  sleeve.updatedAt = event.block.timestamp;
  sleeve.updatedTx = event.transaction.hash;
  sleeve.save();
}

function recordAutomation(
  event: ethereum.Event,
  account: Address,
  operator: Address,
  destination: Address,
  action: string,
  requestedAmount: BigInt,
  actualAmount: BigInt,
): void {
  const id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  const automation = new AutomationAction(id);
  automation.account = account;
  automation.operator = operator;
  automation.destination = destination;
  automation.action = action;
  automation.requestedAmount = requestedAmount;
  automation.actualAmount = actualAmount;
  automation.txHash = event.transaction.hash;
  automation.blockNumber = event.block.number;
  automation.timestamp = event.block.timestamp;
  automation.save();

  recordActivity(event, account, operator, destination, "automation", action, actualAmount, requestedAmount);
}

function recordMultisigActivity(
  event: ethereum.Event,
  actor: Address | null,
  destination: Address | null,
  action: string,
  internalId: BigInt,
): void {
  recordActivity(event, null, actor, destination, "multisig", action, internalId, null);
}

function recordActivity(
  event: ethereum.Event,
  account: Address | null,
  actor: Address | null,
  destination: Address | null,
  category: string,
  action: string,
  amount: BigInt | null,
  secondaryAmount: BigInt | null,
): void {
  const id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString() + "-" + action;
  const activity = new TreasuryActivity(id);
  activity.account = account;
  activity.actor = actor;
  activity.destination = destination;
  activity.category = category;
  activity.action = action;
  activity.amount = amount;
  activity.secondaryAmount = secondaryAmount;
  activity.txHash = event.transaction.hash;
  activity.logIndex = event.logIndex;
  activity.blockNumber = event.block.number;
  activity.timestamp = event.block.timestamp;
  activity.save();
}

function proposalId(multisig: Address, kind: string, id: BigInt): string {
  return multisig.toHexString() + "-" + kind + "-" + id.toString();
}
