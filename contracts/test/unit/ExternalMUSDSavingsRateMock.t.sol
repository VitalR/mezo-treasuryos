// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Test } from "forge-std/Test.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { ExternalMUSDSavingsRateMock } from "../../src/external/ExternalMUSDSavingsRateMock.sol";
import { MockMUSDToken } from "../helpers/MockMUSDToken.sol";

contract ExternalMUSDSavingsRateMockTest is Test {
    using Math for uint256;

    address internal _owner;
    address internal _alice;
    address internal _bob;

    MockMUSDToken internal _musdToken;
    ExternalMUSDSavingsRateMock internal _savingsRate;

    function setUp() public {
        _owner = makeAddr("owner");
        _alice = makeAddr("alice");
        _bob = makeAddr("bob");

        _musdToken = new MockMUSDToken();
        _savingsRate = new ExternalMUSDSavingsRateMock(_owner, _musdToken);

        _musdToken.mint(_owner, 1000 ether);
        _musdToken.mint(_alice, 500 ether);
        _musdToken.mint(_bob, 500 ether);
    }

    function test_FundYield_UpdatesClaimableYieldProRata() public {
        vm.startPrank(_alice);
        _musdToken.approve(address(_savingsRate), 100 ether);
        _savingsRate.deposit(100 ether);
        vm.stopPrank();

        vm.startPrank(_bob);
        _musdToken.approve(address(_savingsRate), 300 ether);
        _savingsRate.deposit(300 ether);
        vm.stopPrank();

        vm.prank(_owner);
        _musdToken.approve(address(_savingsRate), 40 ether);

        vm.prank(_owner);
        _savingsRate.fundYield(40 ether);

        vm.prank(_alice);
        uint256 _aliceClaimed = _savingsRate.claimYield();

        vm.prank(_bob);
        uint256 _bobClaimed = _savingsRate.claimYield();

        assertEq(_aliceClaimed, 10 ether);
        assertEq(_bobClaimed, 30 ether);
        assertEq(_savingsRate.lastYieldFundedAmount(), 40 ether);
        assertEq(_savingsRate.lastYieldFundedAt(), block.timestamp);
    }

    function test_ClaimYield_TransfersFundedYieldToHolder() public {
        vm.startPrank(_alice);
        _musdToken.approve(address(_savingsRate), 200 ether);
        _savingsRate.deposit(200 ether);
        vm.stopPrank();

        vm.prank(_owner);
        _musdToken.approve(address(_savingsRate), 20 ether);

        vm.prank(_owner);
        _savingsRate.fundYield(20 ether);

        uint256 _aliceBalanceBefore = _musdToken.balanceOf(_alice);

        vm.prank(_alice);
        uint256 _claimed = _savingsRate.claimYield();

        assertEq(_claimed, 20 ether);
        assertEq(_musdToken.balanceOf(_alice), _aliceBalanceBefore + 20 ether);
        assertEq(_savingsRate.claimableYield(_alice), 0);
    }

    function test_Withdraw_ClaimsYieldAndReturnsPrincipal() public {
        vm.startPrank(_alice);
        _musdToken.approve(address(_savingsRate), 200 ether);
        _savingsRate.deposit(200 ether);
        vm.stopPrank();

        vm.prank(_owner);
        _musdToken.approve(address(_savingsRate), 20 ether);

        vm.prank(_owner);
        _savingsRate.fundYield(20 ether);

        vm.prank(_alice);
        _savingsRate.withdraw(200 ether);

        assertEq(_musdToken.balanceOf(_alice), 520 ether);
        assertEq(_savingsRate.balanceOf(_alice), 0);
        assertEq(_savingsRate.claimableYield(_alice), 0);
    }

    function test_FundYield_BuffersWhenNoSharesAndDistributesAfterDeposit() public {
        vm.prank(_owner);
        _musdToken.approve(address(_savingsRate), 10 ether);

        vm.prank(_owner);
        _savingsRate.fundYield(10 ether);

        assertEq(_savingsRate.pendingYield(), 10 ether);
        assertEq(_savingsRate.yieldIndex(), 0);

        vm.startPrank(_alice);
        _musdToken.approve(address(_savingsRate), 100 ether);
        _savingsRate.deposit(100 ether);
        vm.stopPrank();

        vm.prank(_owner);
        _musdToken.approve(address(_savingsRate), 10 ether);

        vm.prank(_owner);
        _savingsRate.fundYield(10 ether);

        vm.prank(_alice);
        uint256 _claimed = _savingsRate.claimYield();

        assertEq(_claimed, 20 ether);
        assertEq(_savingsRate.pendingYield(), 0);
    }

    function test_FundYieldForAnnualRateBps_ReturnsZeroWhenNoShares() public {
        vm.prank(_owner);
        uint256 _funded = _savingsRate.fundYieldForAnnualRateBps(500, 7 days);

        assertEq(_funded, 0);
        assertEq(_savingsRate.lastYieldFundedAmount(), 0);
        assertEq(_savingsRate.lastYieldFundedAt(), 0);
    }

    function test_Transfer_CheckpointsYieldBeforeMovingShares() public {
        vm.startPrank(_alice);
        _musdToken.approve(address(_savingsRate), 100 ether);
        _savingsRate.deposit(100 ether);
        vm.stopPrank();

        vm.prank(_owner);
        _musdToken.approve(address(_savingsRate), 20 ether);

        vm.prank(_owner);
        _savingsRate.fundYield(20 ether);

        vm.prank(_alice);
        _savingsRate.transfer(_bob, 50 ether);

        vm.prank(_owner);
        _musdToken.approve(address(_savingsRate), 20 ether);

        vm.prank(_owner);
        _savingsRate.fundYield(20 ether);

        vm.prank(_alice);
        uint256 _aliceClaimed = _savingsRate.claimYield();

        vm.prank(_bob);
        uint256 _bobClaimed = _savingsRate.claimYield();

        assertEq(_aliceClaimed, 30 ether);
        assertEq(_bobClaimed, 10 ether);
    }

    function test_RevertsForInvalidAmountsAndNoShares() public {
        vm.expectRevert(ExternalMUSDSavingsRateMock.ZeroAmount.selector);
        _savingsRate.deposit(0);

        vm.expectRevert(ExternalMUSDSavingsRateMock.ZeroAmount.selector);
        _savingsRate.withdraw(0);

        vm.expectRevert(ExternalMUSDSavingsRateMock.InsufficientBalance.selector);
        _savingsRate.withdraw(1);

        vm.expectRevert(ExternalMUSDSavingsRateMock.ZeroAmount.selector);
        _savingsRate.quoteYieldForAnnualRateBps(0, 7 days);

        vm.expectRevert(ExternalMUSDSavingsRateMock.ZeroAmount.selector);
        _savingsRate.quoteYieldForAnnualRateBps(500, 0);

        vm.expectRevert(ExternalMUSDSavingsRateMock.NoShares.selector);
        _savingsRate.claimYield();
    }

    function test_QuoteYieldForAnnualRateBps_ReturnsWeeklyAmountForFivePercentAnnualRate() public {
        vm.startPrank(_alice);
        _musdToken.approve(address(_savingsRate), 400 ether);
        _savingsRate.deposit(400 ether);
        vm.stopPrank();

        uint256 _quoted = _savingsRate.quoteYieldForAnnualRateBps(500, 7 days);
        uint256 _expected = uint256(400 ether).mulDiv(500 * 7 days, 10_000 * 365 days);

        assertEq(_quoted, _expected);
    }

    function test_FundYieldForAnnualRateBps_FundsQuotedYieldAndMakesItClaimable() public {
        vm.startPrank(_alice);
        _musdToken.approve(address(_savingsRate), 400 ether);
        _savingsRate.deposit(400 ether);
        vm.stopPrank();

        uint256 _expected = _savingsRate.quoteYieldForAnnualRateBps(500, 7 days);

        vm.prank(_owner);
        _musdToken.approve(address(_savingsRate), _expected);

        vm.prank(_owner);
        uint256 _funded = _savingsRate.fundYieldForAnnualRateBps(500, 7 days);

        vm.prank(_alice);
        uint256 _claimed = _savingsRate.claimYield();

        assertEq(_funded, _expected);
        assertLe(_claimed, _expected);
        assertGe(_claimed, _expected - 100);
        assertEq(_savingsRate.lastYieldFundedAmount(), _expected);
        assertEq(_savingsRate.lastYieldFundedAt(), block.timestamp);
    }
}
