// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BTCReservePolicy } from "../core/BTCReservePolicy.sol";
import { TreasuryAccount } from "../core/TreasuryAccount.sol";
import { IBTCReserveHandler } from "../interfaces/IBTCReserveHandler.sol";
import { IBTCYieldSleeveHandler } from "../interfaces/IBTCYieldSleeveHandler.sol";
import { ITigrisBasicRouter } from "../interfaces/ITigrisBasicRouter.sol";

/// @title TigrisBTCStablePoolHandler
/// @notice Guarded handler for the Tigris mcbBTC/BTC stable pool candidate.
/// @dev BTC principal remains Treasury Account-owned. Entry and exit must be initiated through `BTCReserveRouter`,
///      pass `BTCReservePolicy`, and include explicit min-out/min-liquidity bounds.
contract TigrisBTCStablePoolHandler is IBTCReserveHandler, IBTCYieldSleeveHandler {
    // =============================================================
    // Types
    // =============================================================

    struct LiquidityOutcome {
        uint256 pairedUsed;
        uint256 btcUsed;
        uint256 liquidityMinted;
    }

    // =============================================================
    // Events
    // =============================================================

    event BTCStablePoolDepositRouted(
        address indexed treasuryAccount,
        address indexed actor,
        address indexed destination,
        uint256 btcAmount,
        uint256 btcSwapped,
        uint256 pairedReceived,
        uint256 btcUsed,
        uint256 pairedUsed,
        uint256 liquidityMinted,
        uint256 unusedBTC,
        uint256 unusedPaired
    );
    event BTCStablePoolWithdrawalRouted(
        address indexed treasuryAccount,
        address indexed actor,
        address indexed destination,
        uint256 liquidityBurned,
        uint256 principalReduced,
        uint256 pairedReceived,
        uint256 btcReceived,
        uint256 btcFromPairedSwap
    );

    // =============================================================
    // Errors
    // =============================================================

    error InvalidBTCReserveRouter(address btcReserveRouter);
    error InvalidBTCReservePolicy(address btcReservePolicy);
    error InvalidDestination(address destination);
    error InvalidPoolFactory(address poolFactory);
    error InvalidRouter(address router);
    error InvalidToken(address token);
    error InvalidTreasuryAccount(address treasuryAccount);
    error InvalidAmount(uint256 amount);
    error InvalidDepositSplit(uint256 btcAmount, uint256 btcToSwap);
    error MinOutRequired();
    error PolicyBlocked(BTCReservePolicy.BTCAllocationDecisionCode reason);
    error InsufficientTreasuryBTCBalance(uint256 required, uint256 balance);
    error InsufficientPairedOutput(uint256 amountOut, uint256 minAmountOut);
    error InsufficientLiquidityMinted(uint256 liquidityMinted, uint256 minLiquidity);
    error UnauthorizedCaller(address caller);
    error UnexpectedSwapPathLength(uint256 pathLength);

    // =============================================================
    // Storage
    // =============================================================

    address public immutable btcReserveRouter;
    BTCReservePolicy public immutable btcReservePolicy;
    ITigrisBasicRouter internal immutable tigrisRouter;
    address public immutable override destination;
    address public immutable override principalAsset;
    address public immutable override pairedAsset;
    address public immutable override receiptAsset;
    address public immutable override rewardAsset;
    address public immutable poolFactory;
    bool public immutable poolStable;
    uint256 public immutable deadlineWindow;
    uint256 public immutable maxSlippageBps;

    // =============================================================
    // Constructor
    // =============================================================

    /// @param _btcReserveRouter Router allowed to dispatch BTC sleeve actions to this handler.
    /// @param _btcReservePolicy BTC reserve policy checked before principal movement.
    /// @param _router Tigris router used for swaps and liquidity actions.
    /// @param _destination LP token / pool destination reported to TreasuryOS policy and accounting.
    /// @param _poolFactory Tigris pool factory used for route and liquidity execution.
    /// @param _poolStable Whether the target Tigris pool is stable.
    /// @param _principalAsset ERC20-compatible BTC token, such as Mezo BTCCaller.
    /// @param _pairedAsset BTC-correlated paired token, such as mcbBTC.
    /// @param _rewardAsset Reward token reported for future staking integrations.
    /// @param _deadlineWindow Number of seconds added to `block.timestamp` for router deadlines.
    /// @param _maxSlippageBps Slippage value reported by previews. Execution uses caller-supplied minimums.
    constructor(
        address _btcReserveRouter,
        BTCReservePolicy _btcReservePolicy,
        ITigrisBasicRouter _router,
        address _destination,
        address _poolFactory,
        bool _poolStable,
        address _principalAsset,
        address _pairedAsset,
        address _rewardAsset,
        uint256 _deadlineWindow,
        uint256 _maxSlippageBps
    ) {
        require(_btcReserveRouter != address(0), InvalidBTCReserveRouter(_btcReserveRouter));
        require(address(_btcReservePolicy) != address(0), InvalidBTCReservePolicy(address(_btcReservePolicy)));
        require(address(_router) != address(0), InvalidRouter(address(_router)));
        require(_destination != address(0), InvalidDestination(_destination));
        require(_poolFactory != address(0), InvalidPoolFactory(_poolFactory));
        require(_principalAsset != address(0), InvalidToken(_principalAsset));
        require(_pairedAsset != address(0), InvalidToken(_pairedAsset));

        btcReserveRouter = _btcReserveRouter;
        btcReservePolicy = _btcReservePolicy;
        tigrisRouter = _router;
        destination = _destination;
        principalAsset = _principalAsset;
        pairedAsset = _pairedAsset;
        receiptAsset = _destination;
        rewardAsset = _rewardAsset;
        poolFactory = _poolFactory;
        poolStable = _poolStable;
        deadlineWindow = _deadlineWindow;
        maxSlippageBps = _maxSlippageBps;
    }

    // =============================================================
    // External Functions
    // =============================================================

    /// @inheritdoc IBTCYieldSleeveHandler
    function riskClass() external pure returns (IBTCYieldSleeveHandler.BTCSleeveRiskClass) {
        return IBTCYieldSleeveHandler.BTCSleeveRiskClass.BTC_CORRELATED;
    }

    /// @inheritdoc IBTCYieldSleeveHandler
    function previewExposure(address _treasury) external view returns (BTCExposure memory exposure) {
        (,,,,, uint256 _swapPriceImpactBps, uint256 _slippageBps,) = btcReservePolicy.btcSleeves(_treasury, destination);

        exposure.principalBTC = _btcPrincipal(_treasury);
        exposure.pairedAssetAmount = IERC20(pairedAsset).balanceOf(_treasury);
        exposure.btcEquivalentExposure = exposure.principalBTC;
        exposure.receiptBalance = IERC20(receiptAsset).balanceOf(_treasury);
        exposure.swapPriceImpactBps = _swapPriceImpactBps;
        exposure.slippageBps = _slippageBps;
        exposure.principalMovementSupported = true;
        exposure.stakingSupported = false;
    }

    /// @inheritdoc IBTCYieldSleeveHandler
    function previewDeposit(uint256 _btcAmount) external view returns (BTCDepositPreview memory preview) {
        preview.principalAsset = principalAsset;
        preview.pairedAsset = pairedAsset;
        preview.receiptAsset = receiptAsset;
        preview.rewardAsset = rewardAsset;
        preview.btcAmount = _btcAmount;
        preview.slippageBps = maxSlippageBps;

        if (_btcAmount == 0) {
            return preview;
        }

        uint256 _btcToSwap = _btcAmount / 2;
        uint256 _btcToPair = _btcAmount - _btcToSwap;
        ITigrisBasicRouter.Route[] memory _routes = _buildRoute(principalAsset, pairedAsset);
        uint256 _pairedOut = _quoteSwapOutput(_btcToSwap, _routes);
        (,, uint256 _liquidity) =
            tigrisRouter.quoteAddLiquidity(pairedAsset, principalAsset, poolStable, poolFactory, _pairedOut, _btcToPair);

        preview.pairedAmount = _pairedOut;
        preview.minPairedOut = _amountAfterSlippage(_pairedOut);
        preview.estimatedLiquidity = _liquidity;
        preview.minLiquidity = _amountAfterSlippage(_liquidity);
    }

    /// @inheritdoc IBTCReserveHandler
    function deposit(address _treasuryAccount, address _actor, BTCDepositRequest calldata _request)
        external
        returns (BTCDepositResult memory result)
    {
        require(msg.sender == btcReserveRouter, UnauthorizedCaller(msg.sender));
        require(_treasuryAccount != address(0), InvalidTreasuryAccount(_treasuryAccount));
        require(_request.btcAmount > 0, InvalidAmount(_request.btcAmount));
        require(
            _request.btcToSwap > 0 && _request.btcToSwap < _request.btcAmount,
            InvalidDepositSplit(_request.btcAmount, _request.btcToSwap)
        );
        require(_request.minPairedOut > 0 && _request.minLiquidity > 0, MinOutRequired());

        _requirePolicyAllowed(_treasuryAccount, _request.btcAmount);
        _requireTreasuryBTCBalance(_treasuryAccount, _request.btcAmount);

        TreasuryAccount(payable(_treasuryAccount))
            .allocateIdleBTCFromBTCHandler(_actor, destination, _request.btcAmount);
        TreasuryAccount(payable(_treasuryAccount))
            .forceApproveTokenFromBTCHandler(principalAsset, address(tigrisRouter), _request.btcAmount);

        uint256 _pairedReceived = _swapBTCToPaired(_treasuryAccount, _request.btcToSwap, _request.minPairedOut);
        uint256 _btcToPair = _request.btcAmount - _request.btcToSwap;
        TreasuryAccount(payable(_treasuryAccount))
            .forceApproveTokenFromBTCHandler(pairedAsset, address(tigrisRouter), _pairedReceived);

        LiquidityOutcome memory _liquidity = _addLiquidity(
            _treasuryAccount,
            _pairedReceived,
            _btcToPair,
            _request.minPairedUsed,
            _request.minBTCUsed,
            _request.minLiquidity
        );

        result = BTCDepositResult({
            pairedReceived: _pairedReceived,
            btcUsed: _request.btcToSwap + _liquidity.btcUsed,
            pairedUsed: _liquidity.pairedUsed,
            liquidityMinted: _liquidity.liquidityMinted,
            unusedBTC: _btcToPair - _liquidity.btcUsed,
            unusedPaired: _pairedReceived - _liquidity.pairedUsed
        });

        if (result.unusedBTC > 0) {
            TreasuryAccount(payable(_treasuryAccount))
                .settleBTCWithdrawalFromHandler(_actor, destination, result.unusedBTC, result.unusedBTC);
        }

        emit BTCStablePoolDepositRouted(
            _treasuryAccount,
            _actor,
            destination,
            _request.btcAmount,
            _request.btcToSwap,
            result.pairedReceived,
            result.btcUsed,
            result.pairedUsed,
            result.liquidityMinted,
            result.unusedBTC,
            result.unusedPaired
        );
    }

    /// @inheritdoc IBTCReserveHandler
    function withdraw(address _treasuryAccount, address _actor, BTCWithdrawRequest calldata _request)
        external
        returns (BTCWithdrawResult memory result)
    {
        require(msg.sender == btcReserveRouter, UnauthorizedCaller(msg.sender));
        require(_treasuryAccount != address(0), InvalidTreasuryAccount(_treasuryAccount));
        require(_request.liquidity > 0, InvalidAmount(_request.liquidity));
        require(_request.principalReductionBTC > 0, InvalidAmount(_request.principalReductionBTC));
        require(_request.minPairedOut > 0 || _request.minBTCOut > 0, MinOutRequired());

        TreasuryAccount(payable(_treasuryAccount))
            .forceApproveTokenFromBTCHandler(receiptAsset, address(tigrisRouter), _request.liquidity);

        (uint256 _pairedReceived, uint256 _btcReceived) =
            _removeLiquidity(_treasuryAccount, _request.liquidity, _request.minPairedOut, _request.minBTCOut);

        uint256 _btcFromPaired;
        if (_request.swapPairedToBTC && _pairedReceived > 0) {
            require(_request.minBTCFromPaired > 0, MinOutRequired());
            TreasuryAccount(payable(_treasuryAccount))
                .forceApproveTokenFromBTCHandler(pairedAsset, address(tigrisRouter), _pairedReceived);
            _btcFromPaired = _swapPairedToBTC(_treasuryAccount, _pairedReceived, _request.minBTCFromPaired);
        }

        uint256 _idleBTCIncrease = _btcReceived + _btcFromPaired;
        TreasuryAccount(payable(_treasuryAccount))
            .settleBTCWithdrawalFromHandler(_actor, destination, _request.principalReductionBTC, _idleBTCIncrease);

        result = BTCWithdrawResult({
            pairedReceived: _pairedReceived,
            btcReceived: _btcReceived,
            btcFromPairedSwap: _btcFromPaired,
            principalReductionBTC: _request.principalReductionBTC
        });

        emit BTCStablePoolWithdrawalRouted(
            _treasuryAccount,
            _actor,
            destination,
            _request.liquidity,
            _request.principalReductionBTC,
            _pairedReceived,
            _btcReceived,
            _btcFromPaired
        );
    }

    // =============================================================
    // Internal Functions
    // =============================================================

    /// @notice Reverts unless BTCReservePolicy allows the proposed principal amount.
    /// @param _treasuryAccount Treasury Account being checked.
    /// @param _btcAmount BTC principal amount being checked.
    function _requirePolicyAllowed(address _treasuryAccount, uint256 _btcAmount) internal view {
        BTCReservePolicy.BTCAllocationPreview memory _preview =
            btcReservePolicy.previewBTCAllocation(_treasuryAccount, destination, _btcAmount);
        require(_preview.allowed, PolicyBlocked(_preview.reason));
    }

    /// @notice Reverts when the Treasury Account lacks the ERC20-compatible BTC balance needed for execution.
    /// @param _treasuryAccount Treasury Account whose BTC token balance is checked.
    /// @param _btcAmount Required BTC token amount.
    function _requireTreasuryBTCBalance(address _treasuryAccount, uint256 _btcAmount) internal view {
        uint256 _balance = IERC20(principalAsset).balanceOf(_treasuryAccount);
        require(_balance >= _btcAmount, InsufficientTreasuryBTCBalance(_btcAmount, _balance));
    }

    /// @notice Swaps ERC20-compatible BTC into the paired BTC-correlated asset.
    /// @param _treasuryAccount Treasury Account forwarding the router call.
    /// @param _btcToSwap BTC amount to swap.
    /// @param _minPairedOut Minimum paired asset amount required.
    /// @return pairedReceived Paired asset balance delta received by the Treasury Account.
    function _swapBTCToPaired(address _treasuryAccount, uint256 _btcToSwap, uint256 _minPairedOut)
        internal
        returns (uint256 pairedReceived)
    {
        uint256 _pairedBefore = IERC20(pairedAsset).balanceOf(_treasuryAccount);
        ITigrisBasicRouter.Route[] memory _routes = _buildRoute(principalAsset, pairedAsset);

        _callTreasury(
            _treasuryAccount,
            address(tigrisRouter),
            abi.encodeCall(
                ITigrisBasicRouter.swapExactTokensForTokens,
                (_btcToSwap, _minPairedOut, _routes, _treasuryAccount, block.timestamp + deadlineWindow)
            )
        );

        pairedReceived = IERC20(pairedAsset).balanceOf(_treasuryAccount) - _pairedBefore;
        require(pairedReceived >= _minPairedOut, InsufficientPairedOutput(pairedReceived, _minPairedOut));
    }

    /// @notice Adds liquidity to the configured Tigris BTC-correlated stable pool.
    /// @param _treasuryAccount Treasury Account forwarding the router call.
    /// @param _pairedAmount Paired asset amount supplied as token A.
    /// @param _btcAmount BTC amount supplied as token B.
    /// @param _minPairedUsed Minimum paired asset amount that must be used.
    /// @param _minBTCUsed Minimum BTC amount that must be used.
    /// @param _minLiquidity Minimum LP liquidity that must be minted.
    /// @return outcome Token amounts consumed and LP liquidity minted.
    function _addLiquidity(
        address _treasuryAccount,
        uint256 _pairedAmount,
        uint256 _btcAmount,
        uint256 _minPairedUsed,
        uint256 _minBTCUsed,
        uint256 _minLiquidity
    ) internal returns (LiquidityOutcome memory outcome) {
        bytes memory _addLiquidityResult = _callAddLiquidity(
            _treasuryAccount, _pairedAmount, _btcAmount, _minPairedUsed, _minBTCUsed
        );

        (outcome.pairedUsed, outcome.btcUsed, outcome.liquidityMinted) =
            abi.decode(_addLiquidityResult, (uint256, uint256, uint256));
        require(
            outcome.liquidityMinted >= _minLiquidity,
            InsufficientLiquidityMinted(outcome.liquidityMinted, _minLiquidity)
        );
    }

    /// @notice Encodes and forwards the Tigris add-liquidity call through the Treasury Account.
    /// @param _treasuryAccount Treasury Account forwarding the router call.
    /// @param _pairedAmount Paired asset amount supplied as token A.
    /// @param _btcAmount BTC amount supplied as token B.
    /// @param _minPairedUsed Minimum paired asset amount that must be used.
    /// @param _minBTCUsed Minimum BTC amount that must be used.
    /// @return result Raw add-liquidity return data.
    function _callAddLiquidity(
        address _treasuryAccount,
        uint256 _pairedAmount,
        uint256 _btcAmount,
        uint256 _minPairedUsed,
        uint256 _minBTCUsed
    ) internal returns (bytes memory result) {
        result = _callTreasury(
            _treasuryAccount,
            address(tigrisRouter),
            abi.encodeCall(
                ITigrisBasicRouter.addLiquidity,
                (
                    pairedAsset,
                    principalAsset,
                    poolStable,
                    _pairedAmount,
                    _btcAmount,
                    _minPairedUsed,
                    _minBTCUsed,
                    _treasuryAccount,
                    block.timestamp + deadlineWindow
                )
            )
        );
    }

    /// @notice Removes liquidity from the configured Tigris BTC-correlated stable pool.
    /// @param _treasuryAccount Treasury Account forwarding the router call.
    /// @param _liquidity LP amount to burn.
    /// @param _minPairedOut Minimum paired asset amount required.
    /// @param _minBTCOut Minimum BTC amount required.
    /// @return pairedReceived Paired asset returned by the pool.
    /// @return btcReceived BTC returned by the pool.
    function _removeLiquidity(address _treasuryAccount, uint256 _liquidity, uint256 _minPairedOut, uint256 _minBTCOut)
        internal
        returns (uint256 pairedReceived, uint256 btcReceived)
    {
        bytes memory _removeLiquidityResult = _callTreasury(
            _treasuryAccount,
            address(tigrisRouter),
            abi.encodeCall(
                ITigrisBasicRouter.removeLiquidity,
                (
                    pairedAsset,
                    principalAsset,
                    poolStable,
                    _liquidity,
                    _minPairedOut,
                    _minBTCOut,
                    _treasuryAccount,
                    block.timestamp + deadlineWindow
                )
            )
        );

        (pairedReceived, btcReceived) = abi.decode(_removeLiquidityResult, (uint256, uint256));
    }

    /// @notice Swaps paired BTC-correlated asset back into ERC20-compatible BTC.
    /// @param _treasuryAccount Treasury Account forwarding the router call.
    /// @param _pairedAmount Paired asset amount to swap.
    /// @param _minBTCOut Minimum BTC output required.
    /// @return btcReturned BTC output returned by the router.
    function _swapPairedToBTC(address _treasuryAccount, uint256 _pairedAmount, uint256 _minBTCOut)
        internal
        returns (uint256 btcReturned)
    {
        ITigrisBasicRouter.Route[] memory _routes = _buildRoute(pairedAsset, principalAsset);
        bytes memory _swapResult = _callTreasury(
            _treasuryAccount,
            address(tigrisRouter),
            abi.encodeCall(
                ITigrisBasicRouter.swapExactTokensForTokens,
                (_pairedAmount, _minBTCOut, _routes, _treasuryAccount, block.timestamp + deadlineWindow)
            )
        );

        uint256[] memory _amounts = abi.decode(_swapResult, (uint256[]));
        require(_amounts.length >= 2, UnexpectedSwapPathLength(_amounts.length));
        btcReturned = _amounts[_amounts.length - 1];
    }

    /// @notice Builds a one-hop Tigris route for the configured BTC-correlated pool.
    /// @param _from Input token for the swap.
    /// @param _to Output token for the swap.
    /// @return routes Single-hop route array accepted by the deployed Tigris router.
    function _buildRoute(address _from, address _to) internal view returns (ITigrisBasicRouter.Route[] memory routes) {
        routes = new ITigrisBasicRouter.Route[](1);
        routes[0] = ITigrisBasicRouter.Route({ from: _from, to: _to, stable: poolStable, factory: poolFactory });
    }

    /// @notice Quotes the final token output for a Tigris route and validates the returned route length.
    /// @param _amountIn Input token amount being quoted.
    /// @param _routes Route used for the quote.
    /// @return amountOut Final token output quoted by the router.
    function _quoteSwapOutput(uint256 _amountIn, ITigrisBasicRouter.Route[] memory _routes)
        internal
        view
        returns (uint256 amountOut)
    {
        if (_amountIn == 0) return 0;
        uint256[] memory _amounts = tigrisRouter.getAmountsOut(_amountIn, _routes);
        require(_amounts.length >= 2, UnexpectedSwapPathLength(_amounts.length));
        amountOut = _amounts[_amounts.length - 1];
    }

    /// @notice Converts an expected amount into a preview minimum using the configured slippage setting.
    /// @param _amount Expected token or liquidity amount.
    /// @return Minimum acceptable amount after applying `maxSlippageBps`.
    function _amountAfterSlippage(uint256 _amount) internal view returns (uint256) {
        return (_amount * (10_000 - maxSlippageBps)) / 10_000;
    }

    /// @notice Reads BTC-principal sleeve accounting from a Treasury Account.
    /// @param _treasury Treasury Account being queried.
    /// @return principal BTC principal currently tracked for this handler's destination.
    function _btcPrincipal(address _treasury) internal view returns (uint256 principal) {
        if (_treasury.code.length == 0) return 0;

        try TreasuryAccount(payable(_treasury)).btcSleevePrincipalAllocations(destination) returns (
            uint256 _principal
        ) {
            return _principal;
        } catch {
            return 0;
        }
    }

    /// @notice Executes router calldata from the Treasury Account so assets and receipts stay account-owned.
    /// @param _treasuryAccount Treasury Account that forwards the external router call.
    /// @param _target External router target called by the Treasury Account.
    /// @param _data Encoded router calldata.
    /// @return result Decoded raw return data from the Treasury Account forwarding call.
    function _callTreasury(address _treasuryAccount, address _target, bytes memory _data)
        internal
        returns (bytes memory result)
    {
        (bool _success, bytes memory _result) = _treasuryAccount.call(
            abi.encodeWithSignature("executeFromBTCHandler(address,uint256,bytes)", _target, 0, _data)
        );
        if (!_success) {
            _revertWithReturnData(_result);
        }

        return abi.decode(_result, (bytes));
    }

    /// @notice Bubbles revert data returned by the Treasury Account forwarding path.
    /// @param _returnData Revert data returned by the failed low-level call.
    function _revertWithReturnData(bytes memory _returnData) internal pure {
        if (_returnData.length == 0) {
            revert();
        }

        assembly {
            revert(add(_returnData, 32), mload(_returnData))
        }
    }
}
