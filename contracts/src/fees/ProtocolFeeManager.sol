// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ProtocolFeeManager
/// @notice Governance-controlled TreasuryOS fee configuration and lightweight subscription collection.
/// @dev Fee quoting is intentionally advisory until downstream flows explicitly wire in fee settlement.
contract ProtocolFeeManager is Ownable2Step {
    using SafeERC20 for IERC20;

    // =============================================================
    // Constants
    // =============================================================

    /// @notice Basis-point denominator.
    uint256 public constant BPS_DENOMINATOR = 10_000;
    /// @notice Maximum performance fee on realized positive yield: 3%.
    uint16 public constant MAX_PERFORMANCE_FEE_BPS = 300;
    /// @notice Maximum origination fee on explicitly fee-enabled borrow flows: 0.25%.
    uint16 public constant MAX_ORIGINATION_FEE_BPS = 25;
    /// @notice Maximum optimization action fee on explicitly fee-enabled non-emergency actions: 0.05%.
    uint16 public constant MAX_OPTIMIZATION_ACTION_FEE_BPS = 5;
    /// @notice Fee type used for performance-fee cap validation.
    bytes32 public constant PERFORMANCE_FEE_TYPE = keccak256("PERFORMANCE_FEE");
    /// @notice Fee type used for origination-fee cap validation.
    bytes32 public constant ORIGINATION_FEE_TYPE = keccak256("ORIGINATION_FEE");
    /// @notice Fee type used for optimization-action-fee cap validation.
    bytes32 public constant OPTIMIZATION_ACTION_FEE_TYPE = keccak256("OPTIMIZATION_ACTION_FEE");
    /// @notice Fee type used for explicit subscription payments.
    bytes32 public constant SUBSCRIPTION_FEE_TYPE = keccak256("SUBSCRIPTION_FEE");
    /// @notice Fee type used for generic basis-point quote validation.
    bytes32 public constant BPS_QUOTE_FEE_TYPE = keccak256("BPS_QUOTE_FEE");

    // =============================================================
    // Events
    // =============================================================

    /// @notice Emitted when governance updates the fee configuration.
    /// @param feeVault Protocol vault contract that receives fees.
    /// @param feesEnabled Global fee quoting/payment switch.
    /// @param performanceFeeBps Performance fee on realized positive yield.
    /// @param originationFeeBps Optional origination fee.
    /// @param optimizationActionFeeBps Optional optimization action fee.
    event FeeConfigUpdated(
        address indexed feeVault,
        bool feesEnabled,
        uint16 performanceFeeBps,
        uint16 originationFeeBps,
        uint16 optimizationActionFeeBps
    );
    /// @notice Emitted when a payer explicitly pays a subscription/service fee.
    /// @param payer Account paying the subscription.
    /// @param treasury Treasury account or client identifier being serviced.
    /// @param token ERC20 payment token.
    /// @param amount Amount paid.
    /// @param period Accounting period identifier.
    /// @param feeVault Protocol vault that received payment.
    event SubscriptionPaid(
        address indexed payer,
        address indexed treasury,
        address indexed token,
        uint256 amount,
        bytes32 period,
        address feeVault
    );
    /// @notice Emitted when a payer explicitly pays a native BTC subscription/service fee.
    /// @param payer Account paying the subscription.
    /// @param treasury Treasury account or client identifier being serviced.
    /// @param amount Native BTC amount paid.
    /// @param period Accounting period identifier.
    /// @param feeVault Protocol vault that received payment.
    event NativeSubscriptionPaid(
        address indexed payer, address indexed treasury, uint256 amount, bytes32 period, address feeVault
    );
    /// @notice Emitted when governance updates whether a token is accepted for subscription payments.
    /// @param token ERC20 token whose payment eligibility changed.
    /// @param accepted Whether the token is accepted for subscription payments.
    event AcceptedSubscriptionTokenUpdated(address indexed token, bool accepted);

    // =============================================================
    // Errors
    // =============================================================

    /// @notice Raised when the configured fee vault is zero or not a contract.
    /// @param feeVault Invalid fee vault.
    error InvalidFeeVault(address feeVault);
    /// @notice Raised when a fee exceeds its hard cap.
    /// @param feeType Fee category.
    /// @param feeBps Attempted fee in basis points.
    /// @param maxFeeBps Maximum allowed fee in basis points.
    error FeeBpsAboveCap(bytes32 feeType, uint256 feeBps, uint256 maxFeeBps);
    /// @notice Raised when an explicit subscription treasury reference is zero.
    /// @param treasury Invalid treasury reference.
    error InvalidTreasury(address treasury);
    /// @notice Raised when an ERC20 payment token is zero.
    /// @param token Invalid token address.
    error InvalidToken(address token);
    /// @notice Raised when an amount is zero.
    /// @param amount Invalid amount.
    error InvalidAmount(uint256 amount);
    /// @notice Raised when a fee-payment path is called while fees are disabled.
    error FeesDisabled();
    /// @notice Raised when an ERC20 token is not accepted for subscription payments.
    /// @param token Rejected token address.
    error SubscriptionTokenNotAccepted(address token);
    /// @notice Raised when forwarding a native BTC subscription payment to the fee vault fails.
    /// @param feeVault Protocol vault that rejected or failed the payment.
    /// @param amount Native BTC amount attempted.
    error NativeSubscriptionForwardFailed(address feeVault, uint256 amount);

    // =============================================================
    // Storage
    // =============================================================

    /// @notice Protocol vault contract that receives all explicit fee payments.
    address public feeVault;
    /// @notice Global switch for fee quotes and explicit subscription payments.
    bool public feesEnabled;
    /// @notice Performance fee on realized positive yield.
    uint16 public performanceFeeBps;
    /// @notice Optional origination fee.
    uint16 public originationFeeBps;
    /// @notice Optional optimization action fee for non-emergency optimization workflows.
    uint16 public optimizationActionFeeBps;
    /// @notice ERC20 tokens accepted for subscription/service payments.
    mapping(address token => bool accepted) public acceptedSubscriptionToken;

    // =============================================================
    // Constructor
    // =============================================================

    /// @param _owner Governance/admin owner of the protocol fee manager.
    /// @param _feeVault Protocol vault contract that receives fees.
    constructor(address _owner, address _feeVault) Ownable(_owner) {
        _setFeeConfig(_feeVault, false, 0, 0, 0);
    }

    // =============================================================
    // External Functions
    // =============================================================

    /// @notice Updates all fee settings under hard protocol caps.
    /// @param _feeVault Protocol vault contract that receives fees.
    /// @param _feesEnabled Global fee quoting/payment switch.
    /// @param _performanceFeeBps Performance fee on realized positive yield.
    /// @param _originationFeeBps Optional origination fee.
    /// @param _optimizationActionFeeBps Optional optimization action fee.
    function setFeeConfig(
        address _feeVault,
        bool _feesEnabled,
        uint16 _performanceFeeBps,
        uint16 _originationFeeBps,
        uint16 _optimizationActionFeeBps
    ) external onlyOwner {
        _setFeeConfig(_feeVault, _feesEnabled, _performanceFeeBps, _originationFeeBps, _optimizationActionFeeBps);
    }

    /// @notice Sets whether an ERC20 token is accepted for subscription/service payments.
    /// @param _token ERC20 token whose payment eligibility is updated.
    /// @param _accepted Whether the token is accepted.
    function setAcceptedSubscriptionToken(IERC20 _token, bool _accepted) external onlyOwner {
        require(address(_token) != address(0), InvalidToken(address(_token)));

        acceptedSubscriptionToken[address(_token)] = _accepted;

        emit AcceptedSubscriptionTokenUpdated(address(_token), _accepted);
    }

    /// @notice Quotes the performance fee on realized positive yield only.
    /// @param _principal Principal amount initially deployed.
    /// @param _returnedAmount Amount returned from the yield/optimization path.
    /// @return fee Performance fee amount, or zero when disabled, flat, or loss-making.
    function quotePerformanceFee(uint256 _principal, uint256 _returnedAmount) external view returns (uint256 fee) {
        if (!feesEnabled || performanceFeeBps == 0 || _returnedAmount <= _principal) {
            return 0;
        }

        fee = _calculateBpsFee(_returnedAmount - _principal, performanceFeeBps);
    }

    /// @notice Quotes a generic basis-point fee and returns zero while fees are disabled.
    /// @param _amount Amount being charged.
    /// @param _bps Fee in basis points.
    /// @return fee Quoted fee amount.
    function quoteBpsFee(uint256 _amount, uint256 _bps) public view returns (uint256 fee) {
        if (!feesEnabled || _amount == 0 || _bps == 0) {
            return 0;
        }

        require(_bps <= BPS_DENOMINATOR, FeeBpsAboveCap(BPS_QUOTE_FEE_TYPE, _bps, BPS_DENOMINATOR));

        fee = _calculateBpsFee(_amount, _bps);
    }

    /// @notice Quotes the configured origination fee.
    /// @param _amount Amount being originated.
    /// @return fee Quoted origination fee.
    function quoteOriginationFee(uint256 _amount) external view returns (uint256 fee) {
        fee = quoteBpsFee(_amount, originationFeeBps);
    }

    /// @notice Quotes the configured optimization action fee.
    /// @param _amount Amount being optimized.
    /// @return fee Quoted optimization action fee.
    function quoteOptimizationActionFee(uint256 _amount) external view returns (uint256 fee) {
        fee = quoteBpsFee(_amount, optimizationActionFeeBps);
    }

    /// @notice Explicitly pays a subscription/service fee to the protocol vault.
    /// @dev This is not called by emergency defense flows and does not skim treasury principal.
    /// @param _treasury Treasury account or client identifier being serviced.
    /// @param _token ERC20 payment token.
    /// @param _amount Token amount paid.
    /// @param _period Accounting period identifier, e.g. bytes32("2026-05").
    function paySubscription(address _treasury, IERC20 _token, uint256 _amount, bytes32 _period) external {
        if (!feesEnabled) revert FeesDisabled();
        require(_treasury != address(0), InvalidTreasury(_treasury));
        require(address(_token) != address(0), InvalidToken(address(_token)));
        require(_amount > 0, InvalidAmount(_amount));
        require(acceptedSubscriptionToken[address(_token)], SubscriptionTokenNotAccepted(address(_token)));

        _token.safeTransferFrom(msg.sender, feeVault, _amount);

        emit SubscriptionPaid(msg.sender, _treasury, address(_token), _amount, _period, feeVault);
    }

    /// @notice Explicitly pays a native BTC subscription/service fee to the protocol vault.
    /// @dev This emits only the manager-level subscription event; the vault receive path intentionally does not emit
    ///      FeeReceived so indexers do not double-classify subscription payments as direct vault deposits.
    /// @param _treasury Treasury account or client identifier being serviced.
    /// @param _period Accounting period identifier, e.g. bytes32("2026-05").
    function payNativeSubscription(address _treasury, bytes32 _period) external payable {
        if (!feesEnabled) revert FeesDisabled();
        require(_treasury != address(0), InvalidTreasury(_treasury));
        require(msg.value > 0, InvalidAmount(msg.value));

        (bool success,) = payable(feeVault).call{ value: msg.value }("");
        require(success, NativeSubscriptionForwardFailed(feeVault, msg.value));

        emit NativeSubscriptionPaid(msg.sender, _treasury, msg.value, _period, feeVault);
    }

    // =============================================================
    // Internal Functions
    // =============================================================

    /// @notice Updates storage after validating the vault and fee caps.
    function _setFeeConfig(
        address _feeVault,
        bool _feesEnabled,
        uint16 _performanceFeeBps,
        uint16 _originationFeeBps,
        uint16 _optimizationActionFeeBps
    ) internal {
        _requireFeeVault(_feeVault);
        _requireFeeCap(PERFORMANCE_FEE_TYPE, _performanceFeeBps, MAX_PERFORMANCE_FEE_BPS);
        _requireFeeCap(ORIGINATION_FEE_TYPE, _originationFeeBps, MAX_ORIGINATION_FEE_BPS);
        _requireFeeCap(OPTIMIZATION_ACTION_FEE_TYPE, _optimizationActionFeeBps, MAX_OPTIMIZATION_ACTION_FEE_BPS);

        feeVault = _feeVault;
        feesEnabled = _feesEnabled;
        performanceFeeBps = _performanceFeeBps;
        originationFeeBps = _originationFeeBps;
        optimizationActionFeeBps = _optimizationActionFeeBps;

        emit FeeConfigUpdated(
            _feeVault, _feesEnabled, _performanceFeeBps, _originationFeeBps, _optimizationActionFeeBps
        );
    }

    /// @notice Enforces that fee payments route to a contract vault, not an EOA.
    /// @param _feeVault Proposed protocol fee vault.
    function _requireFeeVault(address _feeVault) internal view {
        require(_feeVault != address(0) && _feeVault.code.length > 0, InvalidFeeVault(_feeVault));
    }

    /// @notice Enforces per-fee hard caps.
    function _requireFeeCap(bytes32 _feeType, uint256 _feeBps, uint256 _maxFeeBps) internal pure {
        require(_feeBps <= _maxFeeBps, FeeBpsAboveCap(_feeType, _feeBps, _maxFeeBps));
    }

    /// @notice Calculates a basis-point fee using floor rounding.
    function _calculateBpsFee(uint256 _amount, uint256 _bps) internal pure returns (uint256) {
        return (_amount * _bps) / BPS_DENOMINATOR;
    }
}
