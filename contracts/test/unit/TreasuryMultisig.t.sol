// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";

import { AllocationRouter } from "../../src/adapters/AllocationRouter.sol";
import { MUSDSavingsRateHandler } from "../../src/adapters/MUSDSavingsRateHandler.sol";
import { TreasuryAccount } from "../../src/core/TreasuryAccount.sol";
import { TreasuryAccountFactory } from "../../src/core/TreasuryAccountFactory.sol";
import { TreasuryAutomationExecutor } from "../../src/core/TreasuryAutomationExecutor.sol";
import { TreasuryPolicyEngine } from "../../src/core/TreasuryPolicyEngine.sol";
import { ITreasuryPolicyEngine } from "../../src/interfaces/ITreasuryPolicyEngine.sol";
import { TreasuryMultisig } from "../../src/multisig/TreasuryMultisig.sol";
import { MockBorrowerOperations } from "../helpers/MockBorrowerOperations.sol";
import { MockMUSDSavingsRate } from "../helpers/MockMUSDSavingsRate.sol";

contract TreasuryMultisigTest is Test {
    address internal _ownerOne;
    address internal _ownerTwo;
    address internal _ownerThree;
    address internal _operator;
    address internal _approver;
    address internal _automationOperator;
    address internal _operatingRecipient;
    address internal _upperHint;
    address internal _lowerHint;

    TreasuryMultisig internal _multisig;
    TreasuryPolicyEngine internal _policyEngine;
    TreasuryAccountFactory internal _factory;
    TreasuryAutomationExecutor internal _automationExecutor;
    MockBorrowerOperations internal _borrowerOperations;
    MockMUSDSavingsRate internal _savingsVault;
    AllocationRouter internal _allocationRouter;
    MUSDSavingsRateHandler internal _savingsHandler;
    TreasuryAccount internal _treasuryAccount;
    MultisigCallTarget internal _callTarget;

    function setUp() public {
        _ownerOne = makeAddr("ownerOne");
        _ownerTwo = makeAddr("ownerTwo");
        _ownerThree = makeAddr("ownerThree");
        _operator = makeAddr("operator");
        _approver = makeAddr("approver");
        _automationOperator = makeAddr("automationOperator");
        _operatingRecipient = makeAddr("operatingRecipient");
        _upperHint = makeAddr("upperHint");
        _lowerHint = makeAddr("lowerHint");

        _multisig = new TreasuryMultisig(_defaultOwners(), 2, 0, 7 days);
        _policyEngine = new TreasuryPolicyEngine();
        _borrowerOperations = new MockBorrowerOperations();
        _factory = new TreasuryAccountFactory(
            IERC20(_borrowerOperations.musdToken()), _policyEngine, address(new TreasuryAccount())
        );
        _automationExecutor = new TreasuryAutomationExecutor(address(_multisig));
        _savingsVault = new MockMUSDSavingsRate(_borrowerOperations.musdTokenContract());
        _allocationRouter = new AllocationRouter(address(_multisig));
        _savingsHandler = new MUSDSavingsRateHandler(_savingsVault, address(_allocationRouter));
        _callTarget = new MultisigCallTarget();

        _factory.setTreasuryAdminApproval(address(_multisig), true);
        _treasuryAccount =
            TreasuryAccount(payable(_factory.deployTreasuryAccount(address(_multisig), _defaultConfig())));

        vm.deal(_ownerOne, 50 ether);
        vm.deal(_ownerTwo, 50 ether);
        vm.deal(_ownerThree, 50 ether);
        vm.deal(_operator, 50 ether);
        vm.deal(_approver, 50 ether);
        vm.deal(address(_multisig), 50 ether);
    }

    function test_ProposeTransaction_ExecutesOnlyAfterThreshold() public {
        uint256 _transferAmount = 1 ether;
        uint256 _txId = _proposeMultisigCall(_operatingRecipient, _transferAmount, "");

        assertEq(_operatingRecipient.balance, 0);
        assertEq(_multisig.getConfirmationCount(_txId), 1);

        vm.prank(_ownerTwo);
        _multisig.confirmTransaction(_txId);

        assertEq(_operatingRecipient.balance, _transferAmount);
    }

    function test_ProposeTransaction_CanAttachNativeValueForOneShotExecution() public {
        TreasuryMultisig _singleSignerMultisig = new TreasuryMultisig(_singleOwner(), 1, 0, 7 days);
        uint256 _transferAmount = 1 ether;

        vm.prank(_ownerOne);
        _singleSignerMultisig.proposeTransaction{ value: _transferAmount }(
            _operatingRecipient, _transferAmount, "", bytes32(0)
        );

        assertEq(_operatingRecipient.balance, _transferAmount);
        assertEq(address(_singleSignerMultisig).balance, 0);
    }

    function test_ProposeTransaction_AttachedNativeValueMustMatchProposalValue() public {
        TreasuryMultisig _singleSignerMultisig = new TreasuryMultisig(_singleOwner(), 1, 0, 7 days);

        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.NativeValueMismatch.selector, 1 ether, 2 ether));
        vm.prank(_ownerOne);
        _singleSignerMultisig.proposeTransaction{ value: 1 ether }(_operatingRecipient, 2 ether, "", bytes32(0));
    }

    function test_ProposeTransaction_CanTransferERC20Funds() public {
        IERC20 _musdToken = IERC20(_borrowerOperations.musdToken());
        uint256 _transferAmount = 100 ether;

        _borrowerOperations.musdTokenContract().mint(address(_multisig), _transferAmount);

        _executeMultisigCall(
            address(_musdToken), 0, abi.encodeCall(IERC20.transfer, (_operatingRecipient, _transferAmount))
        );

        assertEq(_musdToken.balanceOf(_operatingRecipient), _transferAmount);
        assertEq(_musdToken.balanceOf(address(_multisig)), 0);
    }

    function test_Constructor_InvalidOwnerConfigurationReverts() public {
        address[] memory _owners = new address[](0);

        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.InvalidThreshold.selector, 1, 0));
        new TreasuryMultisig(_owners, 1, 0, 0);

        _owners = _defaultOwners();

        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.InvalidThreshold.selector, 0, 3));
        new TreasuryMultisig(_owners, 0, 0, 0);

        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.InvalidThreshold.selector, 4, 3));
        new TreasuryMultisig(_owners, 4, 0, 0);

        _owners[2] = _owners[1];

        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.DuplicateOwner.selector, _ownerTwo));
        new TreasuryMultisig(_owners, 2, 0, 0);
    }

    function test_Constructor_InvalidTimingConfigurationReverts() public {
        vm.expectRevert(TreasuryMultisig.InvalidTimingParams.selector);
        new TreasuryMultisig(_defaultOwners(), 3, 1 days, 2 days);
    }

    function test_ProposeTransaction_InvalidCallerAndTargetRevert() public {
        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.NotOwner.selector, _operator));
        vm.prank(_operator);
        _multisig.proposeTransaction(_operatingRecipient, 0, "", bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.InvalidTarget.selector, address(0)));
        vm.prank(_ownerOne);
        _multisig.proposeTransaction(address(0), 0, "", bytes32(0));
    }

    function test_ExecuteTransaction_NotEnoughConfirmationsReverts() public {
        uint256 _txId = _proposeMultisigCall(_operatingRecipient, 1 ether, "");

        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.NotEnoughConfirmations.selector, 1, 2));
        vm.prank(_ownerOne);
        _multisig.executeTransaction(_txId);
    }

    function test_ConfirmTransaction_DuplicateAndConsecutiveConfirmationReverts() public {
        TreasuryMultisig _wideMultisig = new TreasuryMultisig(_defaultOwners(), 3, 0, 7 days);
        vm.deal(address(_wideMultisig), 10 ether);

        uint256 _txId = _proposeMultisigCall(_wideMultisig, _operatingRecipient, 1 ether, "");

        vm.expectRevert(TreasuryMultisig.AlreadyConfirmed.selector);
        vm.prank(_ownerOne);
        _wideMultisig.confirmTransaction(_txId);

        vm.prank(_ownerTwo);
        _wideMultisig.confirmTransaction(_txId);

        vm.prank(_ownerTwo);
        _wideMultisig.revokeConfirmation(_txId);

        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.ConsecutiveConfirmation.selector, _ownerTwo));
        vm.prank(_ownerTwo);
        _wideMultisig.confirmTransaction(_txId);
    }

    function test_CancelTransaction_ProposerCancelsAndBlocksExecution() public {
        uint256 _txId = _proposeMultisigCall(_operatingRecipient, 1 ether, "");

        vm.prank(_ownerOne);
        _multisig.cancelTransaction(_txId);

        (,,,, bool _executed, bool _cancelled,,,) = _multisig.getTransaction(_txId);

        assertFalse(_executed);
        assertTrue(_cancelled);

        vm.expectRevert(TreasuryMultisig.AlreadyCancelled.selector);
        vm.prank(_ownerTwo);
        _multisig.confirmTransaction(_txId);
    }

    function test_CancelTransaction_NonProposerReverts() public {
        uint256 _txId = _proposeMultisigCall(_operatingRecipient, 1 ether, "");

        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.NotOwner.selector, _ownerTwo));
        vm.prank(_ownerTwo);
        _multisig.cancelTransaction(_txId);
    }

    function test_RevokeConfirmation_RemovesValidConfirmation() public {
        uint256 _txId = _proposeMultisigCall(_operatingRecipient, 1 ether, "");

        assertTrue(_multisig.hasConfirmed(_txId, _ownerOne));

        vm.prank(_ownerOne);
        _multisig.revokeConfirmation(_txId);

        assertFalse(_multisig.hasConfirmed(_txId, _ownerOne));
        assertEq(_multisig.getConfirmationCount(_txId), 0);

        vm.expectRevert(TreasuryMultisig.NotConfirmed.selector);
        vm.prank(_ownerOne);
        _multisig.revokeConfirmation(_txId);
    }

    function test_RejectTransaction_RejectionLifecycleAndCancellation() public {
        uint256 _txId = _proposeMultisigCall(_operatingRecipient, 1 ether, "");

        vm.expectRevert(TreasuryMultisig.AlreadyConfirmed.selector);
        vm.prank(_ownerOne);
        _multisig.rejectTransaction(_txId);

        vm.prank(_ownerTwo);
        _multisig.rejectTransaction(_txId);

        vm.expectRevert(TreasuryMultisig.AlreadyRejected.selector);
        vm.prank(_ownerTwo);
        _multisig.confirmTransaction(_txId);

        vm.prank(_ownerTwo);
        _multisig.revokeRejection(_txId);

        vm.expectRevert(TreasuryMultisig.NotRejected.selector);
        vm.prank(_ownerTwo);
        _multisig.revokeRejection(_txId);

        vm.prank(_ownerTwo);
        _multisig.rejectTransaction(_txId);

        vm.prank(_ownerThree);
        _multisig.rejectTransaction(_txId);

        (,,,,, bool _cancelled,,,) = _multisig.getTransaction(_txId);
        assertTrue(_cancelled);
    }

    function test_ExpiredTransaction_BlocksConfirmationAndExecution() public {
        TreasuryMultisig _expiringMultisig = new TreasuryMultisig(_defaultOwners(), 2, 0, 1 days);
        vm.deal(address(_expiringMultisig), 10 ether);

        uint256 _txId = _proposeMultisigCall(_expiringMultisig, _operatingRecipient, 1 ether, "");

        vm.warp(block.timestamp + 1 days + 1);

        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.ProposalExpired.selector, block.timestamp - 1));
        vm.prank(_ownerTwo);
        _expiringMultisig.confirmTransaction(_txId);

        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.ProposalExpired.selector, block.timestamp - 1));
        vm.prank(_ownerOne);
        _expiringMultisig.executeTransaction(_txId);
    }

    function test_ExecuteTransaction_BubblesTargetRevertData() public {
        uint256 _txId =
            _proposeMultisigCall(address(_callTarget), 0, abi.encodeCall(MultisigCallTarget.revertWithData, ()));

        vm.expectRevert(MultisigCallTarget.TargetReverted.selector);
        vm.prank(_ownerTwo);
        _multisig.confirmTransaction(_txId);
    }

    function test_ExecuteTransaction_GenericFailureWithoutRevertData() public {
        uint256 _txId =
            _proposeMultisigCall(address(_callTarget), 0, abi.encodeCall(MultisigCallTarget.revertWithoutData, ()));

        vm.expectRevert(TreasuryMultisig.ExecutionFailed.selector);
        vm.prank(_ownerTwo);
        _multisig.confirmTransaction(_txId);
    }

    function test_SetSensitiveSelector_EnforcesConfirmationDelay() public {
        TreasuryMultisig _delayedMultisig = new TreasuryMultisig(_defaultOwners(), 2, 1 hours, 1 days);
        vm.deal(address(_delayedMultisig), 10 ether);

        uint256 _selectorTxId = _proposeMultisigCall(
            _delayedMultisig,
            address(_delayedMultisig),
            0,
            abi.encodeCall(TreasuryMultisig.setSensitiveSelector, (_operatingRecipient, bytes4(0), true))
        );

        vm.prank(_ownerTwo);
        _delayedMultisig.confirmTransaction(_selectorTxId);

        uint256 _cashTxId = _proposeMultisigCall(_delayedMultisig, _operatingRecipient, 1 ether, "");
        uint256 _earliestConfirmation = block.timestamp + 1 hours;

        vm.prank(_ownerTwo);
        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.ConfirmationTooSoon.selector, _earliestConfirmation));
        _delayedMultisig.confirmTransaction(_cashTxId);

        vm.warp(_earliestConfirmation);

        vm.prank(_ownerTwo);
        _delayedMultisig.confirmTransaction(_cashTxId);

        assertEq(_operatingRecipient.balance, 1 ether);
    }

    function test_UpdateTiming_SelfManagedTimingChangeAndInvalidDirectCall() public {
        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.NotSelf.selector, _ownerOne));
        vm.prank(_ownerOne);
        _multisig.updateTiming(1 hours, 1 days);

        _executeMultisigCall(address(_multisig), 0, abi.encodeCall(TreasuryMultisig.updateTiming, (1 hours, 3 days)));

        assertEq(_multisig.sigDelay(), 1 hours);
        assertEq(_multisig.maxPending(), 3 days);
    }

    function test_AddOwnerWithThreshold_SelfManagedOwnerChangeExecutesThroughMultisig() public {
        address _newOwner = makeAddr("newOwner");

        _executeMultisigCall(
            address(_multisig), 0, abi.encodeCall(TreasuryMultisig.addOwnerWithThreshold, (_newOwner, 3))
        );

        address[] memory _owners = _multisig.getOwners();

        assertEq(_multisig.threshold(), 3);
        assertTrue(_multisig.isOwner(_newOwner));
        assertEq(_owners.length, 4);
    }

    function test_RemoveOwnerAndSwapOwner_SelfManagedSignerChangesExecuteThroughMultisig() public {
        _executeMultisigCall(address(_multisig), 0, abi.encodeCall(TreasuryMultisig.removeOwner, (_ownerThree, 2)));

        address _newOwner = makeAddr("newOwner");

        _executeMultisigCall(address(_multisig), 0, abi.encodeCall(TreasuryMultisig.swapOwner, (_ownerTwo, _newOwner)));

        address[] memory _owners = _multisig.getOwners();

        assertFalse(_multisig.isOwner(_ownerTwo));
        assertFalse(_multisig.isOwner(_ownerThree));
        assertTrue(_multisig.isOwner(_newOwner));
        assertEq(_multisig.threshold(), 2);
        assertEq(_owners.length, 2);
    }

    function test_SelfManagedSignerChanges_InvalidInputsRevert() public {
        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.NotSelf.selector, _ownerOne));
        vm.prank(_ownerOne);
        _multisig.changeThreshold(1);

        uint256 _txId =
            _proposeMultisigCall(address(_multisig), 0, abi.encodeCall(TreasuryMultisig.removeOwner, (_operator, 2)));

        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.InvalidOwner.selector, _operator));
        vm.prank(_ownerTwo);
        _multisig.confirmTransaction(_txId);

        _txId = _proposeMultisigCall(
            address(_multisig), 0, abi.encodeCall(TreasuryMultisig.swapOwner, (_ownerTwo, address(0)))
        );

        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.InvalidOwner.selector, address(0)));
        vm.prank(_ownerTwo);
        _multisig.confirmTransaction(_txId);

        _txId = _proposeMultisigCall(
            address(_multisig), 0, abi.encodeCall(TreasuryMultisig.swapOwner, (_ownerTwo, _ownerOne))
        );

        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.DuplicateOwner.selector, _ownerOne));
        vm.prank(_ownerTwo);
        _multisig.confirmTransaction(_txId);
    }

    function test_BatchTransaction_InvalidInputsRevert() public {
        address[] memory _targets = new address[](1);
        uint256[] memory _values = new uint256[](2);
        bytes[] memory _payloads = new bytes[](1);

        vm.expectRevert(TreasuryMultisig.LengthMismatch.selector);
        vm.prank(_ownerOne);
        _multisig.proposeBatchTransaction(_targets, _values, _payloads, bytes32(0));

        _targets = new address[](0);
        _values = new uint256[](0);
        _payloads = new bytes[](0);

        vm.expectRevert(TreasuryMultisig.EmptyBatch.selector);
        vm.prank(_ownerOne);
        _multisig.proposeBatchTransaction(_targets, _values, _payloads, bytes32(0));

        _targets = new address[](1);
        _values = new uint256[](1);
        _payloads = new bytes[](1);

        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.InvalidTarget.selector, address(0)));
        vm.prank(_ownerOne);
        _multisig.proposeBatchTransaction(_targets, _values, _payloads, bytes32(0));
    }

    function test_BatchTransaction_RevokeRejectCancelAndInvalidStatePaths() public {
        address[] memory _targets = new address[](1);
        uint256[] memory _values = new uint256[](1);
        bytes[] memory _payloads = new bytes[](1);
        _targets[0] = address(_callTarget);
        _payloads[0] = abi.encodeCall(MultisigCallTarget.setValue, (11));

        uint256 _batchId = _proposeMultisigBatch(_targets, _values, _payloads);

        assertTrue(_multisig.hasConfirmedBatch(_batchId, _ownerOne));

        vm.prank(_ownerOne);
        _multisig.revokeBatchConfirmation(_batchId);

        assertFalse(_multisig.hasConfirmedBatch(_batchId, _ownerOne));
        assertEq(_multisig.getBatchConfirmationCount(_batchId), 0);

        vm.expectRevert(TreasuryMultisig.NotConfirmed.selector);
        vm.prank(_ownerOne);
        _multisig.revokeBatchConfirmation(_batchId);

        vm.prank(_ownerTwo);
        _multisig.rejectBatchTransaction(_batchId);

        vm.expectRevert(TreasuryMultisig.AlreadyRejected.selector);
        vm.prank(_ownerTwo);
        _multisig.confirmBatchTransaction(_batchId);

        vm.prank(_ownerTwo);
        _multisig.revokeBatchRejection(_batchId);

        vm.expectRevert(TreasuryMultisig.NotRejected.selector);
        vm.prank(_ownerTwo);
        _multisig.revokeBatchRejection(_batchId);

        vm.prank(_ownerOne);
        _multisig.cancelBatchTransaction(_batchId);

        vm.expectRevert(TreasuryMultisig.AlreadyCancelled.selector);
        vm.prank(_ownerThree);
        _multisig.confirmBatchTransaction(_batchId);
    }

    function test_BatchTransaction_CanAttachNativeValueForOneShotExecution() public {
        TreasuryMultisig _singleSignerMultisig = new TreasuryMultisig(_singleOwner(), 1, 0, 7 days);
        address _recipientTwo = makeAddr("recipientTwo");
        address[] memory _targets = new address[](2);
        uint256[] memory _values = new uint256[](2);
        bytes[] memory _payloads = new bytes[](2);
        _targets[0] = _operatingRecipient;
        _targets[1] = _recipientTwo;
        _values[0] = 1 ether;
        _values[1] = 2 ether;

        vm.prank(_ownerOne);
        _singleSignerMultisig.proposeBatchTransaction{ value: 3 ether }(_targets, _values, _payloads, bytes32(0));

        assertEq(_operatingRecipient.balance, 1 ether);
        assertEq(_recipientTwo.balance, 2 ether);
        assertEq(address(_singleSignerMultisig).balance, 0);
    }

    function test_BatchTransaction_AttachedNativeValueMustMatchBatchValues() public {
        TreasuryMultisig _singleSignerMultisig = new TreasuryMultisig(_singleOwner(), 1, 0, 7 days);
        address[] memory _targets = new address[](1);
        uint256[] memory _values = new uint256[](1);
        bytes[] memory _payloads = new bytes[](1);
        _targets[0] = _operatingRecipient;
        _values[0] = 2 ether;

        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.NativeValueMismatch.selector, 1 ether, 2 ether));
        vm.prank(_ownerOne);
        _singleSignerMultisig.proposeBatchTransaction{ value: 1 ether }(_targets, _values, _payloads, bytes32(0));
    }

    function test_BatchTransaction_RejectionsCancelWhenThresholdImpossible() public {
        address[] memory _targets = new address[](1);
        uint256[] memory _values = new uint256[](1);
        bytes[] memory _payloads = new bytes[](1);
        _targets[0] = address(_callTarget);
        _payloads[0] = abi.encodeCall(MultisigCallTarget.setValue, (11));

        uint256 _batchId = _proposeMultisigBatch(_targets, _values, _payloads);

        vm.expectRevert(TreasuryMultisig.AlreadyConfirmed.selector);
        vm.prank(_ownerOne);
        _multisig.rejectBatchTransaction(_batchId);

        vm.prank(_ownerTwo);
        _multisig.rejectBatchTransaction(_batchId);

        vm.prank(_ownerThree);
        _multisig.rejectBatchTransaction(_batchId);

        vm.expectRevert(TreasuryMultisig.AlreadyCancelled.selector);
        vm.prank(_ownerTwo);
        _multisig.revokeBatchRejection(_batchId);
    }

    function test_BatchTransaction_SensitiveSelectorDelayApplies() public {
        TreasuryMultisig _delayedMultisig = new TreasuryMultisig(_defaultOwners(), 2, 1 hours, 1 days);

        uint256 _selectorTxId = _proposeMultisigCall(
            _delayedMultisig,
            address(_delayedMultisig),
            0,
            abi.encodeCall(
                TreasuryMultisig.setSensitiveSelector,
                (address(_callTarget), MultisigCallTarget.setValue.selector, true)
            )
        );

        vm.prank(_ownerTwo);
        _delayedMultisig.confirmTransaction(_selectorTxId);

        address[] memory _targets = new address[](1);
        uint256[] memory _values = new uint256[](1);
        bytes[] memory _payloads = new bytes[](1);
        _targets[0] = address(_callTarget);
        _payloads[0] = abi.encodeCall(MultisigCallTarget.setValue, (22));

        vm.prank(_ownerOne);
        uint256 _batchId = _delayedMultisig.proposeBatchTransaction(_targets, _values, _payloads, bytes32(0));

        uint256 _earliestConfirmation = block.timestamp + 1 hours;

        vm.prank(_ownerTwo);
        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.ConfirmationTooSoon.selector, _earliestConfirmation));
        _delayedMultisig.confirmBatchTransaction(_batchId);

        vm.warp(_earliestConfirmation);

        vm.prank(_ownerTwo);
        _delayedMultisig.confirmBatchTransaction(_batchId);

        assertEq(_callTarget.value(), 22);
    }

    function test_InvalidViewIdsRevert() public {
        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.InvalidTransaction.selector, 999));
        _multisig.getTransaction(999);

        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.InvalidTransaction.selector, 999));
        _multisig.hasConfirmed(999, _ownerOne);

        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.InvalidTransaction.selector, 999));
        _multisig.getConfirmationCount(999);

        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.InvalidBatch.selector, 999));
        _multisig.hasConfirmedBatch(999, _ownerOne);

        vm.expectRevert(abi.encodeWithSelector(TreasuryMultisig.InvalidBatch.selector, 999));
        _multisig.getBatchConfirmationCount(999);
    }

    function test_DisburseMUSD_MultisigControlsCriticalOperatingWithdrawal() public {
        _executeMultisigCall(
            address(_treasuryAccount),
            0,
            abi.encodeCall(TreasuryAccount.setBorrowerOperations, (address(_borrowerOperations)))
        );

        vm.prank(_approver);
        _treasuryAccount.openTrove{ value: 4 ether }(400 ether, _upperHint, _lowerHint);

        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.ApprovalRequired.selector, _operator, 150 ether, 100 ether)
        );
        vm.prank(_operator);
        _treasuryAccount.disburseMUSD(_operatingRecipient, 150 ether);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _ownerOne));
        vm.prank(_ownerOne);
        _treasuryAccount.setBorrowerOperations(address(_borrowerOperations));

        _executeMultisigCall(
            address(_treasuryAccount), 0, abi.encodeCall(TreasuryAccount.disburseMUSD, (_operatingRecipient, 150 ether))
        );

        assertEq(_treasuryAccount.idleMUSD(), 250 ether);
        assertEq(_borrowerOperations.musdTokenContract().balanceOf(_operatingRecipient), 150 ether);
    }

    function test_BatchTransaction_ConfiguresTreasuryStackAndAutomationPath() public {
        _executeTreasurySetupBatch();

        (address _automationPolicyExecutor, uint256 _maxBufferRestore, uint256 _maxDebtRepay, bool _allowSavings,) =
            _policyEngine.getAccountAutomationPolicy(address(_treasuryAccount));

        assertEq(address(_treasuryAccount.borrowerOperations()), address(_borrowerOperations));
        assertEq(address(_treasuryAccount.allocationRouter()), address(_allocationRouter));
        assertEq(_allocationRouter.handlers(address(_savingsVault)), address(_savingsHandler));
        assertEq(_automationPolicyExecutor, address(_automationExecutor));
        assertEq(_maxBufferRestore, 100 ether);
        assertEq(_maxDebtRepay, 80 ether);
        assertTrue(_allowSavings);
        assertTrue(_automationExecutor.automationOperators(_automationOperator));

        vm.prank(_approver);
        _treasuryAccount.openTrove{ value: 6 ether }(600 ether, _upperHint, _lowerHint);

        vm.prank(_approver);
        _allocationRouter.deposit(address(_treasuryAccount), address(_savingsVault), 300 ether);

        _executeMultisigCall(
            address(_treasuryAccount), 0, abi.encodeCall(TreasuryAccount.disburseMUSD, (_operatingRecipient, 150 ether))
        );

        vm.prank(_automationOperator);
        uint256 _restoredAmount =
            _automationExecutor.restoreBufferFromSavings(_treasuryAccount, address(_savingsVault), 60 ether);

        assertEq(_restoredAmount, 50 ether);
        assertEq(_treasuryAccount.idleMUSD(), 200 ether);
        assertEq(_treasuryAccount.destinationAllocations(address(_savingsVault)), 250 ether);
    }

    function _executeTreasurySetupBatch() internal {
        address[] memory _targets = new address[](7);
        uint256[] memory _values = new uint256[](7);
        bytes[] memory _payloads = new bytes[](7);

        _targets[0] = address(_treasuryAccount);
        _payloads[0] = abi.encodeCall(TreasuryAccount.setBorrowerOperations, (address(_borrowerOperations)));

        _targets[1] = address(_treasuryAccount);
        _payloads[1] = abi.encodeCall(TreasuryAccount.setAllocationRouter, (address(_allocationRouter)));

        _targets[2] = address(_allocationRouter);
        _payloads[2] = abi.encodeCall(AllocationRouter.setHandler, (address(_savingsVault), _savingsHandler));

        _targets[3] = address(_policyEngine);
        _payloads[3] = abi.encodeCall(
            TreasuryPolicyEngine.updateAutomationExecutor, (address(_treasuryAccount), address(_automationExecutor))
        );

        _targets[4] = address(_policyEngine);
        _payloads[4] = abi.encodeCall(
            TreasuryPolicyEngine.updateAutomationLimits, (address(_treasuryAccount), 100 ether, 80 ether)
        );

        _targets[5] = address(_policyEngine);
        _payloads[5] =
            abi.encodeCall(TreasuryPolicyEngine.updateAutomationCapabilities, (address(_treasuryAccount), true, true));

        _targets[6] = address(_automationExecutor);
        _payloads[6] = abi.encodeCall(TreasuryAutomationExecutor.setAutomationOperator, (_automationOperator, true));

        uint256 _batchId = _proposeMultisigBatch(_targets, _values, _payloads);

        vm.prank(_ownerTwo);
        _multisig.confirmBatchTransaction(_batchId);
    }

    function _executeMultisigCall(address _target, uint256 _value, bytes memory _data)
        internal
        returns (uint256 _txId)
    {
        _txId = _proposeMultisigCall(_target, _value, _data);

        vm.prank(_ownerTwo);
        _multisig.confirmTransaction(_txId);
    }

    function _proposeMultisigCall(address _target, uint256 _value, bytes memory _data)
        internal
        returns (uint256 _txId)
    {
        return _proposeMultisigCall(_multisig, _target, _value, _data);
    }

    function _proposeMultisigCall(TreasuryMultisig _targetMultisig, address _target, uint256 _value, bytes memory _data)
        internal
        returns (uint256 _txId)
    {
        vm.prank(_ownerOne);
        _txId = _targetMultisig.proposeTransaction(_target, _value, _data, bytes32(0));
    }

    function _proposeMultisigBatch(address[] memory _targets, uint256[] memory _values, bytes[] memory _payloads)
        internal
        returns (uint256 _batchId)
    {
        vm.prank(_ownerOne);
        _batchId = _multisig.proposeBatchTransaction(_targets, _values, _payloads, keccak256("setup"));
    }

    function _defaultOwners() internal view returns (address[] memory _owners) {
        _owners = new address[](3);
        _owners[0] = _ownerOne;
        _owners[1] = _ownerTwo;
        _owners[2] = _ownerThree;
    }

    function _singleOwner() internal view returns (address[] memory _owners) {
        _owners = new address[](1);
        _owners[0] = _ownerOne;
    }

    function _defaultConfig() internal view returns (ITreasuryPolicyEngine.AccountPolicyConfig memory config) {
        address[] memory _destinations = new address[](1);
        _destinations[0] = address(_savingsVault);

        uint256[] memory _caps = new uint256[](1);
        _caps[0] = 500 ether;

        config = ITreasuryPolicyEngine.AccountPolicyConfig({
            operator: _operator,
            approver: _approver,
            liquidityBuffer: 200 ether,
            approvalThreshold: 100 ether,
            warningCollateralRatioBps: 18_000,
            criticalCollateralRatioBps: 15_000,
            automationEnabled: true,
            startPaused: false,
            approvedDestinations: _destinations,
            destinationCaps: _caps
        });
    }
}

contract MultisigCallTarget {
    error TargetReverted();

    uint256 public value;

    receive() external payable { }

    function setValue(uint256 _value) external payable returns (uint256) {
        value = _value;
        return _value;
    }

    function revertWithData() external pure {
        revert TargetReverted();
    }

    function revertWithoutData() external pure {
        assembly {
            revert(0, 0)
        }
    }
}
