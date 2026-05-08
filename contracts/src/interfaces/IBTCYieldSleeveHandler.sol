// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title IBTCYieldSleeveHandler
/// @notice Read-only interface for BTC-denominated yield sleeve candidates.
/// @dev V1 uses this shape for preview/reporting only. Principal-moving BTC sleeve execution should be added only
///      after BTC reserve policy, receipt accounting, min-out checks, and multisig approval paths are validated.
interface IBTCYieldSleeveHandler {
    /// @notice Risk category assigned to a BTC-denominated sleeve candidate.
    enum BTCSleeveRiskClass {
        /// @notice Sleeve is disabled and cannot receive BTC principal.
        DISABLED,
        /// @notice Sleeve is intended to preserve BTC-correlated exposure, such as mcbBTC/BTC.
        BTC_CORRELATED,
        /// @notice Sleeve changes pure BTC exposure through BTC/stable or similar LP exposure.
        BTC_DIRECTIONAL_LP,
        /// @notice Sleeve is speculative and blocked by default in V1 policy.
        SPECULATIVE,
        /// @notice Sleeve routes to an external vault and requires separate due diligence.
        EXTERNAL_VAULT
    }

    /// @notice Current BTC-denominated sleeve exposure for a treasury.
    /// @param principalBTC BTC principal represented by the position.
    /// @param pairedAssetAmount Paired BTC-correlated or non-BTC asset amount represented by the sleeve.
    /// @param btcEquivalentExposure Estimated BTC-equivalent exposure for reporting.
    /// @param receiptBalance Unstaked receipt or LP token balance.
    /// @param stakedReceiptBalance Staked receipt or LP token balance, if staking exists.
    /// @param claimableRewards Claimable non-principal rewards, if the sleeve exposes them.
    /// @param swapPriceImpactBps Observed or estimated price impact for entering the sleeve.
    /// @param slippageBps Slippage setting used for the preview.
    /// @param principalMovementSupported Whether this handler supports principal movement in the current deployment.
    /// @param stakingSupported Whether this sleeve exposes staking or gauge behavior.
    struct BTCExposure {
        uint256 principalBTC;
        uint256 pairedAssetAmount;
        uint256 btcEquivalentExposure;
        uint256 receiptBalance;
        uint256 stakedReceiptBalance;
        uint256 claimableRewards;
        uint256 swapPriceImpactBps;
        uint256 slippageBps;
        bool principalMovementSupported;
        bool stakingSupported;
    }

    /// @notice Preview of a BTC sleeve deposit path.
    /// @param principalAsset ERC20-compatible BTC asset used as principal.
    /// @param pairedAsset BTC-correlated or non-BTC asset paired with principal.
    /// @param receiptAsset Receipt or LP token minted by the sleeve.
    /// @param rewardAsset Reward token, if known.
    /// @param btcAmount BTC principal amount considered by the preview.
    /// @param pairedAmount Paired asset amount required or expected.
    /// @param minPairedOut Minimum paired asset output for any pre-swap.
    /// @param minLiquidity Minimum receipt or LP tokens expected from deposit.
    /// @param estimatedLiquidity Estimated receipt or LP tokens from deposit.
    /// @param priceImpactBps Estimated price impact in basis points.
    /// @param slippageBps Slippage setting in basis points.
    struct BTCDepositPreview {
        address principalAsset;
        address pairedAsset;
        address receiptAsset;
        address rewardAsset;
        uint256 btcAmount;
        uint256 pairedAmount;
        uint256 minPairedOut;
        uint256 minLiquidity;
        uint256 estimatedLiquidity;
        uint256 priceImpactBps;
        uint256 slippageBps;
    }

    /// @notice Returns the ERC20-compatible BTC principal asset.
    function principalAsset() external view returns (address);

    /// @notice Returns the paired asset used by the BTC sleeve.
    function pairedAsset() external view returns (address);

    /// @notice Returns the sleeve receipt or LP token.
    function receiptAsset() external view returns (address);

    /// @notice Returns the reward token if the sleeve has one.
    function rewardAsset() external view returns (address);

    /// @notice Returns the BTC sleeve risk category.
    function riskClass() external view returns (BTCSleeveRiskClass);

    /// @notice Previews the treasury's current BTC-denominated exposure.
    /// @param treasury Treasury Account or owner whose exposure is being reported.
    /// @return exposure Structured BTC exposure report.
    function previewExposure(address treasury) external view returns (BTCExposure memory exposure);

    /// @notice Previews a BTC sleeve deposit path without moving principal.
    /// @param btcAmount BTC principal amount being considered.
    /// @return preview Structured BTC sleeve deposit preview.
    function previewDeposit(uint256 btcAmount) external view returns (BTCDepositPreview memory preview);
}
