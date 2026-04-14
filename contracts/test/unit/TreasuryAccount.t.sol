// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Test } from "forge-std/Test.sol";

import { TreasuryAccount } from "../../src/core/TreasuryAccount.sol";
import { TreasuryAccountFactory } from "../../src/core/TreasuryAccountFactory.sol";
import { TreasuryPolicyEngine } from "../../src/core/TreasuryPolicyEngine.sol";
import { ITreasuryPolicyEngine } from "../../src/interfaces/ITreasuryPolicyEngine.sol";
import { MockBorrowerOperations } from "../helpers/MockBorrowerOperations.sol";

contract TreasuryAccountTest is Test {
    address internal constant _TREASURY_ADMIN = address(0xA11CE);
    address internal constant _OPERATOR = address(0xB0B);
    address internal constant _APPROVER = address(0xCAFE);
    address internal constant _SAVINGS_VAULT = address(0xD00D);
    address internal constant _SECOND_DESTINATION = address(0xE11E);
    address internal constant _UPPER_HINT = address(0xAAA1);
    address internal constant _LOWER_HINT = address(0xAAA2);

    TreasuryPolicyEngine internal _policyEngine;
    TreasuryAccountFactory internal _factory;
    MockBorrowerOperations internal _borrowerOperations;

    function setUp() public {
        _policyEngine = new TreasuryPolicyEngine();
        _factory = new TreasuryAccountFactory(_policyEngine);
        _borrowerOperations = new MockBorrowerOperations();

        vm.deal(_TREASURY_ADMIN, 50 ether);
        vm.deal(_OPERATOR, 50 ether);
        vm.deal(_APPROVER, 50 ether);
    }

    function test_DeployTreasuryAccount_InitializesPolicyState() public {
        TreasuryAccount _account = _deployTreasuryAccount(_defaultConfig());

        (
            address _treasuryAdmin,
            address _operator,
            address _approver,
            uint256 _liquidityBuffer,
            uint256 _approvalThreshold,
            bool _automationEnabled,
            bool _paused,
            bool _initialized
        ) = _policyEngine.getAccountPolicy(address(_account));

        assertEq(_account.owner(), _TREASURY_ADMIN);
        assertEq(address(_account.policyEngine()), address(_policyEngine));
        assertEq(_treasuryAdmin, _TREASURY_ADMIN);
        assertEq(_operator, _OPERATOR);
        assertEq(_approver, _APPROVER);
        assertEq(_liquidityBuffer, 200 ether);
        assertEq(_approvalThreshold, 100 ether);
        assertTrue(_automationEnabled);
        assertFalse(_paused);
        assertTrue(_initialized);
        assertTrue(_policyEngine.isDestinationApproved(address(_account), _SAVINGS_VAULT));
        assertEq(_policyEngine.allocationCap(address(_account), _SAVINGS_VAULT), 500 ether);
    }

    function test_SetBorrowerOperations_TreasuryAdminCanSetBorrowerOperations() public {
        TreasuryAccount _account = _deployTreasuryAccount(_defaultConfig());

        vm.prank(_TREASURY_ADMIN);
        _account.setBorrowerOperations(address(_borrowerOperations));

        assertEq(address(_account.borrowerOperations()), address(_borrowerOperations));
    }

    function test_AcceptOwnership_PendingOwnerSyncsPolicyTreasuryAdmin() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();
        address _nextTreasuryAdmin = address(0xDD01);

        vm.prank(_TREASURY_ADMIN);
        _account.transferOwnership(_nextTreasuryAdmin);

        vm.prank(_nextTreasuryAdmin);
        _account.acceptOwnership();

        (address _treasuryAdmin,,,,,,,) = _policyEngine.getAccountPolicy(address(_account));

        assertEq(_account.owner(), _nextTreasuryAdmin);
        assertEq(_treasuryAdmin, _nextTreasuryAdmin);
    }

    function test_OpenTrove_OperatorCanOpenWithinApprovalThreshold() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_OPERATOR);
        _account.openTrove{ value: 2 ether }(80 ether, _UPPER_HINT, _LOWER_HINT);

        assertTrue(_account.positionActive());
        assertEq(_account.idleMUSD(), 80 ether);
        assertEq(_account.positionCollateral(), 2 ether);
        assertEq(_account.positionDebtPrincipal(), 80 ether);
        assertEq(_borrowerOperations.totalCollateral(), 2 ether);
        assertEq(_borrowerOperations.totalDebtPrincipal(), 80 ether);
    }

    function test_OpenTrove_OperatorCannotOpenAboveApprovalThreshold() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.ApprovalRequired.selector, _OPERATOR, 150 ether, 100 ether)
        );

        vm.prank(_OPERATOR);
        _account.openTrove{ value: 2 ether }(150 ether, _UPPER_HINT, _LOWER_HINT);
    }

    function test_WithdrawMUSD_ApproverCanIncreaseDebtAboveApprovalThreshold() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_APPROVER);
        _account.openTrove{ value: 2 ether }(150 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_APPROVER);
        _account.withdrawMUSD(120 ether, _UPPER_HINT, _LOWER_HINT);

        assertEq(_account.idleMUSD(), 270 ether);
        assertEq(_account.positionDebtPrincipal(), 270 ether);
    }

    function test_RepayMUSD_OperatorCanRepayWithinApprovalThreshold() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_APPROVER);
        _account.openTrove{ value: 3 ether }(150 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_OPERATOR);
        _account.repayMUSD(50 ether, _UPPER_HINT, _LOWER_HINT);

        assertEq(_account.idleMUSD(), 100 ether);
        assertEq(_account.positionDebtPrincipal(), 100 ether);
    }

    function test_AddCollateral_OperatorCanAddCollateralWhilePaused() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_OPERATOR);
        _account.openTrove{ value: 2 ether }(80 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_APPROVER);
        _account.setPause(true);

        vm.prank(_OPERATOR);
        _account.addCollateral{ value: 1 ether }(_UPPER_HINT, _LOWER_HINT);

        assertEq(_account.positionCollateral(), 3 ether);
    }

    function test_WithdrawCollateral_OperatorCannotWithdrawCollateral() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_OPERATOR);
        _account.openTrove{ value: 2 ether }(80 ether, _UPPER_HINT, _LOWER_HINT);

        vm.deal(address(_borrowerOperations), 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.UnauthorizedActor.selector, address(_account), _OPERATOR)
        );

        vm.prank(_OPERATOR);
        _account.withdrawCollateral(1 ether, _UPPER_HINT, _LOWER_HINT);
    }

    function test_AdjustTrove_ApproverCanAdjustCollateralAndDebt() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_APPROVER);
        _account.openTrove{ value: 3 ether }(150 ether, _UPPER_HINT, _LOWER_HINT);

        vm.deal(address(_borrowerOperations), 1 ether);

        vm.prank(_APPROVER);
        _account.adjustTrove{ value: 1 ether }(1 ether, 40 ether, false, _UPPER_HINT, _LOWER_HINT);

        assertEq(_account.idleMUSD(), 110 ether);
        assertEq(_account.idleBTC(), 1 ether);
        assertEq(_account.positionCollateral(), 3 ether);
        assertEq(_account.positionDebtPrincipal(), 110 ether);
    }

    function test_CloseTrove_ApproverCanCloseAndRestoreBTC() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_APPROVER);
        _account.openTrove{ value: 2 ether }(150 ether, _UPPER_HINT, _LOWER_HINT);

        vm.deal(address(_borrowerOperations), 2 ether);

        vm.prank(_APPROVER);
        _account.closeTrove();

        assertFalse(_account.positionActive());
        assertEq(_account.idleMUSD(), 0);
        assertEq(_account.idleBTC(), 2 ether);
        assertEq(_account.positionCollateral(), 0);
        assertEq(_account.positionDebtPrincipal(), 0);
    }

    function test_Allocate_OperatorCanAllocateWithinThresholdAndBuffer() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_APPROVER);
        _account.openTrove{ value: 6 ether }(600 ether, _UPPER_HINT, _LOWER_HINT);

        vm.expectEmit(true, false, false, true);
        emit TreasuryAccount.AllocationExecuted(_SAVINGS_VAULT, 100 ether, 500 ether, 100 ether);

        vm.prank(_OPERATOR);
        _account.allocate(_SAVINGS_VAULT, 100 ether);

        assertEq(_account.idleMUSD(), 500 ether);
        assertEq(_account.destinationAllocations(_SAVINGS_VAULT), 100 ether);
    }

    function test_Allocate_UnapprovedDestinationReverts() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_APPROVER);
        _account.openTrove{ value: 5 ether }(500 ether, _UPPER_HINT, _LOWER_HINT);

        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.NotApprovedDestination.selector, _SECOND_DESTINATION)
        );

        vm.prank(_OPERATOR);
        _account.allocate(_SECOND_DESTINATION, 50 ether);
    }

    function test_Allocate_LiquidityBufferBreachReverts() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_APPROVER);
        _account.openTrove{ value: 3 ether }(260 ether, _UPPER_HINT, _LOWER_HINT);

        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.LiquidityBufferBreached.selector, 160 ether, 200 ether)
        );

        vm.prank(_OPERATOR);
        _account.allocate(_SAVINGS_VAULT, 100 ether);
    }

    function test_SetPause_ApproverCanPauseAndBlockFurtherAllocation() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_APPROVER);
        _account.openTrove{ value: 4 ether }(400 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_APPROVER);
        _account.setPause(true);

        vm.expectRevert(abi.encodeWithSelector(TreasuryPolicyEngine.PolicyPaused.selector, address(_account)));

        vm.prank(_OPERATOR);
        _account.allocate(_SAVINGS_VAULT, 50 ether);
    }

    function test_SetBorrowerOperations_NonOwnerReverts() public {
        TreasuryAccount _account = _deployTreasuryAccount(_defaultConfig());

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _OPERATOR));

        vm.prank(_OPERATOR);
        _account.setBorrowerOperations(address(_borrowerOperations));
    }

    function test_WithdrawFromDestination_RestoresIdleBalance() public {
        TreasuryAccount _account = _deployConfiguredTreasuryAccount();

        vm.prank(_APPROVER);
        _account.openTrove{ value: 6 ether }(600 ether, _UPPER_HINT, _LOWER_HINT);

        vm.prank(_OPERATOR);
        _account.allocate(_SAVINGS_VAULT, 100 ether);

        vm.prank(_OPERATOR);
        _account.withdrawFromDestination(_SAVINGS_VAULT, 40 ether);

        assertEq(_account.idleMUSD(), 540 ether);
        assertEq(_account.destinationAllocations(_SAVINGS_VAULT), 60 ether);
    }

    function _deployConfiguredTreasuryAccount() internal returns (TreasuryAccount _account) {
        _account = _deployTreasuryAccount(_defaultConfig());

        vm.prank(_TREASURY_ADMIN);
        _account.setBorrowerOperations(address(_borrowerOperations));
    }

    function _deployTreasuryAccount(ITreasuryPolicyEngine.AccountPolicyConfig memory _config)
        internal
        returns (TreasuryAccount)
    {
        return TreasuryAccount(payable(_factory.deployTreasuryAccount(_TREASURY_ADMIN, _config)));
    }

    function _defaultConfig() internal pure returns (ITreasuryPolicyEngine.AccountPolicyConfig memory config) {
        address[] memory _destinations = new address[](1);
        _destinations[0] = _SAVINGS_VAULT;

        uint256[] memory _caps = new uint256[](1);
        _caps[0] = 500 ether;

        config = ITreasuryPolicyEngine.AccountPolicyConfig({
            operator: _OPERATOR,
            approver: _APPROVER,
            liquidityBuffer: 200 ether,
            approvalThreshold: 100 ether,
            automationEnabled: true,
            startPaused: false,
            approvedDestinations: _destinations,
            destinationCaps: _caps
        });
    }
}
