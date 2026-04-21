// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title TreasuryMultisig
/// @notice Optional TreasuryOS client-control multisig for critical treasury administration.
/// @dev This contract controls execution approvals only. It intentionally does not encode treasury policy,
/// liquidity buffers, allocation caps, or automation thresholds; those remain in TreasuryPolicyEngine.
contract TreasuryMultisig {
    /// @notice Emitted when the multisig is initialized.
    /// @param owners Initial signer set.
    /// @param threshold Required confirmation threshold.
    /// @param sigDelay Minimum spacing between confirmations for sensitive calls.
    /// @param maxPending Maximum proposal lifetime. Zero disables expiry.
    event TreasuryMultisigInitialized(address[] owners, uint256 threshold, uint64 sigDelay, uint64 maxPending);
    /// @notice Emitted when a single transaction is proposed.
    /// @param txId Internal transaction id.
    /// @param proposer Signer that proposed the transaction.
    /// @param target Target contract called by the multisig.
    /// @param value Native value sent with the call.
    /// @param selector Function selector extracted from calldata.
    /// @param txIdOffchain Optional offchain tracking id.
    /// @param proposedAt Proposal creation timestamp.
    /// @param expiresAt Proposal expiry timestamp.
    event TransactionProposed(
        uint256 indexed txId,
        address indexed proposer,
        address indexed target,
        uint256 value,
        bytes4 selector,
        bytes32 txIdOffchain,
        uint64 proposedAt,
        uint64 expiresAt
    );
    /// @notice Emitted when a signer confirms a single transaction.
    /// @param txId Internal transaction id.
    /// @param signer Signer that confirmed the transaction.
    /// @param confirmationCount Current valid confirmation count.
    event TransactionConfirmed(uint256 indexed txId, address indexed signer, uint256 confirmationCount);
    /// @notice Emitted when a single transaction executes.
    /// @param txId Internal transaction id.
    /// @param executor Signer that triggered execution.
    /// @param target Target contract called by the multisig.
    /// @param txIdOffchain Optional offchain tracking id.
    event TransactionExecuted(
        uint256 indexed txId, address indexed executor, address indexed target, bytes32 txIdOffchain
    );
    /// @notice Emitted when a signer revokes a confirmation.
    /// @param txId Internal transaction id.
    /// @param signer Signer revoking confirmation.
    event ConfirmationRevoked(uint256 indexed txId, address indexed signer);
    /// @notice Emitted when a signer rejects a transaction.
    /// @param txId Internal transaction id.
    /// @param signer Signer rejecting the transaction.
    /// @param rejectionCount Current valid rejection count.
    event TransactionRejected(uint256 indexed txId, address indexed signer, uint256 rejectionCount);
    /// @notice Emitted when a signer revokes a rejection.
    /// @param txId Internal transaction id.
    /// @param signer Signer revoking rejection.
    event RejectionRevoked(uint256 indexed txId, address indexed signer);
    /// @notice Emitted when a transaction is cancelled.
    /// @param txId Internal transaction id.
    /// @param caller Caller that caused cancellation.
    event TransactionCancelled(uint256 indexed txId, address indexed caller);
    /// @notice Emitted when a batch transaction is proposed.
    /// @param batchId Internal batch id.
    /// @param proposer Signer that proposed the batch.
    /// @param txIdOffchain Optional offchain tracking id.
    /// @param proposedAt Proposal creation timestamp.
    /// @param expiresAt Proposal expiry timestamp.
    event BatchProposed(
        uint256 indexed batchId, address indexed proposer, bytes32 txIdOffchain, uint64 proposedAt, uint64 expiresAt
    );
    /// @notice Emitted when a signer confirms a batch transaction.
    /// @param batchId Internal batch id.
    /// @param signer Signer that confirmed the batch.
    /// @param confirmationCount Current valid confirmation count.
    event BatchConfirmed(uint256 indexed batchId, address indexed signer, uint256 confirmationCount);
    /// @notice Emitted when a signer revokes a batch confirmation.
    /// @param batchId Internal batch id.
    /// @param signer Signer revoking confirmation.
    event BatchConfirmationRevoked(uint256 indexed batchId, address indexed signer);
    /// @notice Emitted when a signer rejects a batch transaction.
    /// @param batchId Internal batch id.
    /// @param signer Signer rejecting the batch.
    /// @param rejectionCount Current valid rejection count.
    event BatchRejected(uint256 indexed batchId, address indexed signer, uint256 rejectionCount);
    /// @notice Emitted when a signer revokes a batch rejection.
    /// @param batchId Internal batch id.
    /// @param signer Signer revoking rejection.
    event BatchRejectionRevoked(uint256 indexed batchId, address indexed signer);
    /// @notice Emitted when a batch transaction executes.
    /// @param batchId Internal batch id.
    /// @param executor Signer that triggered execution.
    /// @param txIdOffchain Optional offchain tracking id.
    event BatchExecuted(uint256 indexed batchId, address indexed executor, bytes32 txIdOffchain);
    /// @notice Emitted when a batch transaction is cancelled.
    /// @param batchId Internal batch id.
    /// @param caller Caller that caused cancellation.
    event BatchCancelled(uint256 indexed batchId, address indexed caller);
    /// @notice Emitted when a signer is added.
    /// @param owner New signer.
    event OwnerAdded(address indexed owner);
    /// @notice Emitted when a signer is removed.
    /// @param owner Removed signer.
    event OwnerRemoved(address indexed owner);
    /// @notice Emitted when a signer is replaced.
    /// @param oldOwner Removed signer.
    /// @param newOwner Added signer.
    event OwnerSwapped(address indexed oldOwner, address indexed newOwner);
    /// @notice Emitted when the confirmation threshold changes.
    /// @param threshold New threshold.
    event ThresholdChanged(uint256 threshold);
    /// @notice Emitted when proposal timing parameters change.
    /// @param sigDelay Minimum confirmation spacing for sensitive calls.
    /// @param maxPending Maximum proposal lifetime.
    event TimingUpdated(uint64 sigDelay, uint64 maxPending);
    /// @notice Emitted when a sensitive selector flag changes.
    /// @param target Target contract whose selector flag changed.
    /// @param selector Function selector being configured.
    /// @param sensitive Whether confirmation spacing is enforced.
    event SensitiveSelectorUpdated(address indexed target, bytes4 indexed selector, bool sensitive);
    /// @notice Emitted when native value is received by the multisig.
    /// @param sender Sender of the native value.
    /// @param value Amount received.
    event NativeValueReceived(address indexed sender, uint256 value);

    /// @notice Raised when a caller is not a current signer.
    /// @param caller Unauthorized caller.
    error NotOwner(address caller);
    /// @notice Raised when a function must be called by the multisig itself.
    /// @param caller Unauthorized caller.
    error NotSelf(address caller);
    /// @notice Raised when a signer list or signer value is invalid.
    /// @param owner Invalid signer.
    error InvalidOwner(address owner);
    /// @notice Raised when an execution target is zero.
    /// @param target Invalid target.
    error InvalidTarget(address target);
    /// @notice Raised when the threshold is zero or exceeds owner count.
    /// @param threshold Invalid threshold.
    /// @param ownerCount Current owner count.
    error InvalidThreshold(uint256 threshold, uint256 ownerCount);
    /// @notice Raised when an owner appears more than once.
    /// @param owner Duplicate signer.
    error DuplicateOwner(address owner);
    /// @notice Raised when a transaction id does not exist.
    /// @param txId Missing transaction id.
    error InvalidTransaction(uint256 txId);
    /// @notice Raised when a batch id does not exist.
    /// @param batchId Missing batch id.
    error InvalidBatch(uint256 batchId);
    /// @notice Raised when a proposal has already executed.
    error AlreadyExecuted();
    /// @notice Raised when a proposal has already been cancelled.
    error AlreadyCancelled();
    /// @notice Raised when a signer already confirmed the current owner generation.
    error AlreadyConfirmed();
    /// @notice Raised when a signer has not confirmed a proposal.
    error NotConfirmed();
    /// @notice Raised when a signer already rejected the current owner generation.
    error AlreadyRejected();
    /// @notice Raised when a signer has not rejected a proposal.
    error NotRejected();
    /// @notice Raised when a proposal does not have enough confirmations.
    /// @param confirmations Current confirmation count.
    /// @param threshold Required threshold.
    error NotEnoughConfirmations(uint256 confirmations, uint256 threshold);
    /// @notice Raised when the external call has no revert data and fails.
    error ExecutionFailed();
    /// @notice Raised when confirmation happens before the sensitive selector delay has elapsed.
    /// @param earliestConfirmation Earliest allowed confirmation timestamp.
    error ConfirmationTooSoon(uint256 earliestConfirmation);
    /// @notice Raised when a proposal has expired.
    /// @param expiresAt Expiry timestamp.
    error ProposalExpired(uint256 expiresAt);
    /// @notice Raised when array lengths do not match.
    error LengthMismatch();
    /// @notice Raised when a batch proposal has no calls.
    error EmptyBatch();
    /// @notice Raised when a signer submits consecutive confirmations on the same proposal.
    /// @param signer Consecutive signer.
    error ConsecutiveConfirmation(address signer);
    /// @notice Raised when timing parameters would make threshold confirmations impractical.
    error InvalidTimingParams();

    /// @notice Single transaction proposal.
    struct Transaction {
        address proposer;
        address target;
        uint256 value;
        bytes data;
        bool executed;
        bool cancelled;
        bytes32 txIdOffchain;
        uint64 proposedAt;
        uint64 expiresAt;
        uint64 lastConfirmationAt;
        address lastConfirmer;
        uint64 lastConfirmerGeneration;
        mapping(address owner => uint64 generation) confirmedAtGeneration;
        mapping(address owner => uint64 generation) rejectedAtGeneration;
    }

    /// @notice Batch transaction proposal.
    struct BatchTransaction {
        address proposer;
        address[] targets;
        uint256[] values;
        bytes[] payloads;
        bool executed;
        bool cancelled;
        bytes32 txIdOffchain;
        uint64 proposedAt;
        uint64 expiresAt;
        uint64 lastConfirmationAt;
        address lastConfirmer;
        uint64 lastConfirmerGeneration;
        mapping(address owner => uint64 generation) confirmedAtGeneration;
        mapping(address owner => uint64 generation) rejectedAtGeneration;
    }

    /// @notice Current signer set.
    address[] private owners;
    /// @notice Current signer status.
    mapping(address owner => bool active) public isOwner;
    /// @notice Signer generation used to invalidate stale confirmations across remove/re-add cycles.
    mapping(address owner => uint64 generation) public ownerGeneration;
    /// @notice Selectors requiring confirmation spacing.
    mapping(address target => mapping(bytes4 selector => bool sensitive)) public sensitiveSelectors;
    /// @notice Confirmation threshold.
    uint256 public threshold;
    /// @notice Minimum delay between confirmations for sensitive calls.
    uint64 public sigDelay;
    /// @notice Maximum proposal lifetime. Zero disables expiry.
    uint64 public maxPending;

    Transaction[] private transactions;
    BatchTransaction[] private batchTransactions;

    /// @notice Restricts execution to current signers.
    modifier onlyOwner() {
        _requireOwner(msg.sender);
        _;
    }

    /// @notice Restricts execution to self-calls approved by the multisig threshold.
    modifier onlySelf() {
        _requireSelf();
        _;
    }

    /// @param _owners Initial signer set.
    /// @param _threshold Required confirmation threshold.
    /// @param _sigDelay Minimum spacing between confirmations for sensitive calls.
    /// @param _maxPending Maximum proposal lifetime. Zero disables expiry.
    constructor(address[] memory _owners, uint256 _threshold, uint64 _sigDelay, uint64 _maxPending) {
        _setInitialOwners(_owners, _threshold);
        _validateTiming(_threshold, _sigDelay, _maxPending);
        sigDelay = _sigDelay;
        maxPending = _maxPending;

        emit TreasuryMultisigInitialized(_owners, _threshold, _sigDelay, _maxPending);
    }

    /// @notice Accepts native value accidentally or intentionally sent to the multisig.
    receive() external payable {
        emit NativeValueReceived(msg.sender, msg.value);
    }

    /// @notice Proposes a single transaction and auto-confirms it by the proposer.
    /// @param _target Target contract to call.
    /// @param _value Native value forwarded with the call.
    /// @param _data Calldata executed on the target.
    /// @param _txIdOffchain Optional offchain id for reporting and accounting systems.
    /// @return txId Internal transaction id.
    function proposeTransaction(address _target, uint256 _value, bytes calldata _data, bytes32 _txIdOffchain)
        external
        onlyOwner
        returns (uint256 txId)
    {
        require(_target != address(0), InvalidTarget(_target));

        txId = transactions.length;
        Transaction storage txn = transactions.push();
        txn.proposer = msg.sender;
        txn.target = _target;
        txn.value = _value;
        txn.data = _data;
        txn.txIdOffchain = _txIdOffchain;
        txn.proposedAt = uint64(block.timestamp);
        txn.expiresAt = _computeExpiry(txn.proposedAt);

        emit TransactionProposed(
            txId, msg.sender, _target, _value, _selector(_data), _txIdOffchain, txn.proposedAt, txn.expiresAt
        );

        confirmTransaction(txId);
    }

    /// @notice Confirms a single transaction and executes it once threshold is reached.
    /// @param _txId Internal transaction id.
    function confirmTransaction(uint256 _txId) public onlyOwner {
        Transaction storage txn = _requirePendingTransaction(_txId);
        _requireNotExpired(txn.expiresAt);
        _requireFreshConfirmation(txn.confirmedAtGeneration[msg.sender]);
        require(txn.rejectedAtGeneration[msg.sender] != ownerGeneration[msg.sender], AlreadyRejected());
        _requireNonConsecutiveConfirmation(txn.lastConfirmer, txn.lastConfirmerGeneration, msg.sender);
        _requireConfirmationDelay(txn.target, _selector(txn.data), txn.lastConfirmationAt, msg.sender == txn.proposer);

        txn.confirmedAtGeneration[msg.sender] = ownerGeneration[msg.sender];
        txn.lastConfirmationAt = uint64(block.timestamp);
        txn.lastConfirmer = msg.sender;
        txn.lastConfirmerGeneration = ownerGeneration[msg.sender];

        uint256 confirmationCount = _countConfirmations(txn);
        emit TransactionConfirmed(_txId, msg.sender, confirmationCount);

        if (confirmationCount >= threshold) {
            executeTransaction(_txId);
        }
    }

    /// @notice Executes a confirmed single transaction.
    /// @param _txId Internal transaction id.
    /// @return result Raw return data from the target call.
    function executeTransaction(uint256 _txId) public onlyOwner returns (bytes memory result) {
        Transaction storage txn = _requirePendingTransaction(_txId);
        _requireNotExpired(txn.expiresAt);

        uint256 confirmationCount = _countConfirmations(txn);
        require(confirmationCount >= threshold, NotEnoughConfirmations(confirmationCount, threshold));

        txn.executed = true;
        (bool success, bytes memory returndata) = txn.target.call{ value: txn.value }(txn.data);
        _revertIfCallFailed(success, returndata);

        emit TransactionExecuted(_txId, msg.sender, txn.target, txn.txIdOffchain);
        return returndata;
    }

    /// @notice Cancels a pending transaction proposed by the caller.
    /// @param _txId Internal transaction id.
    function cancelTransaction(uint256 _txId) external onlyOwner {
        Transaction storage txn = _requirePendingTransaction(_txId);
        require(txn.proposer == msg.sender, NotOwner(msg.sender));

        txn.cancelled = true;
        emit TransactionCancelled(_txId, msg.sender);
    }

    /// @notice Revokes the caller's confirmation for a pending transaction.
    /// @param _txId Internal transaction id.
    function revokeConfirmation(uint256 _txId) external onlyOwner {
        Transaction storage txn = _requirePendingTransaction(_txId);
        require(txn.confirmedAtGeneration[msg.sender] == ownerGeneration[msg.sender], NotConfirmed());

        txn.confirmedAtGeneration[msg.sender] = 0;
        emit ConfirmationRevoked(_txId, msg.sender);
    }

    /// @notice Rejects a pending transaction and cancels it if threshold can no longer be reached.
    /// @param _txId Internal transaction id.
    function rejectTransaction(uint256 _txId) external onlyOwner {
        Transaction storage txn = _requirePendingTransaction(_txId);
        _requireFreshRejection(txn.rejectedAtGeneration[msg.sender]);
        require(txn.confirmedAtGeneration[msg.sender] != ownerGeneration[msg.sender], AlreadyConfirmed());

        txn.rejectedAtGeneration[msg.sender] = ownerGeneration[msg.sender];
        uint256 rejectionCount = _countRejections(txn);

        emit TransactionRejected(_txId, msg.sender, rejectionCount);

        if (rejectionCount >= owners.length - threshold + 1) {
            txn.cancelled = true;
            emit TransactionCancelled(_txId, msg.sender);
        }
    }

    /// @notice Revokes the caller's rejection for a pending transaction.
    /// @param _txId Internal transaction id.
    function revokeRejection(uint256 _txId) external onlyOwner {
        Transaction storage txn = _requirePendingTransaction(_txId);
        require(txn.rejectedAtGeneration[msg.sender] == ownerGeneration[msg.sender], NotRejected());

        txn.rejectedAtGeneration[msg.sender] = 0;
        emit RejectionRevoked(_txId, msg.sender);
    }

    /// @notice Proposes a batch transaction and auto-confirms it by the proposer.
    /// @param _targets Target contracts called by the multisig.
    /// @param _values Native values forwarded to each target.
    /// @param _payloads Calldata payloads executed on each target.
    /// @param _txIdOffchain Optional offchain id for reporting and accounting systems.
    /// @return batchId Internal batch id.
    function proposeBatchTransaction(
        address[] calldata _targets,
        uint256[] calldata _values,
        bytes[] calldata _payloads,
        bytes32 _txIdOffchain
    ) external onlyOwner returns (uint256 batchId) {
        require(_targets.length == _values.length && _values.length == _payloads.length, LengthMismatch());
        require(_targets.length > 0, EmptyBatch());

        batchId = batchTransactions.length;
        BatchTransaction storage batch = batchTransactions.push();
        batch.proposer = msg.sender;
        batch.txIdOffchain = _txIdOffchain;
        batch.proposedAt = uint64(block.timestamp);
        batch.expiresAt = _computeExpiry(batch.proposedAt);

        for (uint256 i = 0; i < _targets.length; i++) {
            require(_targets[i] != address(0), InvalidTarget(_targets[i]));
            batch.targets.push(_targets[i]);
            batch.values.push(_values[i]);
            batch.payloads.push(_payloads[i]);
        }

        emit BatchProposed(batchId, msg.sender, _txIdOffchain, batch.proposedAt, batch.expiresAt);

        confirmBatchTransaction(batchId);
    }

    /// @notice Confirms a batch transaction and executes it once threshold is reached.
    /// @param _batchId Internal batch id.
    function confirmBatchTransaction(uint256 _batchId) public onlyOwner {
        BatchTransaction storage batch = _requirePendingBatch(_batchId);
        _requireNotExpired(batch.expiresAt);
        _requireFreshConfirmation(batch.confirmedAtGeneration[msg.sender]);
        require(batch.rejectedAtGeneration[msg.sender] != ownerGeneration[msg.sender], AlreadyRejected());
        _requireNonConsecutiveConfirmation(batch.lastConfirmer, batch.lastConfirmerGeneration, msg.sender);
        _requireBatchConfirmationDelay(batch, msg.sender == batch.proposer);

        batch.confirmedAtGeneration[msg.sender] = ownerGeneration[msg.sender];
        batch.lastConfirmationAt = uint64(block.timestamp);
        batch.lastConfirmer = msg.sender;
        batch.lastConfirmerGeneration = ownerGeneration[msg.sender];

        uint256 confirmationCount = _countBatchConfirmations(batch);
        emit BatchConfirmed(_batchId, msg.sender, confirmationCount);

        if (confirmationCount >= threshold) {
            executeBatchTransaction(_batchId);
        }
    }

    /// @notice Executes a confirmed batch transaction.
    /// @param _batchId Internal batch id.
    function executeBatchTransaction(uint256 _batchId) public onlyOwner {
        BatchTransaction storage batch = _requirePendingBatch(_batchId);
        _requireNotExpired(batch.expiresAt);

        uint256 confirmationCount = _countBatchConfirmations(batch);
        require(confirmationCount >= threshold, NotEnoughConfirmations(confirmationCount, threshold));

        batch.executed = true;
        for (uint256 i = 0; i < batch.targets.length; i++) {
            (bool success, bytes memory returndata) = batch.targets[i].call{ value: batch.values[i] }(batch.payloads[i]);
            _revertIfCallFailed(success, returndata);
        }

        emit BatchExecuted(_batchId, msg.sender, batch.txIdOffchain);
    }

    /// @notice Cancels a pending batch proposed by the caller.
    /// @param _batchId Internal batch id.
    function cancelBatchTransaction(uint256 _batchId) external onlyOwner {
        BatchTransaction storage batch = _requirePendingBatch(_batchId);
        require(batch.proposer == msg.sender, NotOwner(msg.sender));

        batch.cancelled = true;
        emit BatchCancelled(_batchId, msg.sender);
    }

    /// @notice Revokes the caller's confirmation for a pending batch transaction.
    /// @param _batchId Internal batch id.
    function revokeBatchConfirmation(uint256 _batchId) external onlyOwner {
        BatchTransaction storage batch = _requirePendingBatch(_batchId);
        require(batch.confirmedAtGeneration[msg.sender] == ownerGeneration[msg.sender], NotConfirmed());

        batch.confirmedAtGeneration[msg.sender] = 0;
        emit BatchConfirmationRevoked(_batchId, msg.sender);
    }

    /// @notice Rejects a pending batch and cancels it if threshold can no longer be reached.
    /// @param _batchId Internal batch id.
    function rejectBatchTransaction(uint256 _batchId) external onlyOwner {
        BatchTransaction storage batch = _requirePendingBatch(_batchId);
        _requireFreshRejection(batch.rejectedAtGeneration[msg.sender]);
        require(batch.confirmedAtGeneration[msg.sender] != ownerGeneration[msg.sender], AlreadyConfirmed());

        batch.rejectedAtGeneration[msg.sender] = ownerGeneration[msg.sender];
        uint256 rejectionCount = _countBatchRejections(batch);

        emit BatchRejected(_batchId, msg.sender, rejectionCount);

        if (rejectionCount >= owners.length - threshold + 1) {
            batch.cancelled = true;
            emit BatchCancelled(_batchId, msg.sender);
        }
    }

    /// @notice Revokes the caller's rejection for a pending batch transaction.
    /// @param _batchId Internal batch id.
    function revokeBatchRejection(uint256 _batchId) external onlyOwner {
        BatchTransaction storage batch = _requirePendingBatch(_batchId);
        require(batch.rejectedAtGeneration[msg.sender] == ownerGeneration[msg.sender], NotRejected());

        batch.rejectedAtGeneration[msg.sender] = 0;
        emit BatchRejectionRevoked(_batchId, msg.sender);
    }

    /// @notice Adds a new signer. Must be executed by the multisig itself.
    /// @param _owner Signer to add.
    /// @param _threshold New threshold after the signer is added.
    function addOwnerWithThreshold(address _owner, uint256 _threshold) external onlySelf {
        _addOwner(_owner);
        _changeThreshold(_threshold);
    }

    /// @notice Removes an existing signer. Must be executed by the multisig itself.
    /// @param _owner Signer to remove.
    /// @param _threshold New threshold after the signer is removed.
    function removeOwner(address _owner, uint256 _threshold) external onlySelf {
        require(isOwner[_owner], InvalidOwner(_owner));
        isOwner[_owner] = false;

        uint256 ownerCount = owners.length;
        for (uint256 i = 0; i < ownerCount; i++) {
            if (owners[i] == _owner) {
                owners[i] = owners[ownerCount - 1];
                owners.pop();
                break;
            }
        }

        emit OwnerRemoved(_owner);
        _changeThreshold(_threshold);
    }

    /// @notice Replaces an existing signer with a new signer. Must be executed by the multisig itself.
    /// @param _oldOwner Signer to remove.
    /// @param _newOwner Signer to add.
    function swapOwner(address _oldOwner, address _newOwner) external onlySelf {
        require(isOwner[_oldOwner], InvalidOwner(_oldOwner));
        require(_newOwner != address(0) && _newOwner != address(this), InvalidOwner(_newOwner));
        require(!isOwner[_newOwner], DuplicateOwner(_newOwner));

        isOwner[_oldOwner] = false;
        isOwner[_newOwner] = true;
        ownerGeneration[_newOwner] += 1;

        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == _oldOwner) {
                owners[i] = _newOwner;
                break;
            }
        }

        emit OwnerSwapped(_oldOwner, _newOwner);
    }

    /// @notice Changes the signer confirmation threshold. Must be executed by the multisig itself.
    /// @param _threshold New threshold.
    function changeThreshold(uint256 _threshold) external onlySelf {
        _changeThreshold(_threshold);
    }

    /// @notice Updates proposal timing controls. Must be executed by the multisig itself.
    /// @param _sigDelay Minimum confirmation spacing for sensitive calls.
    /// @param _maxPending Maximum proposal lifetime. Zero disables expiry.
    function updateTiming(uint64 _sigDelay, uint64 _maxPending) external onlySelf {
        _validateTiming(threshold, _sigDelay, _maxPending);
        sigDelay = _sigDelay;
        maxPending = _maxPending;
        emit TimingUpdated(_sigDelay, _maxPending);
    }

    /// @notice Marks or unmarks a selector as sensitive for confirmation-delay enforcement.
    /// @param _target Target contract being configured.
    /// @param _functionSelector Function selector being configured.
    /// @param _sensitive Whether confirmation spacing is enforced for the selector.
    function setSensitiveSelector(address _target, bytes4 _functionSelector, bool _sensitive) external onlySelf {
        sensitiveSelectors[_target][_functionSelector] = _sensitive;
        emit SensitiveSelectorUpdated(_target, _functionSelector, _sensitive);
    }

    /// @notice Returns current signer addresses.
    /// @return Current signer set.
    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    /// @notice Returns the number of single transaction proposals.
    /// @return Number of transaction proposals.
    function getTransactionCount() external view returns (uint256) {
        return transactions.length;
    }

    /// @notice Returns the number of batch transaction proposals.
    /// @return Number of batch proposals.
    function getBatchTransactionCount() external view returns (uint256) {
        return batchTransactions.length;
    }

    /// @notice Returns single transaction metadata.
    /// @param _txId Internal transaction id.
    /// @return proposer Signer that proposed the transaction.
    /// @return target Target contract called by the transaction.
    /// @return value Native value sent with the transaction.
    /// @return data Calldata executed by the transaction.
    /// @return executed Whether the transaction has executed.
    /// @return cancelled Whether the transaction has been cancelled.
    /// @return txIdOffchain Optional offchain tracking id.
    /// @return proposedAt Proposal creation timestamp.
    /// @return expiresAt Proposal expiry timestamp.
    function getTransaction(uint256 _txId)
        external
        view
        returns (
            address proposer,
            address target,
            uint256 value,
            bytes memory data,
            bool executed,
            bool cancelled,
            bytes32 txIdOffchain,
            uint64 proposedAt,
            uint64 expiresAt
        )
    {
        require(_txId < transactions.length, InvalidTransaction(_txId));
        Transaction storage txn = transactions[_txId];
        return (
            txn.proposer,
            txn.target,
            txn.value,
            txn.data,
            txn.executed,
            txn.cancelled,
            txn.txIdOffchain,
            txn.proposedAt,
            txn.expiresAt
        );
    }

    /// @notice Returns whether a signer confirmed a single transaction.
    /// @param _txId Internal transaction id.
    /// @param _owner Signer being checked.
    /// @return Whether the signer has a current-generation confirmation.
    function hasConfirmed(uint256 _txId, address _owner) external view returns (bool) {
        require(_txId < transactions.length, InvalidTransaction(_txId));
        return transactions[_txId].confirmedAtGeneration[_owner] == ownerGeneration[_owner];
    }

    /// @notice Returns the valid confirmation count for a single transaction.
    /// @param _txId Internal transaction id.
    /// @return Valid confirmation count.
    function getConfirmationCount(uint256 _txId) external view returns (uint256) {
        require(_txId < transactions.length, InvalidTransaction(_txId));
        return _countConfirmations(transactions[_txId]);
    }

    /// @notice Returns whether a signer confirmed a batch transaction.
    /// @param _batchId Internal batch id.
    /// @param _owner Signer being checked.
    /// @return Whether the signer has a current-generation confirmation.
    function hasConfirmedBatch(uint256 _batchId, address _owner) external view returns (bool) {
        require(_batchId < batchTransactions.length, InvalidBatch(_batchId));
        return batchTransactions[_batchId].confirmedAtGeneration[_owner] == ownerGeneration[_owner];
    }

    /// @notice Returns the valid confirmation count for a batch transaction.
    /// @param _batchId Internal batch id.
    /// @return Valid confirmation count.
    function getBatchConfirmationCount(uint256 _batchId) external view returns (uint256) {
        require(_batchId < batchTransactions.length, InvalidBatch(_batchId));
        return _countBatchConfirmations(batchTransactions[_batchId]);
    }

    /// @notice Initializes signer storage.
    /// @param _owners Initial signer set.
    /// @param _threshold Initial threshold.
    function _setInitialOwners(address[] memory _owners, uint256 _threshold) internal {
        require(_owners.length > 0, InvalidThreshold(_threshold, 0));
        require(_threshold > 0 && _threshold <= _owners.length, InvalidThreshold(_threshold, _owners.length));

        for (uint256 i = 0; i < _owners.length; i++) {
            _addOwner(_owners[i]);
        }

        threshold = _threshold;
    }

    /// @notice Adds a signer without changing threshold.
    /// @param _owner Signer to add.
    function _addOwner(address _owner) internal {
        require(_owner != address(0) && _owner != address(this), InvalidOwner(_owner));
        require(!isOwner[_owner], DuplicateOwner(_owner));

        isOwner[_owner] = true;
        owners.push(_owner);
        ownerGeneration[_owner] += 1;

        emit OwnerAdded(_owner);
    }

    /// @notice Changes the threshold after validating against current owner count.
    /// @param _threshold New threshold.
    function _changeThreshold(uint256 _threshold) internal {
        require(_threshold > 0 && _threshold <= owners.length, InvalidThreshold(_threshold, owners.length));
        _validateTiming(_threshold, sigDelay, maxPending);
        threshold = _threshold;
        emit ThresholdChanged(_threshold);
    }

    /// @notice Reverts unless `_owner` is a current signer.
    /// @param _owner Address being checked.
    function _requireOwner(address _owner) internal view {
        require(isOwner[_owner], NotOwner(_owner));
    }

    /// @notice Reverts unless the caller is the multisig itself.
    function _requireSelf() internal view {
        require(msg.sender == address(this), NotSelf(msg.sender));
    }

    /// @notice Returns a pending single transaction or reverts.
    /// @param _txId Internal transaction id.
    /// @return txn Pending transaction storage pointer.
    function _requirePendingTransaction(uint256 _txId) internal view returns (Transaction storage txn) {
        require(_txId < transactions.length, InvalidTransaction(_txId));
        txn = transactions[_txId];
        require(!txn.executed, AlreadyExecuted());
        require(!txn.cancelled, AlreadyCancelled());
    }

    /// @notice Returns a pending batch transaction or reverts.
    /// @param _batchId Internal batch id.
    /// @return batch Pending batch storage pointer.
    function _requirePendingBatch(uint256 _batchId) internal view returns (BatchTransaction storage batch) {
        require(_batchId < batchTransactions.length, InvalidBatch(_batchId));
        batch = batchTransactions[_batchId];
        require(!batch.executed, AlreadyExecuted());
        require(!batch.cancelled, AlreadyCancelled());
    }

    /// @notice Reverts if a proposal has expired.
    /// @param _expiresAt Proposal expiry timestamp.
    function _requireNotExpired(uint64 _expiresAt) internal view {
        require(block.timestamp <= _expiresAt, ProposalExpired(_expiresAt));
    }

    /// @notice Reverts if the caller already confirmed with the current signer generation.
    /// @param _confirmedAtGeneration Stored confirmation generation.
    function _requireFreshConfirmation(uint64 _confirmedAtGeneration) internal view {
        require(_confirmedAtGeneration != ownerGeneration[msg.sender], AlreadyConfirmed());
    }

    /// @notice Reverts if the caller already rejected with the current signer generation.
    /// @param _rejectedAtGeneration Stored rejection generation.
    function _requireFreshRejection(uint64 _rejectedAtGeneration) internal view {
        require(_rejectedAtGeneration != ownerGeneration[msg.sender], AlreadyRejected());
    }

    /// @notice Reverts when the same current-generation signer submits consecutive confirmations.
    /// @param _lastConfirmer Last signer that confirmed.
    /// @param _lastConfirmerGeneration Generation of the last confirmer when they confirmed.
    /// @param _currentConfirmer Current signer attempting to confirm.
    function _requireNonConsecutiveConfirmation(
        address _lastConfirmer,
        uint64 _lastConfirmerGeneration,
        address _currentConfirmer
    ) internal view {
        require(
            _lastConfirmer != _currentConfirmer || _lastConfirmerGeneration != ownerGeneration[_currentConfirmer],
            ConsecutiveConfirmation(_currentConfirmer)
        );
    }

    /// @notice Reverts if a sensitive single transaction confirmation is too early.
    /// @param _target Target contract.
    /// @param _functionSelector Function selector.
    /// @param _lastConfirmationAt Last confirmation timestamp.
    /// @param _isProposer Whether the current confirmer proposed the transaction.
    function _requireConfirmationDelay(
        address _target,
        bytes4 _functionSelector,
        uint64 _lastConfirmationAt,
        bool _isProposer
    ) internal view {
        if (_isProposer || _lastConfirmationAt == 0 || !sensitiveSelectors[_target][_functionSelector]) {
            return;
        }

        uint256 earliestConfirmation = uint256(_lastConfirmationAt) + uint256(sigDelay);
        require(block.timestamp >= earliestConfirmation, ConfirmationTooSoon(earliestConfirmation));
    }

    /// @notice Reverts if a sensitive batch transaction confirmation is too early.
    /// @param _batch Batch transaction being confirmed.
    /// @param _isProposer Whether the current confirmer proposed the batch.
    function _requireBatchConfirmationDelay(BatchTransaction storage _batch, bool _isProposer) internal view {
        if (_isProposer || _batch.lastConfirmationAt == 0 || !_batchHasSensitiveSelector(_batch)) {
            return;
        }

        uint256 earliestConfirmation = uint256(_batch.lastConfirmationAt) + uint256(sigDelay);
        require(block.timestamp >= earliestConfirmation, ConfirmationTooSoon(earliestConfirmation));
    }

    /// @notice Returns whether any call in a batch is marked sensitive.
    /// @param _batch Batch transaction being checked.
    /// @return Whether any batch call is sensitive.
    function _batchHasSensitiveSelector(BatchTransaction storage _batch) internal view returns (bool) {
        for (uint256 i = 0; i < _batch.targets.length; i++) {
            if (sensitiveSelectors[_batch.targets[i]][_selector(_batch.payloads[i])]) {
                return true;
            }
        }

        return false;
    }

    /// @notice Counts valid confirmations for a single transaction.
    /// @param _txn Transaction being checked.
    /// @return count Valid confirmation count.
    function _countConfirmations(Transaction storage _txn) internal view returns (uint256 count) {
        for (uint256 i = 0; i < owners.length; i++) {
            address owner = owners[i];
            if (_txn.confirmedAtGeneration[owner] == ownerGeneration[owner]) {
                count++;
            }
        }
    }

    /// @notice Counts valid rejections for a single transaction.
    /// @param _txn Transaction being checked.
    /// @return count Valid rejection count.
    function _countRejections(Transaction storage _txn) internal view returns (uint256 count) {
        for (uint256 i = 0; i < owners.length; i++) {
            address owner = owners[i];
            if (_txn.rejectedAtGeneration[owner] == ownerGeneration[owner]) {
                count++;
            }
        }
    }

    /// @notice Counts valid confirmations for a batch transaction.
    /// @param _batch Batch transaction being checked.
    /// @return count Valid confirmation count.
    function _countBatchConfirmations(BatchTransaction storage _batch) internal view returns (uint256 count) {
        for (uint256 i = 0; i < owners.length; i++) {
            address owner = owners[i];
            if (_batch.confirmedAtGeneration[owner] == ownerGeneration[owner]) {
                count++;
            }
        }
    }

    /// @notice Counts valid rejections for a batch transaction.
    /// @param _batch Batch transaction being checked.
    /// @return count Valid rejection count.
    function _countBatchRejections(BatchTransaction storage _batch) internal view returns (uint256 count) {
        for (uint256 i = 0; i < owners.length; i++) {
            address owner = owners[i];
            if (_batch.rejectedAtGeneration[owner] == ownerGeneration[owner]) {
                count++;
            }
        }
    }

    /// @notice Computes proposal expiry from creation time and configured lifetime.
    /// @param _proposedAt Proposal creation timestamp.
    /// @return Expiry timestamp.
    function _computeExpiry(uint64 _proposedAt) internal view returns (uint64) {
        if (maxPending == 0) {
            return type(uint64).max;
        }

        return _proposedAt + maxPending;
    }

    /// @notice Validates timing controls against a proposed threshold.
    /// @param _threshold Threshold being checked.
    /// @param _sigDelay Minimum sensitive confirmation spacing.
    /// @param _maxPending Maximum proposal lifetime.
    function _validateTiming(uint256 _threshold, uint64 _sigDelay, uint64 _maxPending) internal pure {
        if (_sigDelay == 0 || _maxPending == 0 || _threshold <= 1) {
            return;
        }

        require(uint256(_maxPending) > (uint256(_threshold) - 1) * uint256(_sigDelay), InvalidTimingParams());
    }

    /// @notice Extracts a function selector from calldata-like bytes.
    /// @param _data Calldata payload.
    /// @return selector Extracted selector, or zero when payload is shorter than four bytes.
    function _selector(bytes memory _data) internal pure returns (bytes4 selector) {
        if (_data.length < 4) {
            return bytes4(0);
        }

        assembly {
            selector := mload(add(_data, 32))
        }
    }

    /// @notice Reverts with target revert data or generic execution failure.
    /// @param _success Whether the call succeeded.
    /// @param _returndata Raw return or revert data.
    function _revertIfCallFailed(bool _success, bytes memory _returndata) internal pure {
        if (_success) {
            return;
        }

        if (_returndata.length == 0) {
            revert ExecutionFailed();
        }

        assembly {
            revert(add(_returndata, 32), mload(_returndata))
        }
    }
}
