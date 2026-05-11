// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ProtocolFeeVault
/// @notice Protocol-owned fee receiver for native BTC and ERC20-denominated TreasuryOS fees.
/// @dev This contract is the fee receiver. Fee-producing flows should route here instead of to an EOA.
contract ProtocolFeeVault is Ownable2Step {
    using SafeERC20 for IERC20;

    // =============================================================
    // Constants
    // =============================================================

    /// @notice Address sentinel used in events for native BTC.
    address public constant NATIVE_TOKEN = address(0);
    /// @notice Default fee type for direct native transfers.
    bytes32 public constant DIRECT_NATIVE_FEE_TYPE = keccak256("DIRECT_NATIVE_FEE");
    /// @notice Default fee type for direct ERC20 deposits.
    bytes32 public constant DIRECT_ERC20_FEE_TYPE = keccak256("DIRECT_ERC20_FEE");

    // =============================================================
    // Events
    // =============================================================

    /// @notice Emitted when the vault receives a fee payment.
    /// @param payer Account that funded the payment.
    /// @param token ERC20 token address, or address(0) for native BTC.
    /// @param amount Amount received.
    /// @param feeType Accounting label for the payment source.
    event FeeReceived(address indexed payer, address indexed token, uint256 amount, bytes32 indexed feeType);
    /// @notice Emitted when protocol governance withdraws accumulated fees.
    /// @param recipient Contract recipient that received the withdrawal.
    /// @param token ERC20 token address, or address(0) for native BTC.
    /// @param amount Amount withdrawn.
    event FeeWithdrawn(address indexed recipient, address indexed token, uint256 amount);

    // =============================================================
    // Errors
    // =============================================================

    /// @notice Raised when an amount is zero.
    /// @param amount Invalid amount.
    error InvalidAmount(uint256 amount);
    /// @notice Raised when a token address is zero for an ERC20 operation.
    /// @param token Invalid token address.
    error InvalidToken(address token);
    /// @notice Raised when a withdrawal recipient is zero or not a contract.
    /// @param recipient Invalid recipient address.
    error InvalidWithdrawalRecipient(address recipient);
    /// @notice Raised when a native BTC withdrawal call fails.
    /// @param recipient Recipient that rejected or failed the transfer.
    /// @param amount Amount attempted.
    error NativeWithdrawalFailed(address recipient, uint256 amount);

    // =============================================================
    // Constructor
    // =============================================================

    /// @param _owner Governance/admin owner of the protocol fee vault.
    constructor(address _owner) Ownable(_owner) { }

    // =============================================================
    // Receive Native BTC
    // =============================================================

    /// @notice Accepts native BTC without metadata. Use depositNative for indexable direct fee deposits.
    receive() external payable { }

    // =============================================================
    // External Functions
    // =============================================================

    /// @notice Deposits a native BTC fee payment into the vault with structured accounting metadata.
    /// @param _feeType Accounting label for the payment source.
    function depositNative(bytes32 _feeType) external payable {
        require(msg.value > 0, InvalidAmount(msg.value));

        emit FeeReceived(msg.sender, NATIVE_TOKEN, msg.value, _feeType);
    }

    /// @notice Deposits an ERC20 fee payment into the vault and emits structured accounting metadata.
    /// @param _token ERC20 token paid.
    /// @param _amount Token amount paid.
    /// @param _feeType Accounting label for the payment source.
    function depositERC20(IERC20 _token, uint256 _amount, bytes32 _feeType) external {
        require(address(_token) != address(0), InvalidToken(address(_token)));
        require(_amount > 0, InvalidAmount(_amount));

        _token.safeTransferFrom(msg.sender, address(this), _amount);

        emit FeeReceived(msg.sender, address(_token), _amount, _feeType);
    }

    /// @notice Withdraws native BTC fees to a protocol treasury/custody contract.
    /// @param _to Contract recipient that receives the withdrawal.
    /// @param _amount Native BTC amount withdrawn.
    function withdrawNative(address payable _to, uint256 _amount) external onlyOwner {
        _requireContractRecipient(_to);
        require(_amount > 0, InvalidAmount(_amount));

        (bool success,) = _to.call{ value: _amount }("");
        require(success, NativeWithdrawalFailed(_to, _amount));

        emit FeeWithdrawn(_to, NATIVE_TOKEN, _amount);
    }

    /// @notice Withdraws ERC20 fees to a protocol treasury/custody contract.
    /// @param _token ERC20 token withdrawn.
    /// @param _to Contract recipient that receives the withdrawal.
    /// @param _amount Token amount withdrawn.
    function withdrawERC20(IERC20 _token, address _to, uint256 _amount) external onlyOwner {
        require(address(_token) != address(0), InvalidToken(address(_token)));
        _requireContractRecipient(_to);
        require(_amount > 0, InvalidAmount(_amount));

        _token.safeTransfer(_to, _amount);

        emit FeeWithdrawn(_to, address(_token), _amount);
    }

    // =============================================================
    // Internal Functions
    // =============================================================

    /// @notice Enforces that withdrawals go to a contract treasury/custody recipient rather than an EOA.
    /// @param _recipient Withdrawal recipient.
    function _requireContractRecipient(address _recipient) internal view {
        require(_recipient != address(0) && _recipient.code.length > 0, InvalidWithdrawalRecipient(_recipient));
    }
}
