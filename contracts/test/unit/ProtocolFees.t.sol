// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

import { ProtocolFeeManager } from "../../src/fees/ProtocolFeeManager.sol";
import { ProtocolFeeVault } from "../../src/fees/ProtocolFeeVault.sol";
import { MockMUSDToken } from "../helpers/MockMUSDToken.sol";

contract ProtocolFeesTest is Test {
    address internal constant _OWNER = address(0xA11CE);
    address internal constant _PAYER = address(0xB0B);
    address internal constant _TREASURY = address(0xCAFE);
    address internal constant _STRANGER = address(0xBAD);
    address internal constant _EOA_VAULT = address(0xFEE);
    bytes32 internal constant _MAY_2026 = bytes32("2026-05");
    bytes32 internal constant _FEE_RECEIVED_TOPIC = keccak256("FeeReceived(address,address,uint256,bytes32)");
    bytes32 internal constant _SUBSCRIPTION_PAID_TOPIC =
        keccak256("SubscriptionPaid(address,address,address,uint256,bytes32,address)");
    bytes32 internal constant _NATIVE_SUBSCRIPTION_PAID_TOPIC =
        keccak256("NativeSubscriptionPaid(address,address,uint256,bytes32,address)");

    ProtocolFeeVault internal _vault;
    ProtocolFeeManager internal _manager;
    MockMUSDToken internal _musd;
    FeeRecipient internal _recipient;

    function setUp() public {
        _vault = new ProtocolFeeVault(_OWNER);
        _manager = new ProtocolFeeManager(_OWNER, address(_vault));
        _musd = new MockMUSDToken();
        _recipient = new FeeRecipient();
    }

    function test_DefaultFeesAreZeroAndDisabled() public view {
        assertEq(_manager.feeVault(), address(_vault));
        assertFalse(_manager.feesEnabled());
        assertEq(_manager.performanceFeeBps(), 0);
        assertEq(_manager.originationFeeBps(), 0);
        assertEq(_manager.optimizationActionFeeBps(), 0);
        assertEq(_manager.quotePerformanceFee(1000 ether, 1100 ether), 0);
        assertEq(_manager.quoteOriginationFee(1000 ether), 0);
        assertEq(_manager.quoteOptimizationActionFee(1000 ether), 0);
    }

    function test_FeesDisabledReturnsZeroEvenWhenConfigured() public {
        vm.prank(_OWNER);
        _manager.setFeeConfig(address(_vault), false, 300, 25, 5);

        assertEq(_manager.quotePerformanceFee(1000 ether, 1100 ether), 0);
        assertEq(_manager.quoteBpsFee(1000 ether, 300), 0);
        assertEq(_manager.quoteBpsFee(1000 ether, 10_001), 0);
        assertEq(_manager.quoteOriginationFee(1000 ether), 0);
        assertEq(_manager.quoteOptimizationActionFee(1000 ether), 0);
    }

    function test_SetFeeConfig_CannotSetFeeAboveCap() public {
        vm.startPrank(_OWNER);

        vm.expectRevert(
            abi.encodeWithSelector(
                ProtocolFeeManager.FeeBpsAboveCap.selector, _manager.PERFORMANCE_FEE_TYPE(), 301, 300
            )
        );
        _manager.setFeeConfig(address(_vault), true, 301, 0, 0);

        vm.expectRevert(
            abi.encodeWithSelector(ProtocolFeeManager.FeeBpsAboveCap.selector, _manager.ORIGINATION_FEE_TYPE(), 26, 25)
        );
        _manager.setFeeConfig(address(_vault), true, 0, 26, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ProtocolFeeManager.FeeBpsAboveCap.selector, _manager.OPTIMIZATION_ACTION_FEE_TYPE(), 6, 5
            )
        );
        _manager.setFeeConfig(address(_vault), true, 0, 0, 6);

        vm.stopPrank();
    }

    function test_FeeVaultCannotBeZeroOrEOA() public {
        vm.expectRevert(abi.encodeWithSelector(ProtocolFeeManager.InvalidFeeVault.selector, address(0)));
        new ProtocolFeeManager(_OWNER, address(0));

        vm.startPrank(_OWNER);

        vm.expectRevert(abi.encodeWithSelector(ProtocolFeeManager.InvalidFeeVault.selector, address(0)));
        _manager.setFeeConfig(address(0), false, 0, 0, 0);

        vm.expectRevert(abi.encodeWithSelector(ProtocolFeeManager.InvalidFeeVault.selector, _EOA_VAULT));
        _manager.setFeeConfig(_EOA_VAULT, false, 0, 0, 0);

        vm.stopPrank();
    }

    function test_QuotePerformanceFee_AppliesOnlyToProfit() public {
        vm.prank(_OWNER);
        _manager.setFeeConfig(address(_vault), true, 300, 25, 5);

        assertEq(_manager.quotePerformanceFee(1000 ether, 1100 ether), 3 ether);
        assertEq(_manager.quotePerformanceFee(1000 ether, 1000 ether), 0);
        assertEq(_manager.quotePerformanceFee(1000 ether, 900 ether), 0);
        assertEq(_manager.quoteOriginationFee(1000 ether), 2.5 ether);
        assertEq(_manager.quoteOptimizationActionFee(1000 ether), 0.5 ether);
    }

    function test_SetFeeConfig_OnlyOwnerCanUpdateConfig() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _STRANGER));
        vm.prank(_STRANGER);
        _manager.setFeeConfig(address(_vault), true, 300, 25, 5);
    }

    function test_PaySubscription_RoutesMUSDToProtocolVault() public {
        vm.prank(_OWNER);
        _manager.setFeeConfig(address(_vault), true, 300, 25, 5);
        vm.prank(_OWNER);
        _manager.setAcceptedSubscriptionToken(IERC20(address(_musd)), true);

        _musd.mint(_PAYER, 1000 ether);

        vm.recordLogs();

        vm.startPrank(_PAYER);
        _musd.approve(address(_manager), 100 ether);
        _manager.paySubscription(_TREASURY, IERC20(address(_musd)), 100 ether, _MAY_2026);
        vm.stopPrank();

        assertEq(_musd.balanceOf(address(_vault)), 100 ether);
        assertEq(_musd.balanceOf(_PAYER), 900 ether);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertTrue(_hasTopic(entries, _SUBSCRIPTION_PAID_TOPIC));
        assertFalse(_hasTopic(entries, _FEE_RECEIVED_TOPIC));
    }

    function test_PaySubscription_UnacceptedTokenReverts() public {
        vm.prank(_OWNER);
        _manager.setFeeConfig(address(_vault), true, 300, 25, 5);

        _musd.mint(_PAYER, 1000 ether);

        vm.startPrank(_PAYER);
        _musd.approve(address(_manager), 100 ether);
        vm.expectRevert(
            abi.encodeWithSelector(ProtocolFeeManager.SubscriptionTokenNotAccepted.selector, address(_musd))
        );
        _manager.paySubscription(_TREASURY, IERC20(address(_musd)), 100 ether, _MAY_2026);
        vm.stopPrank();
    }

    function test_PaySubscription_DisabledReverts() public {
        vm.expectRevert(ProtocolFeeManager.FeesDisabled.selector);
        vm.prank(_PAYER);
        _manager.paySubscription(_TREASURY, IERC20(address(_musd)), 100 ether, _MAY_2026);
    }

    function test_PayNativeSubscription_ForwardsNativeBTCToProtocolVault() public {
        vm.prank(_OWNER);
        _manager.setFeeConfig(address(_vault), true, 300, 25, 5);

        vm.deal(_PAYER, 1 ether);
        vm.recordLogs();

        vm.prank(_PAYER);
        _manager.payNativeSubscription{ value: 0.25 ether }(_TREASURY, _MAY_2026);

        assertEq(address(_vault).balance, 0.25 ether);
        assertEq(_PAYER.balance, 0.75 ether);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertTrue(_hasTopic(entries, _NATIVE_SUBSCRIPTION_PAID_TOPIC));
        assertFalse(_hasTopic(entries, _FEE_RECEIVED_TOPIC));
    }

    function test_PayNativeSubscription_DisabledReverts() public {
        vm.deal(_PAYER, 1 ether);

        vm.expectRevert(ProtocolFeeManager.FeesDisabled.selector);
        vm.prank(_PAYER);
        _manager.payNativeSubscription{ value: 0.25 ether }(_TREASURY, _MAY_2026);
    }

    function test_VaultCanReceiveNativeAndERC20() public {
        vm.deal(_PAYER, 1 ether);

        vm.recordLogs();

        vm.prank(_PAYER);
        _vault.depositNative{ value: 0.25 ether }(_vault.DIRECT_NATIVE_FEE_TYPE());

        assertEq(address(_vault).balance, 0.25 ether);
        assertTrue(_hasTopic(vm.getRecordedLogs(), _FEE_RECEIVED_TOPIC));

        _musd.mint(_PAYER, 100 ether);

        vm.startPrank(_PAYER);
        _musd.approve(address(_vault), 40 ether);
        _vault.depositERC20(IERC20(address(_musd)), 40 ether, _vault.DIRECT_ERC20_FEE_TYPE());
        vm.stopPrank();

        assertEq(_musd.balanceOf(address(_vault)), 40 ether);
    }

    function test_VaultWithdrawOnlyOwner() public {
        vm.deal(address(_vault), 1 ether);
        _musd.mint(address(_vault), 100 ether);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _STRANGER));
        vm.prank(_STRANGER);
        _vault.withdrawNative(payable(address(_recipient)), 0.25 ether);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _STRANGER));
        vm.prank(_STRANGER);
        _vault.withdrawERC20(IERC20(address(_musd)), address(_recipient), 25 ether);

        vm.startPrank(_OWNER);
        _vault.withdrawNative(payable(address(_recipient)), 0.25 ether);
        _vault.withdrawERC20(IERC20(address(_musd)), address(_recipient), 25 ether);
        vm.stopPrank();

        assertEq(address(_recipient).balance, 0.25 ether);
        assertEq(_musd.balanceOf(address(_recipient)), 25 ether);
    }

    function test_VaultWithdrawRejectsEOARecipient() public {
        vm.deal(address(_vault), 1 ether);
        _musd.mint(address(_vault), 100 ether);

        vm.startPrank(_OWNER);

        vm.expectRevert(abi.encodeWithSelector(ProtocolFeeVault.InvalidWithdrawalRecipient.selector, _STRANGER));
        _vault.withdrawNative(payable(_STRANGER), 0.25 ether);

        vm.expectRevert(abi.encodeWithSelector(ProtocolFeeVault.InvalidWithdrawalRecipient.selector, _STRANGER));
        _vault.withdrawERC20(IERC20(address(_musd)), _STRANGER, 25 ether);

        vm.stopPrank();
    }

    function _hasTopic(Vm.Log[] memory _entries, bytes32 _topic) internal pure returns (bool) {
        for (uint256 i = 0; i < _entries.length; i++) {
            if (_entries[i].topics.length > 0 && _entries[i].topics[0] == _topic) {
                return true;
            }
        }

        return false;
    }
}

contract FeeRecipient {
    receive() external payable { }
}
