// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title IBTCReserveHandler
/// @notice Executable handler interface for guarded BTC-denominated sleeve actions.
/// @dev BTC reserve handlers are separate from MUSD allocation handlers because they operate on BTC-principal
///      accounting, require owner/multisig initiation, and must not affect MUSD liquidity-buffer state.
interface IBTCReserveHandler {
    /// @notice BTC sleeve entry request with explicit route and liquidity safety bounds.
    /// @param btcAmount Total idle BTC principal considered for the sleeve.
    /// @param btcToSwap Portion of BTC swapped into the paired BTC-correlated asset before LP entry.
    /// @param minPairedOut Minimum paired asset amount required from the pre-swap.
    /// @param minBTCUsed Minimum BTC amount that must be consumed by add-liquidity.
    /// @param minPairedUsed Minimum paired asset amount that must be consumed by add-liquidity.
    /// @param minLiquidity Minimum LP tokens required from add-liquidity.
    struct BTCDepositRequest {
        uint256 btcAmount;
        uint256 btcToSwap;
        uint256 minPairedOut;
        uint256 minBTCUsed;
        uint256 minPairedUsed;
        uint256 minLiquidity;
    }

    /// @notice BTC sleeve entry result.
    /// @param pairedReceived Paired asset amount received from the pre-swap.
    /// @param btcUsed BTC amount consumed by add-liquidity.
    /// @param pairedUsed Paired asset amount consumed by add-liquidity.
    /// @param liquidityMinted LP tokens minted to the Treasury Account.
    /// @param unusedBTC BTC principal left unused and returned to idle accounting.
    /// @param unusedPaired Paired asset left in the Treasury Account after add-liquidity.
    struct BTCDepositResult {
        uint256 pairedReceived;
        uint256 btcUsed;
        uint256 pairedUsed;
        uint256 liquidityMinted;
        uint256 unusedBTC;
        uint256 unusedPaired;
    }

    /// @notice BTC sleeve exit request with explicit remove-liquidity and optional swap-back safety bounds.
    /// @param liquidity LP tokens to burn.
    /// @param principalReductionBTC BTC-principal accounting amount reduced by this exit.
    /// @param minPairedOut Minimum paired asset amount required from remove-liquidity.
    /// @param minBTCOut Minimum BTC amount required directly from remove-liquidity.
    /// @param swapPairedToBTC Whether to swap the paired asset back into BTC after removal.
    /// @param minBTCFromPaired Minimum BTC output required from the paired-asset swap-back.
    struct BTCWithdrawRequest {
        uint256 liquidity;
        uint256 principalReductionBTC;
        uint256 minPairedOut;
        uint256 minBTCOut;
        bool swapPairedToBTC;
        uint256 minBTCFromPaired;
    }

    /// @notice BTC sleeve exit result.
    /// @param pairedReceived Paired asset amount received from remove-liquidity.
    /// @param btcReceived BTC amount received directly from remove-liquidity.
    /// @param btcFromPairedSwap BTC amount received from optional paired-asset swap-back.
    /// @param principalReductionBTC BTC-principal accounting amount reduced by this exit.
    struct BTCWithdrawResult {
        uint256 pairedReceived;
        uint256 btcReceived;
        uint256 btcFromPairedSwap;
        uint256 principalReductionBTC;
    }

    /// @notice Returns the BTC sleeve destination managed by this handler.
    function destination() external view returns (address);

    /// @notice Routes a guarded BTC sleeve entry.
    /// @param _treasuryAccount Treasury Account providing idle BTC and receiving receipt tokens.
    /// @param _actor Treasury owner/multisig initiating the routed action.
    /// @param _request Explicit execution bounds for the BTC sleeve entry.
    /// @return result Structured BTC sleeve entry result.
    function deposit(address _treasuryAccount, address _actor, BTCDepositRequest calldata _request)
        external
        returns (BTCDepositResult memory result);

    /// @notice Routes a guarded BTC sleeve exit.
    /// @param _treasuryAccount Treasury Account owning receipt tokens and receiving BTC.
    /// @param _actor Treasury owner/multisig initiating the routed action.
    /// @param _request Explicit execution bounds for the BTC sleeve exit.
    /// @return result Structured BTC sleeve exit result.
    function withdraw(address _treasuryAccount, address _actor, BTCWithdrawRequest calldata _request)
        external
        returns (BTCWithdrawResult memory result);
}
