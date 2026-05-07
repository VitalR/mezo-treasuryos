// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";

import { AllocationRouter } from "../../src/adapters/AllocationRouter.sol";
import { TigrisStablePoolHandler } from "../../src/adapters/TigrisStablePoolHandler.sol";
import { TreasuryAccount } from "../../src/core/TreasuryAccount.sol";
import { TreasuryAccountFactory } from "../../src/core/TreasuryAccountFactory.sol";
import { TreasuryPolicyEngine } from "../../src/core/TreasuryPolicyEngine.sol";
import { ITreasuryPolicyEngine } from "../../src/interfaces/ITreasuryPolicyEngine.sol";
import { MockBorrowerOperations } from "../helpers/MockBorrowerOperations.sol";
import { MockMUSDToken } from "../helpers/MockMUSDToken.sol";
import { MockTigrisBasicRouter } from "../helpers/MockTigrisBasicRouter.sol";
import { MockTigrisLPToken } from "../helpers/MockTigrisLPToken.sol";

contract TigrisStablePoolHandlerTest is Test {
    address internal constant _TREASURY_ADMIN = address(0xA11CE);
    address internal constant _OPERATOR = address(0xB0B);
    address internal constant _APPROVER = address(0xCAFE);
    address internal constant _UPPER_HINT = address(0xAAA1);
    address internal constant _LOWER_HINT = address(0xAAA2);
    address internal constant _POOL_FACTORY = address(0xFACADE);

    TreasuryPolicyEngine internal _policyEngine;
    TreasuryAccountFactory internal _factory;
    MockBorrowerOperations internal _borrowerOperations;
    MockMUSDToken internal _pairedStable;
    MockTigrisLPToken internal _poolToken;
    MockTigrisBasicRouter internal _router;
    AllocationRouter internal _allocationRouter;
    TigrisStablePoolHandler internal _handler;
    TreasuryAccount internal _treasuryAccount;

    function setUp() public {
        _policyEngine = new TreasuryPolicyEngine();
        _borrowerOperations = new MockBorrowerOperations();
        _factory = new TreasuryAccountFactory(IERC20(_borrowerOperations.musdToken()), _policyEngine);
        _factory.setTreasuryAdminApproval(_TREASURY_ADMIN, true);
        _pairedStable = new MockMUSDToken();
        _poolToken = new MockTigrisLPToken();
        _router = new MockTigrisBasicRouter(_borrowerOperations.musdTokenContract(), _pairedStable, _poolToken);
        _allocationRouter = new AllocationRouter(_TREASURY_ADMIN);
        _handler = new TigrisStablePoolHandler(
            address(_allocationRouter),
            _router,
            address(_poolToken),
            _POOL_FACTORY,
            true,
            IERC20(_borrowerOperations.musdToken()),
            IERC20(address(_pairedStable)),
            1 hours,
            100
        );

        vm.deal(_TREASURY_ADMIN, 50 ether);
        vm.deal(_OPERATOR, 50 ether);
        vm.deal(_APPROVER, 50 ether);

        _treasuryAccount = TreasuryAccount(payable(_factory.deployTreasuryAccount(_TREASURY_ADMIN, _defaultConfig())));

        vm.prank(_TREASURY_ADMIN);
        _treasuryAccount.setBorrowerOperations(address(_borrowerOperations));

        vm.prank(_TREASURY_ADMIN);
        _treasuryAccount.setAllocationRouter(address(_allocationRouter));

        vm.prank(_TREASURY_ADMIN);
        _allocationRouter.setHandler(address(_poolToken), _handler);

        vm.prank(_APPROVER);
        _treasuryAccount.openTrove{ value: 6 ether }(600 ether, _UPPER_HINT, _LOWER_HINT);
    }

    function test_Deposit_OperatorRoutesIdleMUSDIntoTigrisStablePool() public {
        vm.prank(_OPERATOR);
        uint256 _liquidity = _allocationRouter.deposit(address(_treasuryAccount), address(_poolToken), 100 ether);

        assertEq(_liquidity, 100 ether);
        assertEq(_treasuryAccount.idleMUSD(), 500 ether);
        assertEq(_treasuryAccount.destinationAllocations(address(_poolToken)), 100 ether);
        assertEq(_poolToken.balanceOf(address(_treasuryAccount)), 100 ether);
        assertEq(_pairedStable.balanceOf(address(_treasuryAccount)), 0);
        assertEq(_router.lastSwapAmountOutMin(), 49.5 ether);
        assertTrue(_router.lastSwapRouteStable());
        assertEq(_router.lastSwapRouteFactory(), _POOL_FACTORY);
        assertEq(_router.lastAddAmountAMin(), 49.5 ether);
        assertEq(_router.lastAddAmountBMin(), 49.5 ether);
        assertTrue(_router.lastAddStable());
    }

    function test_Deposit_RefundsUnusedMUSDWhenPoolUsesPartialLiquidity() public {
        _router.setAddLiquidityUsageBps(9900);

        vm.prank(_OPERATOR);
        uint256 _liquidity = _allocationRouter.deposit(address(_treasuryAccount), address(_poolToken), 100 ether);

        assertEq(_liquidity, 99 ether);
        assertEq(_treasuryAccount.idleMUSD(), 501 ether);
        assertEq(_treasuryAccount.destinationAllocations(address(_poolToken)), 99 ether);
        assertEq(_poolToken.balanceOf(address(_treasuryAccount)), 99 ether);
        assertEq(_pairedStable.balanceOf(address(_treasuryAccount)), 0);
    }

    function test_Deposit_RevertsWhenSwapOutputIsBelowMinimum() public {
        _router.setSwapOutputBps(9800);

        vm.expectRevert(
            abi.encodeWithSelector(MockTigrisBasicRouter.InsufficientSwapOutput.selector, 49 ether, 49.5 ether)
        );

        vm.prank(_OPERATOR);
        _allocationRouter.deposit(address(_treasuryAccount), address(_poolToken), 100 ether);
    }

    function test_Deposit_RevertsWhenSwapQuoteIsZero() public {
        _router.setSwapQuoteBps(0);

        vm.expectRevert(abi.encodeWithSelector(TigrisStablePoolHandler.ZeroSwapQuote.selector, 50 ether));

        vm.prank(_OPERATOR);
        _allocationRouter.deposit(address(_treasuryAccount), address(_poolToken), 100 ether);
    }

    function test_Deposit_RevertsWhenLiquidityUsedIsBelowMinimum() public {
        _router.setAddLiquidityUsageBps(9800);

        vm.expectRevert(
            abi.encodeWithSelector(MockTigrisBasicRouter.InsufficientLiquidityAmountA.selector, 49 ether, 49.5 ether)
        );

        vm.prank(_OPERATOR);
        _allocationRouter.deposit(address(_treasuryAccount), address(_poolToken), 100 ether);
    }

    function test_Deposit_RevertsWhenLiquidityQuoteIsZero() public {
        _router.setAddLiquidityQuoteBps(0);

        vm.expectRevert(TigrisStablePoolHandler.ZeroLiquidity.selector);

        vm.prank(_OPERATOR);
        _allocationRouter.deposit(address(_treasuryAccount), address(_poolToken), 100 ether);
    }

    function test_Deposit_UsesRouterQuoteForSwapMinimums() public {
        _router.setSwapQuoteBps(100);
        _router.setSwapOutputBps(100);

        vm.prank(_OPERATOR);
        uint256 _liquidity = _allocationRouter.deposit(address(_treasuryAccount), address(_poolToken), 100 ether);

        assertEq(_liquidity, 50.5 ether);
        assertEq(_router.lastSwapAmountOutMin(), 0.495 ether);
        assertEq(_router.lastAddAmountAMin(), 49.5 ether);
        assertEq(_router.lastAddAmountBMin(), 0.495 ether);
    }

    function test_Deposit_UnexpectedSwapPathLengthReverts() public {
        _router.setAddLiquidityUsageBps(9900);
        _router.setSwapReturnPathLength(1);

        vm.expectRevert(abi.encodeWithSelector(TigrisStablePoolHandler.UnexpectedSwapPathLength.selector, 1));

        vm.prank(_OPERATOR);
        _allocationRouter.deposit(address(_treasuryAccount), address(_poolToken), 100 ether);
    }

    function test_Withdraw_OperatorUnwindsStablePoolBackToIdleMUSD() public {
        vm.prank(_OPERATOR);
        _allocationRouter.deposit(address(_treasuryAccount), address(_poolToken), 100 ether);

        vm.prank(_OPERATOR);
        uint256 _liquidityBurned = _allocationRouter.withdraw(address(_treasuryAccount), address(_poolToken), 40 ether);

        assertEq(_liquidityBurned, 40 ether);
        assertEq(_treasuryAccount.idleMUSD(), 540 ether);
        assertEq(_treasuryAccount.destinationAllocations(address(_poolToken)), 60 ether);
        assertEq(_poolToken.balanceOf(address(_treasuryAccount)), 60 ether);
        assertEq(_pairedStable.balanceOf(address(_treasuryAccount)), 0);
        assertEq(_router.lastRemoveAmountAMin(), 19.8 ether);
        assertEq(_router.lastRemoveAmountBMin(), 19.8 ether);
        assertTrue(_router.lastRemoveStable());
        assertEq(_router.lastSwapAmountOutMin(), 19.8 ether);
        assertTrue(_router.lastSwapRouteStable());
        assertEq(_router.lastSwapRouteFactory(), _POOL_FACTORY);
    }

    function test_Withdraw_RevertsWhenRemoveLiquidityOutputIsBelowMinimum() public {
        vm.prank(_OPERATOR);
        _allocationRouter.deposit(address(_treasuryAccount), address(_poolToken), 100 ether);

        _router.setRemoveLiquidityOutputBps(9800);

        vm.expectRevert(
            abi.encodeWithSelector(MockTigrisBasicRouter.InsufficientRemoveAmountA.selector, 19.6 ether, 19.8 ether)
        );

        vm.prank(_OPERATOR);
        _allocationRouter.withdraw(address(_treasuryAccount), address(_poolToken), 40 ether);
    }

    function test_Withdraw_NoLiquidityReverts() public {
        vm.expectRevert(TigrisStablePoolHandler.ZeroLiquidity.selector);

        vm.prank(_OPERATOR);
        _allocationRouter.withdraw(address(_treasuryAccount), address(_poolToken), 40 ether);
    }

    function test_RestoreLiquidityBuffer_UsesWorkflowWithdrawalPath() public {
        vm.prank(_APPROVER);
        _allocationRouter.deposit(address(_treasuryAccount), address(_poolToken), 350 ether);

        vm.prank(_TREASURY_ADMIN);
        _treasuryAccount.disburseMUSD(address(0xABCD), 120 ether);

        vm.prank(_TREASURY_ADMIN);
        uint256 _restoredAmount = _treasuryAccount.restoreLiquidityBuffer(address(_poolToken), 80 ether);

        assertEq(_restoredAmount, 70 ether);
        assertEq(_treasuryAccount.idleMUSD(), 200 ether);
        assertEq(_treasuryAccount.destinationAllocations(address(_poolToken)), 280 ether);
        assertEq(_poolToken.balanceOf(address(_treasuryAccount)), 280 ether);
    }

    function test_WithdrawFromDestinationAndRepay_UsesWorkflowWithdrawalPath() public {
        vm.prank(_APPROVER);
        _allocationRouter.deposit(address(_treasuryAccount), address(_poolToken), 220 ether);

        vm.prank(_TREASURY_ADMIN);
        _treasuryAccount.disburseMUSD(address(0xABCD), 250 ether);

        vm.prank(_TREASURY_ADMIN);
        (uint256 _actualWithdrawAmount, uint256 _actualRepaidAmount) = _treasuryAccount.withdrawFromDestinationAndRepay(
            address(_poolToken), 120 ether, 90 ether, _UPPER_HINT, _LOWER_HINT
        );

        assertEq(_actualWithdrawAmount, 120 ether);
        assertEq(_actualRepaidAmount, 90 ether);
        assertEq(_treasuryAccount.idleMUSD(), 160 ether);
        assertEq(_treasuryAccount.destinationAllocations(address(_poolToken)), 100 ether);
        assertEq(_poolToken.balanceOf(address(_treasuryAccount)), 100 ether);
        assertEq(_treasuryAccount.positionTotalDebt(), 510 ether);
    }

    function test_ClaimYield_ReturnsZeroForStablePoolSleeve() public {
        vm.prank(_OPERATOR);
        uint256 _claimedYield = _allocationRouter.claimYield(address(_treasuryAccount), address(_poolToken));

        assertEq(_claimedYield, 0);
    }

    function test_Metadata_ReturnsRouterAndPairedToken() public view {
        assertEq(_handler.router(), address(_router));
        assertEq(_handler.pairedToken(), address(_pairedStable));
        assertEq(_handler.destination(), address(_poolToken));
        assertEq(_handler.poolFactory(), _POOL_FACTORY);
        assertTrue(_handler.poolStable());
        assertEq(_handler.maxSlippageBps(), 100);
    }

    function test_Handler_UnauthorizedDirectCallerReverts() public {
        vm.expectRevert(abi.encodeWithSelector(TigrisStablePoolHandler.UnauthorizedCaller.selector, _OPERATOR));

        vm.prank(_OPERATOR);
        _handler.deposit(address(_treasuryAccount), _OPERATOR, 50 ether);
    }

    function test_GetTreasuryComposition_ReturnsTigrisStablePoolMetadata() public {
        vm.prank(_OPERATOR);
        _allocationRouter.deposit(address(_treasuryAccount), address(_poolToken), 100 ether);

        address[] memory _destinations = new address[](1);
        _destinations[0] = address(_poolToken);

        TreasuryAccount.TreasuryCompositionState memory _state = _treasuryAccount.getTreasuryComposition(_destinations);

        assertEq(_state.exposures.length, 1);
        assertEq(_state.exposures[0].destination, address(_poolToken));
        assertEq(_state.exposures[0].handler, address(_handler));
        assertEq(_state.exposures[0].pairedToken, address(_pairedStable));
        assertEq(_state.exposures[0].receiptToken, address(_poolToken));
        assertEq(_state.exposures[0].receiptBalance, 100 ether);
        assertTrue(_state.exposures[0].supportsTigrisStablePool);
        assertFalse(_state.exposures[0].supportsSavingsRate);
        assertEq(_state.exposures[0].claimableYield, 0);
        assertEq(_state.exposures[0].yieldToken, address(0));
    }

    function _defaultConfig() internal view returns (ITreasuryPolicyEngine.AccountPolicyConfig memory config) {
        address[] memory _destinations = new address[](1);
        _destinations[0] = address(_poolToken);

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
