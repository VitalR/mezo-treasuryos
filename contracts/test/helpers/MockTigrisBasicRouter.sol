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

    constructor(MockMUSDToken _musdToken, MockMUSDToken _pairedToken, MockTigrisLPToken _lpToken) {
        musdToken = _musdToken;
        pairedToken = _pairedToken;
        lpToken = _lpToken;
    }

    function swapExactTokensForTokens(uint256 _amountIn, uint256, address[] calldata _path, address _to, uint256)
        external
        returns (uint256[] memory amounts)
    {
        require(_path.length == 2, "invalid path");

        IERC20(_path[0]).safeTransferFrom(msg.sender, address(this), _amountIn);
        MockMUSDToken(_path[1]).mint(_to, _amountIn);

        amounts = new uint256[](2);
        amounts[0] = _amountIn;
        amounts[1] = _amountIn;
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
        IERC20(_tokenA).safeTransferFrom(msg.sender, address(this), _amountADesired);
        IERC20(_tokenB).safeTransferFrom(msg.sender, address(this), _amountBDesired);

        amountA = _amountADesired;
        amountB = _amountBDesired;
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
