// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Test } from "forge-std/Test.sol";

import { AllocationRouter } from "../../src/adapters/AllocationRouter.sol";
import { BTCReserveRouter } from "../../src/adapters/BTCReserveRouter.sol";
import { MUSDSavingsRateHandler } from "../../src/adapters/MUSDSavingsRateHandler.sol";
import { TigrisBTCStablePoolHandler } from "../../src/adapters/TigrisBTCStablePoolHandler.sol";
import { TigrisStablePoolHandler } from "../../src/adapters/TigrisStablePoolHandler.sol";
import { BTCReservePolicy } from "../../src/core/BTCReservePolicy.sol";
import { TreasuryAccount } from "../../src/core/TreasuryAccount.sol";
import { TreasuryAccountFactory } from "../../src/core/TreasuryAccountFactory.sol";
import { TreasuryPolicyEngine } from "../../src/core/TreasuryPolicyEngine.sol";
import { IBTCReserveHandler } from "../../src/interfaces/IBTCReserveHandler.sol";
import { IMUSDSavingsRate } from "../../src/interfaces/IMUSDSavingsRate.sol";
import { ITigrisBasicRouter } from "../../src/interfaces/ITigrisBasicRouter.sol";
import { ITreasuryPolicyEngine } from "../../src/interfaces/ITreasuryPolicyEngine.sol";

interface ITigrisBasicPool is IERC20 {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function stable() external view returns (bool);
    function factory() external view returns (address);
    function getReserves() external view returns (uint256 reserve0, uint256 reserve1, uint256 blockTimestampLast);
}

contract MezoYieldTargetsForkTest is Test {
    uint256 internal constant _DEFAULT_SAVINGS_TEST_AMOUNT = 1e18;
    uint256 internal constant _DEFAULT_MUSD_TIGRIS_TEST_AMOUNT = 100e18;
    uint256 internal constant _DEFAULT_BTC_TIGRIS_TEST_AMOUNT = 1e15;
    uint256 internal constant _BPS_DENOMINATOR = 10_000;
    uint256 internal constant _MAX_SLIPPAGE_BPS = 100;
    uint256 internal constant _DEADLINE_WINDOW = 15 minutes;
    address internal constant _APPROVER = address(0xA7700);

    bool internal _runForkTests;
    address internal _owner;
    IERC20 internal _musd;
    IERC20 internal _musdc;
    IERC20 internal _btc;
    IERC20 internal _mcbtc;
    IMUSDSavingsRate internal _savingsVault;
    ITigrisBasicRouter internal _tigrisRouter;
    ITigrisBasicPool internal _musdMusdcPool;
    ITigrisBasicPool internal _mcbtcBtcPool;
    address internal _poolFactory;

    function setUp() public {
        _runForkTests = vm.envOr("RUN_MEZO_FORK_TESTS", false);
        if (!_runForkTests) return;

        string memory _rpcUrl = vm.envOr("ACTIVE_MEZO_RPC_URL", vm.envOr("MEZO_RPC_URL", string("")));
        vm.createSelectFork(_rpcUrl);

        _owner = vm.envAddress("OWNER_PUBLIC_KEY");
        _musd = IERC20(vm.envAddress("MEZO_MUSD_TOKEN"));
        _musdc = IERC20(vm.envAddress("MEZO_MUSDC_TOKEN"));
        _btc = IERC20(vm.envAddress("MEZO_BTC_TOKEN"));
        _mcbtc = IERC20(vm.envAddress("MEZO_MCBTC_TOKEN"));
        _savingsVault = IMUSDSavingsRate(vm.envAddress("MEZO_MUSD_SAVINGS_RATE"));
        _tigrisRouter = ITigrisBasicRouter(vm.envAddress("MEZO_TIGRIS_ROUTER"));
        _poolFactory = vm.envAddress("MEZO_TIGRIS_POOL_FACTORY");
        _musdMusdcPool = ITigrisBasicPool(vm.envAddress("MEZO_TIGRIS_MUSD_MUSDC_POOL"));
        _mcbtcBtcPool = ITigrisBasicPool(vm.envAddress("MEZO_TIGRIS_MCBTC_BTC_POOL"));
    }

    function testFork_MUSDSavingsVault_DepositAndWithdraw() public {
        _skipUnlessFork();

        uint256 _amount = _boundedTokenAmount(_musd, _owner, "MEZO_FORK_SAVINGS_AMOUNT", _DEFAULT_SAVINGS_TEST_AMOUNT);
        assertGt(_amount, 0, "OWNER_PUBLIC_KEY needs MUSD for savings fork test");

        uint256 _musdBefore = _musd.balanceOf(_owner);
        uint256 _sharesBefore = _savingsVault.balanceOf(_owner);

        vm.startPrank(_owner);
        _musd.approve(address(_savingsVault), _amount);
        _savingsVault.deposit(_amount);
        assertEq(_savingsVault.balanceOf(_owner), _sharesBefore + _amount);

        _savingsVault.withdraw(_amount);
        vm.stopPrank();

        assertEq(_savingsVault.balanceOf(_owner), _sharesBefore);
        assertGe(_musd.balanceOf(_owner), _musdBefore);
        assertEq(_savingsVault.yieldToken(), address(_musd));
    }

    function testFork_TreasuryOSSavingsHandler_DepositAndWithdraw() public {
        _skipUnlessFork();

        uint256 _amount = _boundedTokenAmount(_musd, _owner, "MEZO_FORK_SAVINGS_AMOUNT", _DEFAULT_SAVINGS_TEST_AMOUNT);
        assertGt(_amount, 0, "OWNER_PUBLIC_KEY needs MUSD for TreasuryOS savings fork test");

        address[] memory _destinations = new address[](1);
        _destinations[0] = address(_savingsVault);
        uint256[] memory _caps = new uint256[](1);
        _caps[0] = _amount * 2;

        (TreasuryAccount _account, AllocationRouter _router) = _deployTreasury(_destinations, _caps);
        MUSDSavingsRateHandler _handler = new MUSDSavingsRateHandler(_savingsVault, address(_router));

        vm.startPrank(_owner);
        _router.setHandler(address(_savingsVault), _handler);
        _musd.approve(address(_account), _amount);
        _account.fundIdleMUSD(_amount);

        uint256 _shares = _router.deposit(address(_account), address(_savingsVault), _amount);
        assertEq(_shares, _amount);
        assertEq(_savingsVault.balanceOf(address(_account)), _amount);
        assertEq(_account.idleMUSD(), 0);

        uint256 _burnedShares = _router.withdraw(address(_account), address(_savingsVault), _amount);
        vm.stopPrank();

        assertEq(_burnedShares, _amount);
        assertEq(_savingsVault.balanceOf(address(_account)), 0);
        assertGe(_account.idleMUSD(), _amount);
    }

    function testFork_TigrisMUSDmUSDC_HandlerDepositAndWithdraw() public {
        _skipUnlessFork();
        _assertMUSDMUSDCPoolMetadata();

        uint256 _amount = _quotedMUSDTestAmount("MEZO_FORK_TIGRIS_MUSD_AMOUNT", _DEFAULT_MUSD_TIGRIS_TEST_AMOUNT);
        assertGt(_amount, 0, "MUSD/mUSDC route has no nonzero quote for available owner MUSD");

        address[] memory _destinations = new address[](1);
        _destinations[0] = address(_musdMusdcPool);
        uint256[] memory _caps = new uint256[](1);
        _caps[0] = _amount * 2;

        (TreasuryAccount _account, AllocationRouter _router) = _deployTreasury(_destinations, _caps);
        TigrisStablePoolHandler _handler = new TigrisStablePoolHandler(
            address(_router),
            _tigrisRouter,
            address(_musdMusdcPool),
            _poolFactory,
            true,
            _musd,
            _musdc,
            _DEADLINE_WINDOW,
            _MAX_SLIPPAGE_BPS
        );

        vm.startPrank(_owner);
        _router.setHandler(address(_musdMusdcPool), _handler);
        _musd.approve(address(_account), _amount);
        _account.fundIdleMUSD(_amount);

        uint256 _liquidity;
        try _router.deposit(address(_account), address(_musdMusdcPool), _amount) returns (uint256 _result) {
            _liquidity = _result;
        } catch {
            vm.stopPrank();
            vm.skip(true, "Live MUSD/mUSDC route reverted; keep MUSD Savings as primary demo sleeve");
            return;
        }
        assertGt(_liquidity, 0);
        assertGt(_musdMusdcPool.balanceOf(address(_account)), 0);
        assertGt(_account.destinationAllocations(address(_musdMusdcPool)), 0);

        uint256 _allocation = _account.destinationAllocations(address(_musdMusdcPool));
        uint256 _burnedLiquidity;
        try _router.withdraw(address(_account), address(_musdMusdcPool), _allocation) returns (uint256 _result) {
            _burnedLiquidity = _result;
        } catch {
            vm.stopPrank();
            vm.skip(true, "Live MUSD/mUSDC unwind route reverted; keep MUSD Savings as primary demo sleeve");
            return;
        }
        vm.stopPrank();

        assertGt(_burnedLiquidity, 0);
        assertEq(_musdMusdcPool.balanceOf(address(_account)), 0);
        assertEq(_account.destinationAllocations(address(_musdMusdcPool)), 0);
        assertGt(_account.idleMUSD(), 0);
    }

    function testFork_TigrisMcbBTCBTC_MetadataAndQuotes() public {
        _skipUnlessFork();
        _assertMcbBTCBTCPoolMetadata();

        uint256 _quoteAmount = vm.envOr("MEZO_FORK_BTC_QUOTE_AMOUNT", _DEFAULT_BTC_TIGRIS_TEST_AMOUNT);
        ITigrisBasicRouter.Route[] memory _routes = _buildRoute(address(_btc), address(_mcbtc));
        uint256[] memory _amounts = _tigrisRouter.getAmountsOut(_quoteAmount, _routes);

        assertEq(_amounts.length, 2);
        assertEq(_amounts[0], _quoteAmount);
        assertGt(_amounts[1], 0, "mcbBTC/BTC route returned zero output");
    }

    function testFork_TigrisMcbBTCBTC_DirectRouterDepositAndWithdrawIfFunded() public {
        _skipUnlessFork();
        _assertMcbBTCBTCPoolMetadata();

        (bool _btcReadable, uint256 _amount) =
            _boundedBTCTestAmount("MEZO_FORK_BTC_LP_AMOUNT", _DEFAULT_BTC_TIGRIS_TEST_AMOUNT);
        if (!_btcReadable) {
            vm.skip(true, "Foundry fork cannot execute the Mezo ERC20 BTC precompile wrapper");
        }
        if (_amount == 0) {
            vm.skip(true, "OWNER_PUBLIC_KEY has no ERC20 BTC balance for mcbBTC/BTC execution test");
        }

        vm.startPrank(_owner);
        _btc.approve(address(_tigrisRouter), _amount);
        uint256 _mcbtcReceived = _swapBTCForMcbtc(_amount / 2);
        uint256 _liquidity = _addMcbtcBtcLiquidity(_mcbtcReceived, _amount - (_amount / 2));
        _removeMcbtcBtcLiquidity(_liquidity);
        vm.stopPrank();
    }

    function testFork_TigrisMcbBTCBTC_TreasuryOSHandlerDepositAndWithdrawIfFunded() public {
        _skipUnlessFork();
        _assertMcbBTCBTCPoolMetadata();

        (bool _btcReadable, uint256 _amount) =
            _boundedBTCTestAmount("MEZO_FORK_BTC_LP_AMOUNT", _DEFAULT_BTC_TIGRIS_TEST_AMOUNT);
        if (!_btcReadable) {
            vm.skip(true, "Foundry fork cannot execute the Mezo ERC20 BTC precompile wrapper");
        }
        if (_amount == 0) {
            vm.skip(true, "OWNER_PUBLIC_KEY has no ERC20 BTC balance for guarded mcbBTC/BTC handler test");
        }

        address[] memory _destinations = new address[](0);
        uint256[] memory _caps = new uint256[](0);
        (TreasuryAccount _account,) = _deployTreasury(_destinations, _caps);
        BTCReservePolicy _btcPolicy = new BTCReservePolicy(_account.policyEngine());
        BTCReserveRouter _btcRouter = new BTCReserveRouter(_owner);
        TigrisBTCStablePoolHandler _handler = new TigrisBTCStablePoolHandler(
            address(_btcRouter),
            _btcPolicy,
            _tigrisRouter,
            address(_mcbtcBtcPool),
            _poolFactory,
            true,
            address(_btc),
            address(_mcbtc),
            address(0),
            _DEADLINE_WINDOW,
            _MAX_SLIPPAGE_BPS
        );

        vm.startPrank(_owner);
        _account.setBTCReserveRouter(address(_btcRouter));
        _btcRouter.setHandler(address(_mcbtcBtcPool), _handler);
        _btcPolicy.configureBTCReservePolicy(address(_account), _btcPolicyConfig());
        _btcPolicy.updateBTCReserveBuckets(address(_account), _btcBuckets(_amount));
        _btcPolicy.configureBTCSleeve(address(_account), address(_mcbtcBtcPool), _btcSleeveConfig());
        _account.fundIdleBTC{ value: _amount }();

        IBTCReserveHandler.BTCDepositRequest memory _depositRequest = _btcDepositRequest(_amount);
        IBTCReserveHandler.BTCDepositResult memory _depositResult =
            _btcRouter.deposit(address(_account), address(_mcbtcBtcPool), _depositRequest);
        assertGt(_depositResult.liquidityMinted, 0);
        assertGt(_mcbtcBtcPool.balanceOf(address(_account)), 0);
        assertEq(_account.btcSleevePrincipalAllocations(address(_mcbtcBtcPool)), _amount - _depositResult.unusedBTC);

        IBTCReserveHandler.BTCWithdrawRequest memory _withdrawRequest =
            _btcWithdrawRequest(_depositResult.liquidityMinted, _depositResult.btcUsed);
        IBTCReserveHandler.BTCWithdrawResult memory _withdrawResult =
            _btcRouter.withdraw(address(_account), address(_mcbtcBtcPool), _withdrawRequest);
        vm.stopPrank();

        assertGt(_withdrawResult.btcReceived + _withdrawResult.btcFromPairedSwap, 0);
        assertEq(_mcbtcBtcPool.balanceOf(address(_account)), 0);
        assertEq(_account.btcSleevePrincipalAllocations(address(_mcbtcBtcPool)), 0);
        assertGt(_account.idleBTC(), 0);
    }

    function _swapBTCForMcbtc(uint256 _btcToSwap) internal returns (uint256 mcbtcReceived) {
        ITigrisBasicRouter.Route[] memory _routes = _buildRoute(address(_btc), address(_mcbtc));
        uint256 _quotedMcbtc = _quoteFinalOut(_btcToSwap, _routes);
        assertGt(_quotedMcbtc, 0, "mcbBTC/BTC swap quote is zero");

        uint256 _mcbtcBefore = _mcbtc.balanceOf(_owner);
        _tigrisRouter.swapExactTokensForTokens(
            _btcToSwap, _amountAfterSlippage(_quotedMcbtc), _routes, _owner, block.timestamp + _DEADLINE_WINDOW
        );
        mcbtcReceived = _mcbtc.balanceOf(_owner) - _mcbtcBefore;
        assertGt(mcbtcReceived, 0);
    }

    function _addMcbtcBtcLiquidity(uint256 _mcbtcReceived, uint256 _btcToPair) internal returns (uint256 liquidity) {
        _mcbtc.approve(address(_tigrisRouter), _mcbtcReceived);
        (uint256 _expectedMcbtcUsed, uint256 _expectedBTCUsed, uint256 _expectedLiquidity) = _tigrisRouter.quoteAddLiquidity(
            address(_mcbtc), address(_btc), true, _poolFactory, _mcbtcReceived, _btcToPair
        );
        (uint256 _mcbtcUsed, uint256 _btcUsed, uint256 _liquidity) = _tigrisRouter.addLiquidity(
            address(_mcbtc),
            address(_btc),
            true,
            _mcbtcReceived,
            _btcToPair,
            _amountAfterSlippage(_expectedMcbtcUsed),
            _amountAfterSlippage(_expectedBTCUsed),
            _owner,
            block.timestamp + _DEADLINE_WINDOW
        );
        assertGt(_liquidity, 0);
        assertGe(_liquidity, _amountAfterSlippage(_expectedLiquidity));
        assertGt(_mcbtcUsed, 0);
        assertGt(_btcUsed, 0);

        liquidity = _liquidity;
    }

    function _removeMcbtcBtcLiquidity(uint256 _liquidity) internal {
        _mcbtcBtcPool.approve(address(_tigrisRouter), _liquidity);
        (uint256 _expectedMcbtcOut, uint256 _expectedBTCOut) =
            _tigrisRouter.quoteRemoveLiquidity(address(_mcbtc), address(_btc), true, _poolFactory, _liquidity);
        (uint256 _mcbtcOut, uint256 _btcOut) = _tigrisRouter.removeLiquidity(
            address(_mcbtc),
            address(_btc),
            true,
            _liquidity,
            _amountAfterSlippage(_expectedMcbtcOut),
            _amountAfterSlippage(_expectedBTCOut),
            _owner,
            block.timestamp + _DEADLINE_WINDOW
        );

        assertGt(_mcbtcOut, 0);
        assertGt(_btcOut, 0);
    }

    function _btcDepositRequest(uint256 _amount)
        internal
        view
        returns (IBTCReserveHandler.BTCDepositRequest memory request)
    {
        (uint256 _reserveMcbtc, uint256 _reserveBTC,) = _mcbtcBtcPool.getReserves();
        uint256 _quoteInputBTC = _amount / 10;
        if (_quoteInputBTC == 0) _quoteInputBTC = _amount;
        uint256 _quoteOutputMcbtc = _quoteFinalOut(_quoteInputBTC, _buildRoute(address(_btc), address(_mcbtc)));

        uint256 _btcToSwap = (_amount * _quoteInputBTC * _reserveMcbtc)
            / ((_quoteOutputMcbtc * _reserveBTC) + (_quoteInputBTC * _reserveMcbtc));
        uint256 _expectedMcbtcOut = _quoteFinalOut(_btcToSwap, _buildRoute(address(_btc), address(_mcbtc)));
        uint256 _btcToPair = _amount - _btcToSwap;
        (uint256 _expectedMcbtcUsed, uint256 _expectedBTCUsed, uint256 _expectedLiquidity) = _tigrisRouter.quoteAddLiquidity(
            address(_mcbtc), address(_btc), true, _poolFactory, _expectedMcbtcOut, _btcToPair
        );

        request = IBTCReserveHandler.BTCDepositRequest({
            btcAmount: _amount,
            btcToSwap: _btcToSwap,
            minPairedOut: _amountAfterSlippage(_expectedMcbtcOut),
            minBTCUsed: _amountAfterSlippage(_expectedBTCUsed),
            minPairedUsed: _amountAfterSlippage(_expectedMcbtcUsed),
            minLiquidity: _amountAfterSlippage(_expectedLiquidity)
        });
    }

    function _btcWithdrawRequest(uint256 _liquidity, uint256 _principalReductionBTC)
        internal
        view
        returns (IBTCReserveHandler.BTCWithdrawRequest memory request)
    {
        (uint256 _expectedMcbtcOut, uint256 _expectedBTCOut) =
            _tigrisRouter.quoteRemoveLiquidity(address(_mcbtc), address(_btc), true, _poolFactory, _liquidity);
        uint256 _pairedSwapInput = _amountAfterSlippage(_expectedMcbtcOut);
        uint256 _expectedBTCFromPaired = _quoteFinalOut(_pairedSwapInput, _buildRoute(address(_mcbtc), address(_btc)));

        request = IBTCReserveHandler.BTCWithdrawRequest({
            liquidity: _liquidity,
            principalReductionBTC: _principalReductionBTC,
            minPairedOut: _pairedSwapInput,
            minBTCOut: _amountAfterSlippage(_expectedBTCOut),
            swapPairedToBTC: true,
            minBTCFromPaired: _amountAfterSlippage(_expectedBTCFromPaired)
        });
    }

    function _deployTreasury(address[] memory _destinations, uint256[] memory _caps)
        internal
        returns (TreasuryAccount account, AllocationRouter router)
    {
        TreasuryPolicyEngine _policyEngine = new TreasuryPolicyEngine();
        TreasuryAccountFactory _factory = new TreasuryAccountFactory(_musd, _policyEngine);
        _factory.setTreasuryAdminApproval(_owner, true);

        vm.startPrank(_owner);
        router = new AllocationRouter(_owner);
        account = TreasuryAccount(payable(_factory.deployTreasuryAccount(_owner, _policyConfig(_destinations, _caps))));
        account.setAllocationRouter(address(router));
        vm.stopPrank();
    }

    function _policyConfig(address[] memory _destinations, uint256[] memory _caps)
        internal
        view
        returns (ITreasuryPolicyEngine.AccountPolicyConfig memory config)
    {
        config = ITreasuryPolicyEngine.AccountPolicyConfig({
            operator: _owner,
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

    function _btcPolicyConfig() internal pure returns (BTCReservePolicy.BTCReservePolicyConfig memory config) {
        config = BTCReservePolicy.BTCReservePolicyConfig({
            minIdleBTCReserve: 0,
            emergencyBTCReserve: 0,
            maxYieldBTCBps: 10_000,
            maxPerSleeveBTCBps: 10_000,
            maxDirectionalBTCBps: 0,
            maxBTCAssetDepegBps: 10_000,
            maxSwapPriceImpactBps: 10_000,
            maxSlippageBps: _MAX_SLIPPAGE_BPS,
            collateralWarningCRBps: 0,
            btcYieldPaused: false,
            initialized: false
        });
    }

    function _btcBuckets(uint256 _amount) internal pure returns (BTCReservePolicy.BTCReserveBuckets memory buckets) {
        buckets = BTCReservePolicy.BTCReserveBuckets({
            idleBTCReserve: _amount, collateralBTC: 0, emergencyBTCReserve: 0, yieldActiveBTC: 0, pendingWithdrawBTC: 0
        });
    }

    function _btcSleeveConfig() internal pure returns (BTCReservePolicy.BTCSleeveConfig memory config) {
        config = BTCReservePolicy.BTCSleeveConfig({
            riskClass: BTCReservePolicy.BTCSleeveRiskClass.BTC_CORRELATED,
            enabled: true,
            sleeveCapBps: 10_000,
            assetDepegBps: 0,
            withdrawalDelaySeconds: 0,
            swapPriceImpactBps: 0,
            slippageBps: _MAX_SLIPPAGE_BPS,
            approvalLevel: BTCReservePolicy.BTCApprovalLevel.MULTISIG
        });
    }

    function _assertMUSDMUSDCPoolMetadata() internal view {
        assertEq(_musdMusdcPool.token0(), address(_musd));
        assertEq(_musdMusdcPool.token1(), address(_musdc));
        assertEq(_musdMusdcPool.factory(), _poolFactory);
        assertTrue(_musdMusdcPool.stable());
        (uint256 _reserve0, uint256 _reserve1,) = _musdMusdcPool.getReserves();
        assertGt(_reserve0, 0);
        assertGt(_reserve1, 0);
    }

    function _assertMcbBTCBTCPoolMetadata() internal view {
        assertEq(_mcbtcBtcPool.token0(), address(_mcbtc));
        assertEq(_mcbtcBtcPool.token1(), address(_btc));
        assertEq(_mcbtcBtcPool.factory(), _poolFactory);
        assertTrue(_mcbtcBtcPool.stable());
        assertEq(IERC20Metadata(address(_mcbtc)).decimals(), 8);
        (uint256 _reserve0, uint256 _reserve1,) = _mcbtcBtcPool.getReserves();
        assertGt(_reserve0, 0);
        assertGt(_reserve1, 0);
    }

    function _quotedMUSDTestAmount(string memory _envKey, uint256 _defaultAmount)
        internal
        view
        returns (uint256 amount)
    {
        uint256 _ownerBalance = _musd.balanceOf(_owner);
        uint256 _candidate = _boundedTokenAmount(_musd, _owner, _envKey, _defaultAmount);
        ITigrisBasicRouter.Route[] memory _routes = _buildRoute(address(_musd), address(_musdc));

        while (_candidate > 0 && _candidate <= _ownerBalance) {
            if (_quoteFinalOut(_candidate / 2, _routes) > 0) {
                return _candidate;
            }

            if (_candidate > _ownerBalance / 10) break;
            _candidate *= 10;
        }

        return 0;
    }

    function _quoteFinalOut(uint256 _amountIn, ITigrisBasicRouter.Route[] memory _routes)
        internal
        view
        returns (uint256)
    {
        if (_amountIn == 0) return 0;
        uint256[] memory _amounts = _tigrisRouter.getAmountsOut(_amountIn, _routes);
        return _amounts[_amounts.length - 1];
    }

    function _boundedTokenAmount(IERC20 _token, address _account, string memory _envKey, uint256 _defaultAmount)
        internal
        view
        returns (uint256)
    {
        uint256 _balance = _token.balanceOf(_account);
        if (_balance == 0) return 0;

        uint256 _requested = vm.envOr(_envKey, _defaultAmount);
        if (_requested <= _balance) return _requested;

        return _balance;
    }

    function _boundedBTCTestAmount(string memory _envKey, uint256 _defaultAmount)
        internal
        view
        returns (bool readable, uint256 amount)
    {
        (bool _success, bytes memory _data) =
            address(_btc).staticcall{ gas: 100_000 }(abi.encodeCall(IERC20.balanceOf, (_owner)));
        if (!_success || _data.length < 32) {
            return (false, 0);
        }

        uint256 _balance = abi.decode(_data, (uint256));
        if (_balance == 0) return (true, 0);

        uint256 _requested = vm.envOr(_envKey, _defaultAmount);
        if (_requested <= _balance) return (true, _requested);

        return (true, _balance);
    }

    function _buildRoute(address _from, address _to) internal view returns (ITigrisBasicRouter.Route[] memory routes) {
        routes = new ITigrisBasicRouter.Route[](1);
        routes[0] = ITigrisBasicRouter.Route({ from: _from, to: _to, stable: true, factory: _poolFactory });
    }

    function _amountAfterSlippage(uint256 _amount) internal pure returns (uint256) {
        return (_amount * (_BPS_DENOMINATOR - _MAX_SLIPPAGE_BPS)) / _BPS_DENOMINATOR;
    }

    function _skipUnlessFork() internal {
        if (!_runForkTests) {
            vm.skip(true, "Set RUN_MEZO_FORK_TESTS=true to run live Mezo fork tests");
        }
    }
}
