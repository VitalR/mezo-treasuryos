// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {TreasuryAccount} from "../../src/core/TreasuryAccount.sol";
import {TreasuryAccountFactory} from "../../src/core/TreasuryAccountFactory.sol";
import {TreasuryPolicyEngine} from "../../src/core/TreasuryPolicyEngine.sol";
import {ITreasuryPolicyEngine} from "../../src/interfaces/ITreasuryPolicyEngine.sol";

contract TreasuryAccountTest is Test {
    address internal constant TREASURY_ADMIN = address(0xA11CE);
    address internal constant OPERATOR = address(0xB0B);
    address internal constant APPROVER = address(0xCAFE);
    address internal constant SAVINGS_VAULT = address(0xD00D);
    address internal constant SECOND_DESTINATION = address(0xE11E);

    TreasuryPolicyEngine internal policyEngine;
    TreasuryAccountFactory internal factory;

    function setUp() external {
        policyEngine = new TreasuryPolicyEngine();
        factory = new TreasuryAccountFactory(policyEngine);
    }

    function testDeployTreasuryAccountInitializesPolicyState() external {
        TreasuryAccount account = _deployTreasuryAccount(_defaultConfig());

        (
            address treasuryAdmin,
            address operator,
            address approver,
            uint256 liquidityBuffer,
            uint256 approvalThreshold,
            bool automationEnabled,
            bool paused,
            bool initialized
        ) = policyEngine.getAccountPolicy(address(account));

        assertEq(account.treasuryAdmin(), TREASURY_ADMIN);
        assertEq(address(account.policyEngine()), address(policyEngine));
        assertEq(treasuryAdmin, TREASURY_ADMIN);
        assertEq(operator, OPERATOR);
        assertEq(approver, APPROVER);
        assertEq(liquidityBuffer, 200 ether);
        assertEq(approvalThreshold, 100 ether);
        assertTrue(automationEnabled);
        assertFalse(paused);
        assertTrue(initialized);
        assertTrue(policyEngine.isDestinationApproved(address(account), SAVINGS_VAULT));
        assertEq(policyEngine.allocationCap(address(account), SAVINGS_VAULT), 500 ether);
    }

    function testOperatorCanAllocateWithinThresholdAndBuffer() external {
        TreasuryAccount account = _deployTreasuryAccount(_defaultConfig());

        vm.prank(TREASURY_ADMIN);
        account.recordBorrow(600 ether);

        vm.expectEmit(true, false, false, true);
        emit TreasuryAccount.AllocationExecuted(SAVINGS_VAULT, 100 ether, 500 ether, 100 ether);

        vm.prank(OPERATOR);
        account.allocate(SAVINGS_VAULT, 100 ether);

        assertEq(account.idleMUSD(), 500 ether);
        assertEq(account.destinationAllocations(SAVINGS_VAULT), 100 ether);
    }

    function testOperatorCannotAllocateAboveApprovalThreshold() external {
        TreasuryAccount account = _deployTreasuryAccount(_defaultConfig());

        vm.prank(TREASURY_ADMIN);
        account.recordBorrow(700 ether);

        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.ApprovalRequired.selector, OPERATOR, 150 ether, 100 ether)
        );

        vm.prank(OPERATOR);
        account.allocate(SAVINGS_VAULT, 150 ether);
    }

    function testApproverCanAllocateAboveApprovalThreshold() external {
        TreasuryAccount account = _deployTreasuryAccount(_defaultConfig());

        vm.prank(TREASURY_ADMIN);
        account.recordBorrow(700 ether);

        vm.prank(APPROVER);
        account.allocate(SAVINGS_VAULT, 150 ether);

        assertEq(account.idleMUSD(), 550 ether);
        assertEq(account.destinationAllocations(SAVINGS_VAULT), 150 ether);
    }

    function testAllocateRevertsForUnapprovedDestination() external {
        TreasuryAccount account = _deployTreasuryAccount(_defaultConfig());

        vm.prank(TREASURY_ADMIN);
        account.recordBorrow(500 ether);

        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.NotApprovedDestination.selector, SECOND_DESTINATION)
        );

        vm.prank(OPERATOR);
        account.allocate(SECOND_DESTINATION, 50 ether);
    }

    function testAllocateRevertsWhenLiquidityBufferWouldBeBreached() external {
        TreasuryAccount account = _deployTreasuryAccount(_defaultConfig());

        vm.prank(TREASURY_ADMIN);
        account.recordBorrow(260 ether);

        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.LiquidityBufferBreached.selector, 160 ether, 200 ether)
        );

        vm.prank(OPERATOR);
        account.allocate(SAVINGS_VAULT, 100 ether);
    }

    function testApproverCanPauseAndBlockFurtherAllocation() external {
        TreasuryAccount account = _deployTreasuryAccount(_defaultConfig());

        vm.prank(TREASURY_ADMIN);
        account.recordBorrow(400 ether);

        vm.prank(APPROVER);
        account.setPause(true);

        vm.expectRevert(abi.encodeWithSelector(TreasuryPolicyEngine.PolicyPaused.selector, address(account)));

        vm.prank(OPERATOR);
        account.allocate(SAVINGS_VAULT, 50 ether);
    }

    function testWithdrawRestoresIdleBalance() external {
        TreasuryAccount account = _deployTreasuryAccount(_defaultConfig());

        vm.prank(TREASURY_ADMIN);
        account.recordBorrow(600 ether);

        vm.prank(OPERATOR);
        account.allocate(SAVINGS_VAULT, 100 ether);

        vm.prank(OPERATOR);
        account.withdrawFromDestination(SAVINGS_VAULT, 40 ether);

        assertEq(account.idleMUSD(), 540 ether);
        assertEq(account.destinationAllocations(SAVINGS_VAULT), 60 ether);
    }

    function _deployTreasuryAccount(ITreasuryPolicyEngine.AccountPolicyConfig memory _config)
        internal
        returns (TreasuryAccount)
    {
        return TreasuryAccount(factory.deployTreasuryAccount(TREASURY_ADMIN, _config));
    }

    function _defaultConfig() internal pure returns (ITreasuryPolicyEngine.AccountPolicyConfig memory config) {
        address[] memory destinations = new address[](1);
        destinations[0] = SAVINGS_VAULT;

        uint256[] memory caps = new uint256[](1);
        caps[0] = 500 ether;

        config = ITreasuryPolicyEngine.AccountPolicyConfig({
            operator: OPERATOR,
            approver: APPROVER,
            liquidityBuffer: 200 ether,
            approvalThreshold: 100 ether,
            automationEnabled: true,
            startPaused: false,
            approvedDestinations: destinations,
            destinationCaps: caps
        });
    }
}
