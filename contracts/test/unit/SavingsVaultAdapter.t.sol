// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Test } from "forge-std/Test.sol";

import { SavingsVaultAdapter } from "../../src/adapters/SavingsVaultAdapter.sol";
import { TreasuryAccount } from "../../src/core/TreasuryAccount.sol";
import { TreasuryAccountFactory } from "../../src/core/TreasuryAccountFactory.sol";
import { TreasuryPolicyEngine } from "../../src/core/TreasuryPolicyEngine.sol";
import { IMUSDSavingsVault } from "../../src/interfaces/IMUSDSavingsVault.sol";
import { ITreasuryPolicyEngine } from "../../src/interfaces/ITreasuryPolicyEngine.sol";

contract MockMUSDSavingsVault is IMUSDSavingsVault {
    uint256 public totalAssets;
    uint256 public totalShares;
    uint256 public lastDepositAssets;
    address public lastDepositReceiver;
    uint256 public lastWithdrawAssets;
    address public lastWithdrawReceiver;
    address public lastWithdrawOwner;

    function deposit(uint256 _assets, address _receiver) external returns (uint256 shares) {
        totalAssets += _assets;
        totalShares += _assets;
        lastDepositAssets = _assets;
        lastDepositReceiver = _receiver;
        shares = _assets;
    }

    function withdraw(uint256 _assets, address _receiver, address _owner) external returns (uint256 shares) {
        totalAssets -= _assets;
        totalShares -= _assets;
        lastWithdrawAssets = _assets;
        lastWithdrawReceiver = _receiver;
        lastWithdrawOwner = _owner;
        shares = _assets;
    }
}

contract SavingsVaultAdapterTest is Test {
    address internal constant _TREASURY_ADMIN = address(0xA11CE);
    address internal constant _OPERATOR = address(0xB0B);
    address internal constant _APPROVER = address(0xCAFE);

    TreasuryPolicyEngine internal _policyEngine;
    TreasuryAccountFactory internal _factory;
    MockMUSDSavingsVault internal _mockSavingsVault;
    SavingsVaultAdapter internal _savingsVaultAdapter;
    TreasuryAccount internal _treasuryAccount;

    function setUp() public {
        _policyEngine = new TreasuryPolicyEngine();
        _factory = new TreasuryAccountFactory(_policyEngine);
        _mockSavingsVault = new MockMUSDSavingsVault();
        _savingsVaultAdapter = new SavingsVaultAdapter(_mockSavingsVault);

        _treasuryAccount = TreasuryAccount(_factory.deployTreasuryAccount(_TREASURY_ADMIN, _defaultConfig()));

        vm.prank(_TREASURY_ADMIN);
        _treasuryAccount.setAllocationAdapter(address(_savingsVaultAdapter));

        vm.prank(_TREASURY_ADMIN);
        _treasuryAccount.recordBorrow(600 ether);
    }

    function test_SetAllocationAdapter_TreasuryAdminCanSetAllocationAdapter() public {
        TreasuryAccount _account = TreasuryAccount(_factory.deployTreasuryAccount(_TREASURY_ADMIN, _defaultConfig()));

        vm.prank(_TREASURY_ADMIN);
        _account.setAllocationAdapter(address(_savingsVaultAdapter));

        assertEq(_account.allocationAdapter(), address(_savingsVaultAdapter));
    }

    function test_Deposit_OperatorCanDepositIntoSavingsVaultWithinPolicy() public {
        vm.expectEmit(true, true, false, true);
        emit SavingsVaultAdapter.SavingsDepositRouted(address(_treasuryAccount), _OPERATOR, 100 ether, 100 ether);

        vm.prank(_OPERATOR);
        uint256 _shares = _savingsVaultAdapter.deposit(_treasuryAccount, 100 ether);

        assertEq(_shares, 100 ether);
        assertEq(_treasuryAccount.idleMUSD(), 500 ether);
        assertEq(_treasuryAccount.destinationAllocations(address(_mockSavingsVault)), 100 ether);
        assertEq(_mockSavingsVault.totalAssets(), 100 ether);
        assertEq(_mockSavingsVault.lastDepositAssets(), 100 ether);
        assertEq(_mockSavingsVault.lastDepositReceiver(), address(_treasuryAccount));
    }

    function test_Deposit_OperatorCannotDepositAboveApprovalThreshold() public {
        vm.expectRevert(
            abi.encodeWithSelector(TreasuryPolicyEngine.ApprovalRequired.selector, _OPERATOR, 150 ether, 100 ether)
        );

        vm.prank(_OPERATOR);
        _savingsVaultAdapter.deposit(_treasuryAccount, 150 ether);
    }

    function test_Deposit_ApproverCanDepositAboveApprovalThreshold() public {
        vm.prank(_APPROVER);
        _savingsVaultAdapter.deposit(_treasuryAccount, 150 ether);

        assertEq(_treasuryAccount.idleMUSD(), 450 ether);
        assertEq(_treasuryAccount.destinationAllocations(address(_mockSavingsVault)), 150 ether);
    }

    function test_Withdraw_RestoresIdleTreasuryBalance() public {
        vm.prank(_OPERATOR);
        _savingsVaultAdapter.deposit(_treasuryAccount, 100 ether);

        vm.expectEmit(true, true, false, true);
        emit SavingsVaultAdapter.SavingsWithdrawalRouted(address(_treasuryAccount), _OPERATOR, 40 ether, 40 ether);

        vm.prank(_OPERATOR);
        uint256 _shares = _savingsVaultAdapter.withdraw(_treasuryAccount, 40 ether);

        assertEq(_shares, 40 ether);
        assertEq(_treasuryAccount.idleMUSD(), 540 ether);
        assertEq(_treasuryAccount.destinationAllocations(address(_mockSavingsVault)), 60 ether);
        assertEq(_mockSavingsVault.totalAssets(), 60 ether);
        assertEq(_mockSavingsVault.lastWithdrawAssets(), 40 ether);
        assertEq(_mockSavingsVault.lastWithdrawReceiver(), address(_treasuryAccount));
        assertEq(_mockSavingsVault.lastWithdrawOwner(), address(_treasuryAccount));
    }

    function test_Deposit_UnconfiguredTreasuryAccountReverts() public {
        TreasuryAccount _unconfiguredAccount =
            TreasuryAccount(_factory.deployTreasuryAccount(_TREASURY_ADMIN, _defaultConfig()));

        vm.prank(_TREASURY_ADMIN);
        _unconfiguredAccount.recordBorrow(400 ether);

        vm.expectRevert(
            abi.encodeWithSelector(TreasuryAccount.UnauthorizedCaller.selector, address(_savingsVaultAdapter))
        );

        vm.prank(_OPERATOR);
        _savingsVaultAdapter.deposit(_unconfiguredAccount, 50 ether);
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
            automationEnabled: true,
            startPaused: false,
            approvedDestinations: _destinations,
            destinationCaps: _caps
        });
    }
}
