// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ITigrisBasicRouter } from "../../src/interfaces/ITigrisBasicRouter.sol";
import { MockMUSDToken } from "./MockMUSDToken.sol";
import { MockTigrisLPToken } from "./MockTigrisLPToken.sol";

contract MockTigrisBasicRouter is ITigrisBasicRouter {
    using SafeERC20 for IERC20;

    MockMUSDToken public immutable musdToken;
    MockMUSDToken public immutable pairedToken;
    MockTigrisLPToken public immutable lpToken;

    uint256 public addLiquidityUsageBps = 10_000;
    uint256 public swapReturnPathLength = 2;

    constructor(MockMUSDToken _musdToken, MockMUSDToken _pairedToken, MockTigrisLPToken _lpToken) {
        musdToken = _musdToken;
        pairedToken = _pairedToken;
        lpToken = _lpToken;
    }

    function setAddLiquidityUsageBps(uint256 _addLiquidityUsageBps) external {
        require(_addLiquidityUsageBps <= 10_000, "invalid usage");
        addLiquidityUsageBps = _addLiquidityUsageBps;
    }

    function setSwapReturnPathLength(uint256 _swapReturnPathLength) external {
        swapReturnPathLength = _swapReturnPathLength;
    }

    function swapExactTokensForTokens(uint256 _amountIn, uint256, address[] calldata _path, address _to, uint256)
        external
        returns (uint256[] memory amounts)
    {
        require(_path.length == 2, "invalid path");

        IERC20(_path[0]).safeTransferFrom(msg.sender, address(this), _amountIn);
        MockMUSDToken(_path[1]).mint(_to, _amountIn);

        amounts = new uint256[](swapReturnPathLength);
        if (swapReturnPathLength > 0) {
            amounts[0] = _amountIn;
        }
        if (swapReturnPathLength > 1) {
            amounts[1] = _amountIn;
        }
    }

    function addLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _amountADesired,
        uint256 _amountBDesired,
        uint256,
        uint256,
        address _to,
        uint256
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        amountA = (_amountADesired * addLiquidityUsageBps) / 10_000;
        amountB = (_amountBDesired * addLiquidityUsageBps) / 10_000;

        IERC20(_tokenA).safeTransferFrom(msg.sender, address(this), amountA);
        IERC20(_tokenB).safeTransferFrom(msg.sender, address(this), amountB);
        liquidity = amountA + amountB;

        lpToken.mint(_to, liquidity);
    }

    function removeLiquidity(address, address, uint256 _liquidity, uint256, uint256, address _to, uint256)
        external
        returns (uint256 amountA, uint256 amountB)
    {
        lpToken.burnFrom(msg.sender, _liquidity);

        amountA = _liquidity / 2;
        amountB = _liquidity - amountA;

        musdToken.mint(_to, amountA);
        pairedToken.mint(_to, amountB);
    }
}
