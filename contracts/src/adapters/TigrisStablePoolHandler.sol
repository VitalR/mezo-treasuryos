// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TreasuryAccount } from "../core/TreasuryAccount.sol";
import { IAllocationHandler } from "../interfaces/IAllocationHandler.sol";
import { ITigrisBasicRouter } from "../interfaces/ITigrisBasicRouter.sol";
import { ITigrisStablePoolHandlerMetadata } from "../interfaces/ITigrisStablePoolHandlerMetadata.sol";

/// @title TigrisStablePoolHandler
/// @notice Handler that routes idle MUSD into a configured Tigris basic pool by swapping part of the deposit into the
/// paired token, then adding liquidity through the Tigris router. LP tokens remain owned by the Treasury Account.
/// @dev The deployed Tigris router uses Route[] for swaps and an explicit stable flag for liquidity actions.
contract TigrisStablePoolHandler is IAllocationHandler, ITigrisStablePoolHandlerMetadata {
    // =============================================================
    // Constants
    // =============================================================

    uint256 internal constant BPS_DENOMINATOR = 10_000;

    // =============================================================
    // Types
    // =============================================================

    struct DepositOutcome {
        uint256 pairedReceived;
        uint256 liquidityMinted;
        uint256 refundMUSD;
    }

    // =============================================================
    // Events
    // =============================================================

    event StablePoolDepositRouted(
        address indexed treasuryAccount,
        address indexed actor,
        address indexed destination,
        uint256 musdIn,
        uint256 pairedTokenReceived,
        uint256 liquidityMinted,
        uint256 refundedMUSD
    );
    event StablePoolWithdrawalRouted(
        address indexed treasuryAccount,
        address indexed actor,
        address indexed destination,
        uint256 allocationReduced,
        uint256 liquidityBurned,
        uint256 musdReturned
    );

    // =============================================================
    // Errors
    // =============================================================

    error InvalidAllocationRouter(address allocationRouter);
    error InvalidDestination(address destination);
    error InvalidPoolFactory(address poolFactory);
    error InvalidRouter(address router);
    error InvalidToken(address token);
    error InvalidTreasuryAccount(address treasuryAccount);
    error InvalidAmount(uint256 amount);
    error InvalidSlippageBps(uint256 maxSlippageBps);
    error ZeroLiquidity();
    error UnauthorizedCaller(address caller);
    error UnexpectedSwapPathLength(uint256 pathLength);

    // =============================================================
    // Storage
    // =============================================================

    address public immutable allocationRouter;
    ITigrisBasicRouter internal immutable tigrisRouter;
    address public immutable override destination;
    IERC20 public immutable musdToken;
    IERC20 internal immutable pairedTokenAsset;
    address public immutable override poolFactory;
    bool public immutable override poolStable;
    uint256 public immutable deadlineWindow;
    uint256 public immutable override maxSlippageBps;

    // =============================================================
    // Constructor
    // =============================================================

    /// @param _allocationRouter Router allowed to dispatch calls to this handler.
    /// @param _router Tigris router used for swap and liquidity actions.
    /// @param _destination LP token / pool destination reported to TreasuryOS policy and accounting.
    /// @param _poolFactory Tigris pool factory used for route and liquidity execution.
    /// @param _poolStable Whether the target Tigris pool is stable.
    /// @param _musdToken MUSD token contributed by the treasury.
    /// @param _pairedToken Paired token combined with MUSD in the target pool.
    /// @param _deadlineWindow Number of seconds added to `block.timestamp` for router deadlines.
    /// @param _maxSlippageBps Maximum accepted execution slippage in basis points.
    constructor(
        address _allocationRouter,
        ITigrisBasicRouter _router,
        address _destination,
        address _poolFactory,
        bool _poolStable,
        IERC20 _musdToken,
        IERC20 _pairedToken,
        uint256 _deadlineWindow,
        uint256 _maxSlippageBps
    ) {
        require(_allocationRouter != address(0), InvalidAllocationRouter(_allocationRouter));
        require(address(_router) != address(0), InvalidRouter(address(_router)));
        require(_destination != address(0), InvalidDestination(_destination));
        require(_poolFactory != address(0), InvalidPoolFactory(_poolFactory));
        require(address(_musdToken) != address(0), InvalidToken(address(_musdToken)));
        require(address(_pairedToken) != address(0), InvalidToken(address(_pairedToken)));
        require(_maxSlippageBps < BPS_DENOMINATOR, InvalidSlippageBps(_maxSlippageBps));

        allocationRouter = _allocationRouter;
        tigrisRouter = _router;
        destination = _destination;
        poolFactory = _poolFactory;
        poolStable = _poolStable;
        musdToken = _musdToken;
        pairedTokenAsset = _pairedToken;
        deadlineWindow = _deadlineWindow;
        maxSlippageBps = _maxSlippageBps;
    }

    // =============================================================
    // External Functions
    // =============================================================

    /// @inheritdoc ITigrisStablePoolHandlerMetadata
    function pairedToken() external view returns (address) {
        return address(pairedTokenAsset);
    }

    /// @inheritdoc ITigrisStablePoolHandlerMetadata
    function router() external view returns (address) {
        return address(tigrisRouter);
    }

    /// @inheritdoc IAllocationHandler
    function deposit(address _treasuryAccount, address _actor, uint256 _amount) external returns (uint256 result) {
        require(msg.sender == allocationRouter, UnauthorizedCaller(msg.sender));
        require(_treasuryAccount != address(0), InvalidTreasuryAccount(_treasuryAccount));
        require(_amount > 0, InvalidAmount(_amount));

        uint256 _musdToSwap = _amount / 2;
        uint256 _musdToPair = _amount - _musdToSwap;

        TreasuryAccount(payable(_treasuryAccount))
            .forceApproveTokenFromHandler(address(musdToken), address(tigrisRouter), _amount);
        TreasuryAccount(payable(_treasuryAccount)).allocateFromAdapter(_actor, destination, _amount);

        DepositOutcome memory _outcome = _depositIntoStablePool(_treasuryAccount, _musdToSwap, _musdToPair);

        if (_outcome.refundMUSD > 0) {
            TreasuryAccount(payable(_treasuryAccount))
                .settleWithdrawalFromHandler(_actor, destination, _outcome.refundMUSD, _outcome.refundMUSD);
        }

        result = _outcome.liquidityMinted;

        emit StablePoolDepositRouted(
            _treasuryAccount,
            _actor,
            destination,
            _amount,
            _outcome.pairedReceived,
            _outcome.liquidityMinted,
            _outcome.refundMUSD
        );
    }

    /// @inheritdoc IAllocationHandler
    function withdraw(address _treasuryAccount, address _actor, uint256 _amount) external returns (uint256 result) {
        require(msg.sender == allocationRouter, UnauthorizedCaller(msg.sender));
        require(_treasuryAccount != address(0), InvalidTreasuryAccount(_treasuryAccount));
        require(_amount > 0, InvalidAmount(_amount));

        uint256 _musdReceived;
        (result, _musdReceived) = _withdrawFromStablePool(_treasuryAccount, _amount);

        TreasuryAccount(payable(_treasuryAccount))
            .settleWithdrawalFromHandler(_actor, destination, _amount, _musdReceived);

        emit StablePoolWithdrawalRouted(_treasuryAccount, _actor, destination, _amount, result, _musdReceived);
    }

    /// @inheritdoc IAllocationHandler
    function withdrawForWorkflow(address _treasuryAccount, address _actor, uint256 _amount)
        external
        returns (uint256 result)
    {
        require(msg.sender == allocationRouter, UnauthorizedCaller(msg.sender));
        require(_treasuryAccount != address(0), InvalidTreasuryAccount(_treasuryAccount));
        require(_amount > 0, InvalidAmount(_amount));

        uint256 _musdReceived;
        (result, _musdReceived) = _withdrawFromStablePool(_treasuryAccount, _amount);

        TreasuryAccount(payable(_treasuryAccount))
            .settleWorkflowWithdrawalFromHandler(_actor, destination, _amount, _musdReceived);

        emit StablePoolWithdrawalRouted(_treasuryAccount, _actor, destination, _amount, result, _musdReceived);
    }

    /// @inheritdoc IAllocationHandler
    function claimYield(address, address) external pure returns (uint256 amount) {
        amount = 0;
    }

    // =============================================================
    // Internal Functions
    // =============================================================

    /// @notice Completes the stable-pool entry after account-level policy and accounting have passed.
    /// @param _treasuryAccount Treasury Account contributing MUSD and receiving LP tokens.
    /// @param _musdToSwap Portion of MUSD swapped into the paired stable token.
    /// @param _musdToPair Portion of MUSD contributed directly as the MUSD side of the pool.
    /// @return outcome Paired-token output, LP liquidity minted, and any MUSD-equivalent refund.
    function _depositIntoStablePool(address _treasuryAccount, uint256 _musdToSwap, uint256 _musdToPair)
        internal
        returns (DepositOutcome memory outcome)
    {
        outcome.pairedReceived = _swapMUSDToPaired(_treasuryAccount, _musdToSwap);

        TreasuryAccount(payable(_treasuryAccount))
            .forceApproveTokenFromHandler(address(pairedTokenAsset), address(tigrisRouter), outcome.pairedReceived);

        bytes memory _addLiquidityResult = _callTreasury(
            _treasuryAccount,
            address(tigrisRouter),
            abi.encodeCall(
                ITigrisBasicRouter.addLiquidity,
                (
                    address(musdToken),
                    address(pairedTokenAsset),
                    poolStable,
                    _musdToPair,
                    outcome.pairedReceived,
                    _amountAfterSlippage(_musdToPair),
                    _amountAfterSlippage(outcome.pairedReceived),
                    _treasuryAccount,
                    block.timestamp + deadlineWindow
                )
            )
        );

        (uint256 _musdUsed, uint256 _pairedUsed, uint256 _liquidityMinted) =
            abi.decode(_addLiquidityResult, (uint256, uint256, uint256));

        outcome.liquidityMinted = _liquidityMinted;
        outcome.refundMUSD = _musdToPair - _musdUsed;

        uint256 _pairedRefund = outcome.pairedReceived - _pairedUsed;
        if (_pairedRefund > 0) {
            outcome.refundMUSD += _swapPairBackToMUSD(_treasuryAccount, _pairedRefund);
        }
    }

    /// @notice Removes proportional LP exposure and converts any paired-token output back into MUSD.
    /// @param _treasuryAccount Treasury Account that owns the LP receipt tokens and receives MUSD.
    /// @param _amount MUSD-denominated allocation amount to reduce.
    /// @return liquidityBurned LP token amount burned through the Tigris router.
    /// @return musdReceived Total MUSD returned after liquidity removal and paired-token swap-back.
    function _withdrawFromStablePool(address _treasuryAccount, uint256 _amount)
        internal
        returns (uint256 liquidityBurned, uint256 musdReceived)
    {
        uint256 _lpBalance = IERC20(destination).balanceOf(_treasuryAccount);
        require(_lpBalance > 0, ZeroLiquidity());

        uint256 _currentAllocation = TreasuryAccount(payable(_treasuryAccount)).destinationAllocations(destination);
        require(_currentAllocation >= _amount, InvalidAmount(_amount));

        liquidityBurned = (_lpBalance * _amount) / _currentAllocation;
        require(liquidityBurned > 0, ZeroLiquidity());

        TreasuryAccount(payable(_treasuryAccount))
            .forceApproveTokenFromHandler(destination, address(tigrisRouter), liquidityBurned);

        uint256 _pairedReceived;
        (musdReceived, _pairedReceived) = _removeLiquidityFromStablePool(_treasuryAccount, liquidityBurned, _amount);

        if (_pairedReceived > 0) {
            musdReceived += _swapPairBackToMUSD(_treasuryAccount, _pairedReceived);
        }
    }

    /// @notice Calls Tigris removeLiquidity with configured pool metadata and slippage bounds.
    /// @param _treasuryAccount Treasury Account forwarding the router call.
    /// @param _liquidityToBurn LP token amount to remove.
    /// @param _allocationAmount MUSD-denominated allocation amount being reduced.
    /// @return musdReceived MUSD side returned by the pool.
    /// @return pairedReceived Paired-token side returned by the pool.
    function _removeLiquidityFromStablePool(
        address _treasuryAccount,
        uint256 _liquidityToBurn,
        uint256 _allocationAmount
    ) internal returns (uint256 musdReceived, uint256 pairedReceived) {
        bytes memory _removeLiquidityResult = _callTreasury(
            _treasuryAccount,
            address(tigrisRouter),
            abi.encodeCall(
                ITigrisBasicRouter.removeLiquidity,
                (
                    address(musdToken),
                    address(pairedTokenAsset),
                    poolStable,
                    _liquidityToBurn,
                    _amountAfterSlippage(_allocationAmount / 2),
                    _amountAfterSlippage(_allocationAmount - (_allocationAmount / 2)),
                    _treasuryAccount,
                    block.timestamp + deadlineWindow
                )
            )
        );

        (musdReceived, pairedReceived) = abi.decode(_removeLiquidityResult, (uint256, uint256));
    }

    /// @notice Swaps MUSD into the paired token through the Treasury Account execution boundary.
    /// @param _treasuryAccount Treasury Account that owns the input and receives the paired token.
    /// @param _musdToSwap MUSD amount to swap.
    /// @return pairedReceived Paired stable token amount received by the Treasury Account.
    function _swapMUSDToPaired(address _treasuryAccount, uint256 _musdToSwap)
        internal
        returns (uint256 pairedReceived)
    {
        if (_musdToSwap == 0) {
            return 0;
        }

        uint256 _pairedBalanceBefore = pairedTokenAsset.balanceOf(_treasuryAccount);
        ITigrisBasicRouter.Route[] memory _routes = _buildRoute(address(musdToken), address(pairedTokenAsset));

        _callTreasury(
            _treasuryAccount,
            address(tigrisRouter),
            abi.encodeCall(
                ITigrisBasicRouter.swapExactTokensForTokens,
                (
                    _musdToSwap,
                    _amountAfterSlippage(_musdToSwap),
                    _routes,
                    _treasuryAccount,
                    block.timestamp + deadlineWindow
                )
            )
        );

        pairedReceived = pairedTokenAsset.balanceOf(_treasuryAccount) - _pairedBalanceBefore;
    }

    /// @notice Swaps paired tokens back into MUSD through the Treasury Account execution boundary.
    /// @param _treasuryAccount Treasury Account that owns the paired token and receives MUSD.
    /// @param _pairedAmount Paired token amount to swap.
    /// @return musdReturned MUSD amount returned by the router.
    function _swapPairBackToMUSD(address _treasuryAccount, uint256 _pairedAmount)
        internal
        returns (uint256 musdReturned)
    {
        TreasuryAccount(payable(_treasuryAccount))
            .forceApproveTokenFromHandler(address(pairedTokenAsset), address(tigrisRouter), _pairedAmount);

        ITigrisBasicRouter.Route[] memory _routes = _buildRoute(address(pairedTokenAsset), address(musdToken));

        bytes memory _swapResult = _callTreasury(
            _treasuryAccount,
            address(tigrisRouter),
            abi.encodeCall(
                ITigrisBasicRouter.swapExactTokensForTokens,
                (
                    _pairedAmount,
                    _amountAfterSlippage(_pairedAmount),
                    _routes,
                    _treasuryAccount,
                    block.timestamp + deadlineWindow
                )
            )
        );

        uint256[] memory _amounts = abi.decode(_swapResult, (uint256[]));
        require(_amounts.length >= 2, UnexpectedSwapPathLength(_amounts.length));
        musdReturned = _amounts[_amounts.length - 1];
    }

    /// @notice Builds a one-hop Tigris route for the configured pool.
    /// @param _from Input token for the swap.
    /// @param _to Output token for the swap.
    /// @return routes Single-hop route array accepted by the deployed Tigris router.
    function _buildRoute(address _from, address _to) internal view returns (ITigrisBasicRouter.Route[] memory routes) {
        routes = new ITigrisBasicRouter.Route[](1);
        routes[0] = ITigrisBasicRouter.Route({ from: _from, to: _to, stable: poolStable, factory: poolFactory });
    }

    /// @notice Converts an expected amount into a router minimum using the configured slippage limit.
    /// @param _amount Expected token or liquidity-side amount.
    /// @return Minimum acceptable amount after applying `maxSlippageBps`.
    function _amountAfterSlippage(uint256 _amount) internal view returns (uint256) {
        return (_amount * (BPS_DENOMINATOR - maxSlippageBps)) / BPS_DENOMINATOR;
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
            abi.encodeWithSignature("executeFromHandler(address,uint256,bytes)", _target, 0, _data)
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
