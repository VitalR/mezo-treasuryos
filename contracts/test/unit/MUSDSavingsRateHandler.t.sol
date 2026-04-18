// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";

import { AllocationRouter } from "../../src/adapters/AllocationRouter.sol";
import { MUSDSavingsRateHandler } from "../../src/adapters/MUSDSavingsRateHandler.sol";
import { TreasuryAccount } from "../../src/core/TreasuryAccount.sol";
import { TreasuryAccountFactory } from "../../src/core/TreasuryAccountFactory.sol";
import { TreasuryPolicyEngine } from "../../src/core/TreasuryPolicyEngine.sol";
import { ITreasuryPolicyEngine } from "../../src/interfaces/ITreasuryPolicyEngine.sol";
import { MockBorrowerOperations } from "../helpers/MockBorrowerOperations.sol";
import { MockMUSDSavingsRate } from "../helpers/MockMUSDSavingsRate.sol";

contract MUSDSavingsRateHandlerTest is Test {
    address internal constant _TREASURY_ADMIN = address(0xA11CE);
    address internal constant _OPERATOR = address(0xB0B);
    address internal constant _APPROVER = address(0xCAFE);
    address internal constant _UPPER_HINT = address(0xAAA1);
    address internal constant _LOWER_HINT = address(0xAAA2);

    TreasuryPolicyEngine internal _policyEngine;
    TreasuryAccountFactory internal _factory;
    MockBorrowerOperations internal _borrowerOperations;
    MockMUSDSavingsRate internal _mockSavingsVault;
    AllocationRouter internal _allocationRouter;
    MUSDSavingsRateHandler internal _savingsVaultHandler;
    TreasuryAccount internal _treasuryAccount;

    function setUp() public {
        _policyEngine = new TreasuryPolicyEngine();
        _borrowerOperations = new MockBorrowerOperations();
        _factory = new TreasuryAccountFactory(IERC20(_borrowerOperations.musdToken()), _policyEngine);
        _factory.setTreasuryAdminApproval(_TREASURY_ADMIN, true);
        _mockSavingsVault = new MockMUSDSavingsRate(_borrowerOperations.musdTokenContract());
        _allocationRouter = new AllocationRouter(_TREASURY_ADMIN);
        _savingsVaultHandler = new MUSDSavingsRateHandler(_mockSavingsVault, address(_allocationRouter));

        vm.deal(_TREASURY_ADMIN, 50 ether);
        vm.deal(_OPERATOR, 50 ether);
        vm.deal(_APPROVER, 50 ether);

        _treasuryAccount = TreasuryAccount(payable(_factory.deployTreasuryAccount(_TREASURY_ADMIN, _defaultConfig())));

        vm.prank(_TREASURY_ADMIN);
        _treasuryAccount.setBorrowerOperations(address(_borrowerOperations));

        vm.prank(_TREASURY_ADMIN);
        _treasuryAccount.setAllocationRouter(address(_allocationRouter));

        vm.prank(_TREASURY_ADMIN);
        _allocationRouter.setHandler(address(_mockSavingsVault), _savingsVaultHandler);

        vm.prank(_APPROVER);
        _treasuryAccount.openTrove{ value: 6 ether }(600 ether, _UPPER_HINT, _LOWER_HINT);
    }

    function test_SetAllocationRouter_TreasuryAdminCanSetAllocationRouter() public {
        TreasuryAccount _account =
            TreasuryAccount(payable(_factory.deployTreasuryAccount(_TREASURY_ADMIN, _defaultConfig())));

        vm.prank(_TREASURY_ADMIN);
        _account.setAllocationRouter(address(_allocationRouter));

        assertEq(_account.allocationRouter(), address(_allocationRouter));
    }

    function test_Deposit_OperatorCanDepositIntoSavingsVaultWithinPolicy() public {
        vm.expectEmit(true, true, false, true);
        emit MUSDSavingsRateHandler.SavingsDepositRouted(address(_treasuryAccount), _OPERATOR, 100 ether, 100 ether);

        vm.prank(_OPERATOR);
        uint256 _shares = _allocationRouter.deposit(address(_treasuryAccount), address(_mockSavingsVault), 100 ether);

        assertEq(_shares, 100 ether);
        assertEq(_treasuryAccount.idleMUSD(), 500 ether);
        assertEq(_treasuryAccount.destinationAllocations(address(_mockSavingsVault)), 100 ether);
        assertEq(_mockSavingsVault.balanceOf(address(_treasuryAccount)), 100 ether);
        assertEq(_borrowerOperations.musdTokenContract().balanceOf(address(_treasuryAccount)), 500 ether);
    }

    function test_Deposit_OperatorCannotDepositAboveApprovalThreshold() public {
        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.ApprovalRequired.selector, _OPERATOR, 150 ether, 100 ether)
        );

        vm.prank(_OPERATOR);
        _allocationRouter.deposit(address(_treasuryAccount), address(_mockSavingsVault), 150 ether);
    }

    function test_Deposit_ApproverCanDepositAboveApprovalThreshold() public {
        vm.prank(_APPROVER);
        _allocationRouter.deposit(address(_treasuryAccount), address(_mockSavingsVault), 150 ether);

        assertEq(_treasuryAccount.idleMUSD(), 450 ether);
        assertEq(_treasuryAccount.destinationAllocations(address(_mockSavingsVault)), 150 ether);
        assertEq(_mockSavingsVault.balanceOf(address(_treasuryAccount)), 150 ether);
    }

    function test_Withdraw_RestoresIdleTreasuryBalance() public {
        vm.prank(_OPERATOR);
        _allocationRouter.deposit(address(_treasuryAccount), address(_mockSavingsVault), 100 ether);

        vm.expectEmit(true, true, false, true);
        emit MUSDSavingsRateHandler.SavingsWithdrawalRouted(address(_treasuryAccount), _OPERATOR, 40 ether, 40 ether);

        vm.prank(_OPERATOR);
        uint256 _shares = _allocationRouter.withdraw(address(_treasuryAccount), address(_mockSavingsVault), 40 ether);

        assertEq(_shares, 40 ether);
        assertEq(_treasuryAccount.idleMUSD(), 540 ether);
        assertEq(_treasuryAccount.destinationAllocations(address(_mockSavingsVault)), 60 ether);
        assertEq(_mockSavingsVault.balanceOf(address(_treasuryAccount)), 60 ether);
        assertEq(_borrowerOperations.musdTokenContract().balanceOf(address(_treasuryAccount)), 540 ether);
    }

    function test_ClaimYield_AddsClaimedYieldToIdleTreasuryBalance() public {
        vm.prank(_OPERATOR);
        _allocationRouter.deposit(address(_treasuryAccount), address(_mockSavingsVault), 100 ether);

        _mockSavingsVault.addClaimableYield(address(_treasuryAccount), 25 ether);

        vm.expectEmit(true, true, false, true);
        emit MUSDSavingsRateHandler.SavingsYieldClaimed(address(_treasuryAccount), _OPERATOR, 25 ether);

        vm.prank(_OPERATOR);
        uint256 _claimedYield = _allocationRouter.claimYield(address(_treasuryAccount), address(_mockSavingsVault));

        assertEq(_claimedYield, 25 ether);
        assertEq(_treasuryAccount.idleMUSD(), 525 ether);
        assertEq(_treasuryAccount.destinationAllocations(address(_mockSavingsVault)), 100 ether);
        assertEq(_borrowerOperations.musdTokenContract().balanceOf(address(_treasuryAccount)), 525 ether);
    }

    function test_Deposit_UnconfiguredTreasuryAccountReverts() public {
        TreasuryAccount _unconfiguredAccount =
            TreasuryAccount(payable(_factory.deployTreasuryAccount(_TREASURY_ADMIN, _defaultConfig())));

        vm.prank(_TREASURY_ADMIN);
        _unconfiguredAccount.setBorrowerOperations(address(_borrowerOperations));

        vm.prank(_APPROVER);
        _unconfiguredAccount.openTrove{ value: 4 ether }(400 ether, _UPPER_HINT, _LOWER_HINT);

        vm.expectRevert(abi.encodeWithSelector(MUSDSavingsRateHandler.UnauthorizedCaller.selector, _OPERATOR));

        vm.prank(_OPERATOR);
        _savingsVaultHandler.deposit(address(_unconfiguredAccount), _OPERATOR, 50 ether);
    }

    function _defaultConfig() internal view returns (ITreasuryPolicyEngine.AccountPolicyConfig memory config) {
        address[] memory _destinations = new address[](1);
        _destinations[0] = address(_mockSavingsVault);

        uint256[] memory _caps = new uint256[](1);
        _caps[0] = 500 ether;

        config = ITreasuryPolicyEngine.AccountPolicyConfig({
            operator: _OPERATOR,
            approver: _APPROVER,
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
