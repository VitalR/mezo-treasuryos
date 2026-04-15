// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title ITigrisBasicRouter
/// @notice TreasuryOS integration surface for Mezo/Tigris router-based swaps and liquidity actions.
/// @dev The swap and liquidity signatures follow the Mezo developer documentation examples for pools and swaps.
interface ITigrisBasicRouter {
    /// @notice Swaps an exact input amount across a token path.
    /// @param _amountIn Input token amount being swapped.
    /// @param _amountOutMin Minimum output token amount required.
    /// @param _path Token path executed by the router.
    /// @param _to Recipient of the output tokens.
    /// @param _deadline Timestamp after which the swap is invalid.
    /// @return amounts Per-hop amounts returned by the router.
    function swapExactTokensForTokens(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] calldata _path,
        address _to,
        uint256 _deadline
    ) external returns (uint256[] memory amounts);

    /// @notice Adds liquidity for a token pair and mints LP tokens to the recipient.
    /// @param _tokenA First pool token.
    /// @param _tokenB Second pool token.
    /// @param _amountADesired Desired amount of token A contributed.
    /// @param _amountBDesired Desired amount of token B contributed.
    /// @param _amountAMin Minimum amount of token A that must be used.
    /// @param _amountBMin Minimum amount of token B that must be used.
    /// @param _to Recipient of the LP tokens.
    /// @param _deadline Timestamp after which the liquidity add is invalid.
    /// @return amountA Actual amount of token A used.
    /// @return amountB Actual amount of token B used.
    /// @return liquidity LP liquidity minted to the recipient.
    function addLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _amountADesired,
        uint256 _amountBDesired,
        uint256 _amountAMin,
        uint256 _amountBMin,
        address _to,
        uint256 _deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    /// @notice Removes liquidity for a token pair and returns the underlying tokens to the recipient.
    /// @param _tokenA First pool token.
    /// @param _tokenB Second pool token.
    /// @param _liquidity LP amount being burned.
    /// @param _amountAMin Minimum token A amount required.
    /// @param _amountBMin Minimum token B amount required.
    /// @param _to Recipient of the underlying tokens.
    /// @param _deadline Timestamp after which the liquidity removal is invalid.
    /// @return amountA Token A amount returned.
    /// @return amountB Token B amount returned.
    function removeLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _liquidity,
        uint256 _amountAMin,
        uint256 _amountBMin,
        address _to,
        uint256 _deadline
    ) external returns (uint256 amountA, uint256 amountB);
}
