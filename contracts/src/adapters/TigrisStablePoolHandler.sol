// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TreasuryAccount } from "../core/TreasuryAccount.sol";
import { IAllocationHandler } from "../interfaces/IAllocationHandler.sol";
import { ITigrisBasicRouter } from "../interfaces/ITigrisBasicRouter.sol";
import { ITigrisStablePoolHandlerMetadata } from "../interfaces/ITigrisStablePoolHandlerMetadata.sol";

/// @title TigrisStablePoolHandler
/// @notice Handler that routes idle MUSD into a Tigris stable pool by swapping part of the deposit into the paired
/// token, then adding liquidity through the Tigris router. LP tokens remain owned by the Treasury Account.
/// @dev Router function signatures follow Mezo developer documentation examples for swap and add-liquidity flows.
contract TigrisStablePoolHandler is IAllocationHandler, ITigrisStablePoolHandlerMetadata {
    struct DepositOutcome {
        uint256 pairedReceived;
        uint256 liquidityMinted;
        uint256 refundMUSD;
    }

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

    error InvalidAllocationRouter(address allocationRouter);
    error InvalidDestination(address destination);
    error InvalidRouter(address router);
    error InvalidToken(address token);
    error InvalidTreasuryAccount(address treasuryAccount);
    error InvalidAmount(uint256 amount);
    error ZeroLiquidity();
    error UnauthorizedCaller(address caller);
    error UnexpectedSwapPathLength(uint256 pathLength);

    address public immutable allocationRouter;
    ITigrisBasicRouter internal immutable tigrisRouter;
    address public immutable override destination;
    IERC20 public immutable musdToken;
    IERC20 internal immutable pairedStableToken;
    uint256 public immutable deadlineWindow;

    /// @param _allocationRouter Router allowed to dispatch calls to this handler.
    /// @param _router Tigris router used for swap and liquidity actions.
    /// @param _destination LP token / pool destination reported to TreasuryOS policy and accounting.
    /// @param _musdToken MUSD token contributed by the treasury.
    /// @param _pairedToken Stable paired token combined with MUSD in the target pool.
    /// @param _deadlineWindow Number of seconds added to `block.timestamp` for router deadlines.
    constructor(
        address _allocationRouter,
        ITigrisBasicRouter _router,
        address _destination,
        IERC20 _musdToken,
        IERC20 _pairedToken,
        uint256 _deadlineWindow
    ) {
        require(_allocationRouter != address(0), InvalidAllocationRouter(_allocationRouter));
        require(address(_router) != address(0), InvalidRouter(address(_router)));
        require(_destination != address(0), InvalidDestination(_destination));
        require(address(_musdToken) != address(0), InvalidToken(address(_musdToken)));
        require(address(_pairedToken) != address(0), InvalidToken(address(_pairedToken)));

        allocationRouter = _allocationRouter;
        tigrisRouter = _router;
        destination = _destination;
        musdToken = _musdToken;
        pairedStableToken = _pairedToken;
        deadlineWindow = _deadlineWindow;
    }

    /// @inheritdoc ITigrisStablePoolHandlerMetadata
    function pairedToken() external view returns (address) {
        return address(pairedStableToken);
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

        uint256 _lpBalance = IERC20(destination).balanceOf(_treasuryAccount);
        require(_lpBalance > 0, ZeroLiquidity());

        uint256 _currentAllocation = TreasuryAccount(payable(_treasuryAccount)).destinationAllocations(destination);
        require(_currentAllocation >= _amount, InvalidAmount(_amount));

        uint256 _liquidityToBurn = (_lpBalance * _amount) / _currentAllocation;
        require(_liquidityToBurn > 0, ZeroLiquidity());

        TreasuryAccount(payable(_treasuryAccount))
            .forceApproveTokenFromHandler(destination, address(tigrisRouter), _liquidityToBurn);

        bytes memory _removeLiquidityResult = _callTreasury(
            _treasuryAccount,
            address(tigrisRouter),
            abi.encodeCall(
                ITigrisBasicRouter.removeLiquidity,
                (
                    address(musdToken),
                    address(pairedStableToken),
                    _liquidityToBurn,
                    0,
                    0,
                    _treasuryAccount,
                    block.timestamp + deadlineWindow
                )
            )
        );

        (uint256 _musdReceived, uint256 _pairedReceived) = abi.decode(_removeLiquidityResult, (uint256, uint256));

        if (_pairedReceived > 0) {
            _musdReceived += _swapPairBackToMUSD(_treasuryAccount, _pairedReceived);
        }

        TreasuryAccount(payable(_treasuryAccount))
            .settleWithdrawalFromHandler(_actor, destination, _amount, _musdReceived);

        result = _liquidityToBurn;

        emit StablePoolWithdrawalRouted(_treasuryAccount, _actor, destination, _amount, _liquidityToBurn, _musdReceived);
    }

    /// @inheritdoc IAllocationHandler
    function claimYield(address, address) external pure returns (uint256 amount) {
        amount = 0;
    }

    function _depositIntoStablePool(address _treasuryAccount, uint256 _musdToSwap, uint256 _musdToPair)
        internal
        returns (DepositOutcome memory outcome)
    {
        outcome.pairedReceived = _swapMUSDToPaired(_treasuryAccount, _musdToSwap);

        TreasuryAccount(payable(_treasuryAccount))
            .forceApproveTokenFromHandler(address(pairedStableToken), address(tigrisRouter), outcome.pairedReceived);

        bytes memory _addLiquidityResult = _callTreasury(
            _treasuryAccount,
            address(tigrisRouter),
            abi.encodeCall(
                ITigrisBasicRouter.addLiquidity,
                (
                    address(musdToken),
                    address(pairedStableToken),
                    _musdToPair,
                    outcome.pairedReceived,
                    0,
                    0,
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

    function _swapMUSDToPaired(address _treasuryAccount, uint256 _musdToSwap)
        internal
        returns (uint256 pairedReceived)
    {
        if (_musdToSwap == 0) {
            return 0;
        }

        uint256 _pairedBalanceBefore = pairedStableToken.balanceOf(_treasuryAccount);
        address[] memory _path = new address[](2);
        _path[0] = address(musdToken);
        _path[1] = address(pairedStableToken);

        _callTreasury(
            _treasuryAccount,
            address(tigrisRouter),
            abi.encodeCall(
                ITigrisBasicRouter.swapExactTokensForTokens,
                (_musdToSwap, 0, _path, _treasuryAccount, block.timestamp + deadlineWindow)
            )
        );

        pairedReceived = pairedStableToken.balanceOf(_treasuryAccount) - _pairedBalanceBefore;
    }

    function _swapPairBackToMUSD(address _treasuryAccount, uint256 _pairedAmount)
        internal
        returns (uint256 musdReturned)
    {
        TreasuryAccount(payable(_treasuryAccount))
            .forceApproveTokenFromHandler(address(pairedStableToken), address(tigrisRouter), _pairedAmount);

        address[] memory _path = new address[](2);
        _path[0] = address(pairedStableToken);
        _path[1] = address(musdToken);

        bytes memory _swapResult = _callTreasury(
            _treasuryAccount,
            address(tigrisRouter),
            abi.encodeCall(
                ITigrisBasicRouter.swapExactTokensForTokens,
                (_pairedAmount, 0, _path, _treasuryAccount, block.timestamp + deadlineWindow)
            )
        );

        uint256[] memory _amounts = abi.decode(_swapResult, (uint256[]));
        require(_amounts.length >= 2, UnexpectedSwapPathLength(_amounts.length));
        musdReturned = _amounts[_amounts.length - 1];
    }

    function _callTreasury(address _treasuryAccount, address _target, bytes memory _data)
        internal
        returns (bytes memory result)
    {
        (bool _success, bytes memory _result) = _treasuryAccount.call(
            abi.encodeWithSignature("executeFromHandler(address,uint256,bytes)", _target, 0, _data)
        );
        require(_success, string(_result));
        return abi.decode(_result, (bytes));
    }
}
