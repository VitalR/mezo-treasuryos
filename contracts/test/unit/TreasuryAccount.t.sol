// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Test } from "forge-std/Test.sol";

import { TreasuryAccount } from "../../src/core/TreasuryAccount.sol";
import { TreasuryAccountFactory } from "../../src/core/TreasuryAccountFactory.sol";
import { TreasuryPolicyEngine } from "../../src/core/TreasuryPolicyEngine.sol";
import { ITreasuryPolicyEngine } from "../../src/interfaces/ITreasuryPolicyEngine.sol";

contract TreasuryAccountTest is Test {
    address internal constant _TREASURY_ADMIN = address(0xA11CE);
    address internal constant _OPERATOR = address(0xB0B);
    address internal constant _APPROVER = address(0xCAFE);
    address internal constant _SAVINGS_VAULT = address(0xD00D);
    address internal constant _SECOND_DESTINATION = address(0xE11E);

    TreasuryPolicyEngine internal _policyEngine;
    TreasuryAccountFactory internal _factory;

    function setUp() public {
        _policyEngine = new TreasuryPolicyEngine();
        _factory = new TreasuryAccountFactory(_policyEngine);
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

        assertEq(_account.treasuryAdmin(), _TREASURY_ADMIN);
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

    function test_Allocate_OperatorCanAllocateWithinThresholdAndBuffer() public {
        TreasuryAccount _account = _deployTreasuryAccount(_defaultConfig());

        vm.prank(_TREASURY_ADMIN);
        _account.recordBorrow(600 ether);

        vm.expectEmit(true, false, false, true);
        emit TreasuryAccount.AllocationExecuted(_SAVINGS_VAULT, 100 ether, 500 ether, 100 ether);

        vm.prank(_OPERATOR);
        _account.allocate(_SAVINGS_VAULT, 100 ether);

        assertEq(_account.idleMUSD(), 500 ether);
        assertEq(_account.destinationAllocations(_SAVINGS_VAULT), 100 ether);
    }

    function test_Allocate_OperatorCannotAllocateAboveApprovalThreshold() public {
        TreasuryAccount _account = _deployTreasuryAccount(_defaultConfig());

        vm.prank(_TREASURY_ADMIN);
        _account.recordBorrow(700 ether);

        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.ApprovalRequired.selector, _OPERATOR, 150 ether, 100 ether)
        );

        vm.prank(_OPERATOR);
        _account.allocate(_SAVINGS_VAULT, 150 ether);
    }

    function test_Allocate_ApproverCanAllocateAboveApprovalThreshold() public {
        TreasuryAccount _account = _deployTreasuryAccount(_defaultConfig());

        vm.prank(_TREASURY_ADMIN);
        _account.recordBorrow(700 ether);

        vm.prank(_APPROVER);
        _account.allocate(_SAVINGS_VAULT, 150 ether);

        assertEq(_account.idleMUSD(), 550 ether);
        assertEq(_account.destinationAllocations(_SAVINGS_VAULT), 150 ether);
    }

    function test_Allocate_UnapprovedDestinationReverts() public {
        TreasuryAccount _account = _deployTreasuryAccount(_defaultConfig());

        vm.prank(_TREASURY_ADMIN);
        _account.recordBorrow(500 ether);

        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.NotApprovedDestination.selector, _SECOND_DESTINATION)
        );

        vm.prank(_OPERATOR);
        _account.allocate(_SECOND_DESTINATION, 50 ether);
    }

    function test_Allocate_LiquidityBufferBreachReverts() public {
        TreasuryAccount _account = _deployTreasuryAccount(_defaultConfig());

        vm.prank(_TREASURY_ADMIN);
        _account.recordBorrow(260 ether);

        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.LiquidityBufferBreached.selector, 160 ether, 200 ether)
        );

        vm.prank(_OPERATOR);
        _account.allocate(_SAVINGS_VAULT, 100 ether);
    }

    function test_SetPause_ApproverCanPauseAndBlockFurtherAllocation() public {
        TreasuryAccount _account = _deployTreasuryAccount(_defaultConfig());

        vm.prank(_TREASURY_ADMIN);
        _account.recordBorrow(400 ether);

        vm.prank(_APPROVER);
        _account.setPause(true);

        vm.expectRevert(abi.encodeWithSelector(TreasuryPolicyEngine.PolicyPaused.selector, address(_account)));

        vm.prank(_OPERATOR);
        _account.allocate(_SAVINGS_VAULT, 50 ether);
    }

    function test_WithdrawFromDestination_RestoresIdleBalance() public {
        TreasuryAccount _account = _deployTreasuryAccount(_defaultConfig());

        vm.prank(_TREASURY_ADMIN);
        _account.recordBorrow(600 ether);

        vm.prank(_OPERATOR);
        _account.allocate(_SAVINGS_VAULT, 100 ether);

        vm.prank(_OPERATOR);
        _account.withdrawFromDestination(_SAVINGS_VAULT, 40 ether);

        assertEq(_account.idleMUSD(), 540 ether);
        assertEq(_account.destinationAllocations(_SAVINGS_VAULT), 60 ether);
    }

    function _deployTreasuryAccount(ITreasuryPolicyEngine.AccountPolicyConfig memory _config)
        internal
        returns (TreasuryAccount)
    {
        return TreasuryAccount(_factory.deployTreasuryAccount(_TREASURY_ADMIN, _config));
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
