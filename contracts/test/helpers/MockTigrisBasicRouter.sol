// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ITigrisBasicRouter } from "../../src/interfaces/ITigrisBasicRouter.sol";
import { MockMUSDToken } from "./MockMUSDToken.sol";
import { MockTigrisLPToken } from "./MockTigrisLPToken.sol";

contract MockTigrisBasicRouter is ITigrisBasicRouter {
    using SafeERC20 for IERC20;

    error InsufficientSwapOutput(uint256 amountOut, uint256 amountOutMin);
    error InsufficientLiquidityAmountA(uint256 amountA, uint256 amountAMin);
    error InsufficientLiquidityAmountB(uint256 amountB, uint256 amountBMin);
    error InsufficientRemoveAmountA(uint256 amountA, uint256 amountAMin);
    error InsufficientRemoveAmountB(uint256 amountB, uint256 amountBMin);

    MockMUSDToken public immutable musdToken;
    MockMUSDToken public immutable pairedToken;
    MockTigrisLPToken public immutable lpToken;

    uint256 public addLiquidityUsageBps = 10_000;
    uint256 public removeLiquidityOutputBps = 10_000;
    uint256 public swapOutputBps = 10_000;
    uint256 public swapReturnPathLength = 2;
    uint256 public lastSwapAmountOutMin;
    uint256 public lastAddAmountAMin;
    uint256 public lastAddAmountBMin;
    uint256 public lastRemoveAmountAMin;
    uint256 public lastRemoveAmountBMin;

    constructor(MockMUSDToken _musdToken, MockMUSDToken _pairedToken, MockTigrisLPToken _lpToken) {
        musdToken = _musdToken;
        pairedToken = _pairedToken;
        lpToken = _lpToken;
    }

    function setAddLiquidityUsageBps(uint256 _addLiquidityUsageBps) external {
        require(_addLiquidityUsageBps <= 10_000, "invalid usage");
        addLiquidityUsageBps = _addLiquidityUsageBps;
    }

    function setRemoveLiquidityOutputBps(uint256 _removeLiquidityOutputBps) external {
        require(_removeLiquidityOutputBps <= 10_000, "invalid usage");
        removeLiquidityOutputBps = _removeLiquidityOutputBps;
    }

    function setSwapOutputBps(uint256 _swapOutputBps) external {
        require(_swapOutputBps <= 10_000, "invalid output");
        swapOutputBps = _swapOutputBps;
    }

    function setSwapReturnPathLength(uint256 _swapReturnPathLength) external {
        swapReturnPathLength = _swapReturnPathLength;
    }

    function swapExactTokensForTokens(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] calldata _path,
        address _to,
        uint256
    ) external returns (uint256[] memory amounts) {
        require(_path.length == 2, "invalid path");

        IERC20(_path[0]).safeTransferFrom(msg.sender, address(this), _amountIn);
        uint256 amountOut = (_amountIn * swapOutputBps) / 10_000;
        if (amountOut < _amountOutMin) {
            revert InsufficientSwapOutput(amountOut, _amountOutMin);
        }

        lastSwapAmountOutMin = _amountOutMin;
        MockMUSDToken(_path[1]).mint(_to, amountOut);

        amounts = new uint256[](swapReturnPathLength);
        if (swapReturnPathLength > 0) {
            amounts[0] = _amountIn;
        }
        if (swapReturnPathLength > 1) {
            amounts[1] = amountOut;
        }
    }

    function addLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _amountADesired,
        uint256 _amountBDesired,
        uint256 _amountAMin,
        uint256 _amountBMin,
        address _to,
        uint256
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        amountA = (_amountADesired * addLiquidityUsageBps) / 10_000;
        amountB = (_amountBDesired * addLiquidityUsageBps) / 10_000;
        if (amountA < _amountAMin) {
            revert InsufficientLiquidityAmountA(amountA, _amountAMin);
        }
        if (amountB < _amountBMin) {
            revert InsufficientLiquidityAmountB(amountB, _amountBMin);
        }

        IERC20(_tokenA).safeTransferFrom(msg.sender, address(this), amountA);
        IERC20(_tokenB).safeTransferFrom(msg.sender, address(this), amountB);
        liquidity = amountA + amountB;
        lastAddAmountAMin = _amountAMin;
        lastAddAmountBMin = _amountBMin;

        lpToken.mint(_to, liquidity);
    }

    function removeLiquidity(
        address,
        address,
        uint256 _liquidity,
        uint256 _amountAMin,
        uint256 _amountBMin,
        address _to,
        uint256
    ) external returns (uint256 amountA, uint256 amountB) {
        lpToken.burnFrom(msg.sender, _liquidity);

        uint256 baseAmountA = _liquidity / 2;
        uint256 baseAmountB = _liquidity - baseAmountA;
        amountA = (baseAmountA * removeLiquidityOutputBps) / 10_000;
        amountB = (baseAmountB * removeLiquidityOutputBps) / 10_000;
        if (amountA < _amountAMin) {
            revert InsufficientRemoveAmountA(amountA, _amountAMin);
        }
        if (amountB < _amountBMin) {
            revert InsufficientRemoveAmountB(amountB, _amountBMin);
        }

        musdToken.mint(_to, amountA);
        pairedToken.mint(_to, amountB);
        lastRemoveAmountAMin = _amountAMin;
        lastRemoveAmountBMin = _amountBMin;
    }
}
