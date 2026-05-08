// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";

import { BTCReserveRouter } from "../../src/adapters/BTCReserveRouter.sol";
import { TigrisBTCStablePoolHandler } from "../../src/adapters/TigrisBTCStablePoolHandler.sol";
import { BTCReservePolicy } from "../../src/core/BTCReservePolicy.sol";
import { TreasuryAccount } from "../../src/core/TreasuryAccount.sol";
import { TreasuryAccountFactory } from "../../src/core/TreasuryAccountFactory.sol";
import { TreasuryPolicyEngine } from "../../src/core/TreasuryPolicyEngine.sol";
import { IBTCReserveHandler } from "../../src/interfaces/IBTCReserveHandler.sol";
import { ITreasuryPolicyEngine } from "../../src/interfaces/ITreasuryPolicyEngine.sol";
import { MockMUSDToken } from "../helpers/MockMUSDToken.sol";
import { MockTigrisBasicRouter } from "../helpers/MockTigrisBasicRouter.sol";
import { MockTigrisLPToken } from "../helpers/MockTigrisLPToken.sol";

contract TigrisBTCStablePoolHandlerTest is Test {
    address internal constant _TREASURY_ADMIN = address(0xA11CE);
    address internal constant _OPERATOR = address(0xB0B);
    address internal constant _APPROVER = address(0xCAFE);
    address internal constant _POOL_FACTORY = address(0xFACADE);
    address internal constant _MEZO_REWARD = address(0x7B7c000000000000000000000000000000000001);

    MockMUSDToken internal _musd;
    MockMUSDToken internal _btc;
    MockMUSDToken internal _mcbtc;
    MockTigrisLPToken internal _poolToken;
    MockTigrisBasicRouter internal _tigrisRouter;
    TreasuryPolicyEngine internal _policyEngine;
    TreasuryAccountFactory internal _factory;
    TreasuryAccount internal _treasuryAccount;
    BTCReservePolicy internal _btcReservePolicy;
    BTCReserveRouter internal _btcReserveRouter;
    TigrisBTCStablePoolHandler internal _handler;

    function setUp() public {
        _musd = new MockMUSDToken();
        _btc = new MockMUSDToken();
        _mcbtc = new MockMUSDToken();
        _poolToken = new MockTigrisLPToken();
        _tigrisRouter = new MockTigrisBasicRouter(_mcbtc, _btc, _poolToken);

        _policyEngine = new TreasuryPolicyEngine();
        _factory = new TreasuryAccountFactory(IERC20(address(_musd)), _policyEngine);
        _factory.setTreasuryAdminApproval(_TREASURY_ADMIN, true);
        _btcReservePolicy = new BTCReservePolicy(_policyEngine);
        _btcReserveRouter = new BTCReserveRouter(_TREASURY_ADMIN);
        _handler = new TigrisBTCStablePoolHandler(
            address(_btcReserveRouter),
            _btcReservePolicy,
            _tigrisRouter,
            address(_poolToken),
            _POOL_FACTORY,
            true,
            address(_btc),
            address(_mcbtc),
            _MEZO_REWARD,
            1 hours,
            100
        );

        vm.deal(_TREASURY_ADMIN, 50 ether);
        vm.deal(_OPERATOR, 50 ether);
        vm.deal(_APPROVER, 50 ether);

        _treasuryAccount = TreasuryAccount(payable(_factory.deployTreasuryAccount(_TREASURY_ADMIN, _defaultConfig())));

        vm.startPrank(_TREASURY_ADMIN);
        _treasuryAccount.setBTCReserveRouter(address(_btcReserveRouter));
        _btcReserveRouter.setHandler(address(_poolToken), _handler);
        _btcReservePolicy.configureBTCReservePolicy(address(_treasuryAccount), _defaultBTCPolicy());
        _btcReservePolicy.updateBTCReserveBuckets(address(_treasuryAccount), _defaultBuckets());
        _btcReservePolicy.configureBTCSleeve(address(_treasuryAccount), address(_poolToken), _defaultSleeve());
        _treasuryAccount.fundIdleBTC{ value: 2 ether }();
        vm.stopPrank();

        _btc.mint(address(_treasuryAccount), 2 ether);
    }

    function test_Deposit_OwnerRoutesIdleBTCIntoMcbBTCBTCPool() public {
        vm.prank(_TREASURY_ADMIN);
        IBTCReserveHandler.BTCDepositResult memory _result =
            _btcReserveRouter.deposit(address(_treasuryAccount), address(_poolToken), _defaultDepositRequest());

        assertEq(_result.pairedReceived, 0.4 ether);
        assertEq(_result.btcUsed, 1 ether);
        assertEq(_result.pairedUsed, 0.4 ether);
        assertEq(_result.liquidityMinted, 1 ether);
        assertEq(_result.unusedBTC, 0);
        assertEq(_treasuryAccount.idleBTC(), 1 ether);
        assertEq(_treasuryAccount.btcSleevePrincipalAllocations(address(_poolToken)), 1 ether);
        assertEq(_poolToken.balanceOf(address(_treasuryAccount)), 1 ether);
        assertEq(_btc.balanceOf(address(_treasuryAccount)), 1 ether);
        assertEq(_mcbtc.balanceOf(address(_treasuryAccount)), 0);
        assertTrue(_tigrisRouter.lastSwapRouteStable());
        assertEq(_tigrisRouter.lastSwapRouteFactory(), _POOL_FACTORY);
        assertTrue(_tigrisRouter.lastAddStable());
    }

    function test_Deposit_RevertsWhenActorIsNotTreasuryOwner() public {
        vm.expectRevert(abi.encodeWithSelector(TreasuryAccount.UnauthorizedCaller.selector, _OPERATOR));

        vm.prank(_OPERATOR);
        _btcReserveRouter.deposit(address(_treasuryAccount), address(_poolToken), _defaultDepositRequest());
    }

    function test_Deposit_RevertsWhenPolicyBlocksPriceImpact() public {
        BTCReservePolicy.BTCSleeveConfig memory _sleeve = _defaultSleeve();
        _sleeve.swapPriceImpactBps = 600;

        vm.prank(_TREASURY_ADMIN);
        _btcReservePolicy.configureBTCSleeve(address(_treasuryAccount), address(_poolToken), _sleeve);

        vm.expectRevert(
            abi.encodeWithSelector(
                TigrisBTCStablePoolHandler.PolicyBlocked.selector,
                BTCReservePolicy.BTCAllocationDecisionCode.SwapPriceImpactExceeded
            )
        );

        vm.prank(_TREASURY_ADMIN);
        _btcReserveRouter.deposit(address(_treasuryAccount), address(_poolToken), _defaultDepositRequest());
    }

    function test_Deposit_RevertsWhenTreasuryLacksERC20BTCBalance() public {
        vm.prank(address(_treasuryAccount));
        _btc.burn(2 ether);

        vm.expectRevert(
            abi.encodeWithSelector(TigrisBTCStablePoolHandler.InsufficientTreasuryBTCBalance.selector, 1 ether, 0)
        );

        vm.prank(_TREASURY_ADMIN);
        _btcReserveRouter.deposit(address(_treasuryAccount), address(_poolToken), _defaultDepositRequest());
    }

    function test_Deposit_RevertsWhenMinOutsAreMissing() public {
        IBTCReserveHandler.BTCDepositRequest memory _request = _defaultDepositRequest();
        _request.minPairedOut = 0;

        vm.expectRevert(TigrisBTCStablePoolHandler.MinOutRequired.selector);

        vm.prank(_TREASURY_ADMIN);
        _btcReserveRouter.deposit(address(_treasuryAccount), address(_poolToken), _request);
    }

    function test_Deposit_RevertsWhenMinLiquidityIsNotMet() public {
        IBTCReserveHandler.BTCDepositRequest memory _request = _defaultDepositRequest();
        _request.minLiquidity = 2 ether;

        vm.expectRevert(
            abi.encodeWithSelector(TigrisBTCStablePoolHandler.InsufficientLiquidityMinted.selector, 1 ether, 2 ether)
        );

        vm.prank(_TREASURY_ADMIN);
        _btcReserveRouter.deposit(address(_treasuryAccount), address(_poolToken), _request);
    }

    function test_Deposit_ReturnsUnusedBTCToIdleAccounting() public {
        _tigrisRouter.setAddLiquidityUsageBps(5000);
        IBTCReserveHandler.BTCDepositRequest memory _request = _defaultDepositRequest();
        _request.minPairedUsed = 0.19 ether;
        _request.minBTCUsed = 0.29 ether;
        _request.minLiquidity = 0.5 ether;

        vm.prank(_TREASURY_ADMIN);
        IBTCReserveHandler.BTCDepositResult memory _result =
            _btcReserveRouter.deposit(address(_treasuryAccount), address(_poolToken), _request);

        assertEq(_result.unusedBTC, 0.3 ether);
        assertEq(_result.unusedPaired, 0.2 ether);
        assertEq(_treasuryAccount.idleBTC(), 1.3 ether);
        assertEq(_treasuryAccount.btcSleevePrincipalAllocations(address(_poolToken)), 0.7 ether);
        assertEq(_mcbtc.balanceOf(address(_treasuryAccount)), 0.2 ether);
    }

    function test_Withdraw_OwnerUnwindsLPAndRestoresIdleBTC() public {
        vm.prank(_TREASURY_ADMIN);
        _btcReserveRouter.deposit(address(_treasuryAccount), address(_poolToken), _defaultDepositRequest());

        vm.prank(_TREASURY_ADMIN);
        IBTCReserveHandler.BTCWithdrawResult memory _result =
            _btcReserveRouter.withdraw(address(_treasuryAccount), address(_poolToken), _defaultWithdrawRequest());

        assertEq(_result.pairedReceived, 0.5 ether);
        assertEq(_result.btcReceived, 0.5 ether);
        assertEq(_result.btcFromPairedSwap, 0.5 ether);
        assertEq(_treasuryAccount.idleBTC(), 2 ether);
        assertEq(_treasuryAccount.btcSleevePrincipalAllocations(address(_poolToken)), 0);
        assertEq(_poolToken.balanceOf(address(_treasuryAccount)), 0);
        assertEq(_btc.balanceOf(address(_treasuryAccount)), 2 ether);
        assertEq(_mcbtc.balanceOf(address(_treasuryAccount)), 0);
    }

    function test_Withdraw_RevertsWhenActorIsNotTreasuryOwner() public {
        vm.prank(_TREASURY_ADMIN);
        _btcReserveRouter.deposit(address(_treasuryAccount), address(_poolToken), _defaultDepositRequest());

        vm.expectRevert(abi.encodeWithSelector(TreasuryAccount.UnauthorizedCaller.selector, _OPERATOR));

        vm.prank(_OPERATOR);
        _btcReserveRouter.withdraw(address(_treasuryAccount), address(_poolToken), _defaultWithdrawRequest());
    }

    function _defaultConfig() internal pure returns (ITreasuryPolicyEngine.AccountPolicyConfig memory config) {
        address[] memory _destinations = new address[](0);
        uint256[] memory _caps = new uint256[](0);

        config = ITreasuryPolicyEngine.AccountPolicyConfig({
            operator: _OPERATOR,
            approver: _APPROVER,
            liquidityBuffer: 0,
            approvalThreshold: type(uint256).max,
            warningCollateralRatioBps: 18_000,
            criticalCollateralRatioBps: 15_000,
            automationEnabled: true,
            startPaused: false,
            approvedDestinations: _destinations,
            destinationCaps: _caps
        });
    }

    function _defaultBTCPolicy() internal pure returns (BTCReservePolicy.BTCReservePolicyConfig memory config) {
        config = BTCReservePolicy.BTCReservePolicyConfig({
            minIdleBTCReserve: 0.5 ether,
            emergencyBTCReserve: 0.25 ether,
            maxYieldBTCBps: 3000,
            maxPerSleeveBTCBps: 2000,
            maxDirectionalBTCBps: 500,
            maxBTCAssetDepegBps: 100,
            maxSwapPriceImpactBps: 500,
            maxSlippageBps: 100,
            collateralWarningCRBps: 0,
            btcYieldPaused: false,
            initialized: false
        });
    }

    function _defaultBuckets() internal pure returns (BTCReservePolicy.BTCReserveBuckets memory buckets) {
        buckets = BTCReservePolicy.BTCReserveBuckets({
            idleBTCReserve: 2 ether,
            collateralBTC: 10 ether,
            emergencyBTCReserve: 0.25 ether,
            yieldActiveBTC: 0,
            pendingWithdrawBTC: 0
        });
    }

    function _defaultSleeve() internal pure returns (BTCReservePolicy.BTCSleeveConfig memory config) {
        config = BTCReservePolicy.BTCSleeveConfig({
            riskClass: BTCReservePolicy.BTCSleeveRiskClass.BTC_CORRELATED,
            enabled: true,
            sleeveCapBps: 2000,
            assetDepegBps: 0,
            withdrawalDelaySeconds: 0,
            swapPriceImpactBps: 100,
            slippageBps: 100,
            approvalLevel: BTCReservePolicy.BTCApprovalLevel.MULTISIG
        });
    }

    function _defaultDepositRequest() internal pure returns (IBTCReserveHandler.BTCDepositRequest memory request) {
        request = IBTCReserveHandler.BTCDepositRequest({
            btcAmount: 1 ether,
            btcToSwap: 0.4 ether,
            minPairedOut: 0.39 ether,
            minBTCUsed: 0.59 ether,
            minPairedUsed: 0.39 ether,
            minLiquidity: 0.99 ether
        });
    }

    function _defaultWithdrawRequest() internal pure returns (IBTCReserveHandler.BTCWithdrawRequest memory request) {
        request = IBTCReserveHandler.BTCWithdrawRequest({
            liquidity: 1 ether,
            principalReductionBTC: 1 ether,
            minPairedOut: 0.49 ether,
            minBTCOut: 0.49 ether,
            swapPairedToBTC: true,
            minBTCFromPaired: 0.49 ether
        });
    }
}
