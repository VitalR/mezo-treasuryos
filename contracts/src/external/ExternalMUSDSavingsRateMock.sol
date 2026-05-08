// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IMUSDSavingsRate } from "../interfaces/IMUSDSavingsRate.sol";

/// @title ExternalMUSDSavingsRateMock
/// @notice External savings-rate mock that mimics sMUSD principal and yield behavior with owner-funded yield.
/// @dev This contract is intended for local deterministic demos and tests only. It preserves the same user-facing
///      mental model as Mezo's savings vault:
///      1. MUSD principal is deposited and sMUSD receipts are minted 1:1.
///      2. Yield is distributed through a global `yieldIndex`.
///      3. Holders claim accumulated MUSD yield without changing principal balances.
///      It intentionally cannot be deployed on Mezo testnet now that the real MUSD Savings Vault is known.
contract ExternalMUSDSavingsRateMock is ERC20, Ownable, ReentrancyGuard, IMUSDSavingsRate {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // =============================================================
    // Constants
    // =============================================================

    /// @notice Mezo testnet chain ID where the real MUSD Savings Vault should be used instead.
    uint256 public constant MEZO_TESTNET_CHAIN_ID = 31_611;

    // =============================================================
    // Events
    // =============================================================

    /// @notice Emitted when a depositor contributes MUSD principal and receives sMUSD.
    /// @param user Depositor receiving the sMUSD receipts.
    /// @param amount Amount of MUSD principal deposited.
    event Deposit(address indexed user, uint256 amount);
    /// @notice Emitted when a depositor burns sMUSD and withdraws MUSD principal.
    /// @param user Withdrawer burning the sMUSD receipts.
    /// @param amount Amount of MUSD principal withdrawn.
    event Withdraw(address indexed user, uint256 amount);
    /// @notice Emitted when a depositor claims accrued MUSD yield.
    /// @param user Yield recipient.
    /// @param amount Amount of MUSD yield claimed.
    event YieldClaimed(address indexed user, uint256 amount);
    /// @notice Emitted when the owner funds mock yield into the vault.
    /// @param funder Address funding the demo yield.
    /// @param amount Amount of MUSD yield distributed or buffered.
    event YieldFunded(address indexed funder, uint256 amount);

    // =============================================================
    // Errors
    // =============================================================

    /// @notice Reverts when a user attempts to withdraw more sMUSD than owned.
    error InsufficientBalance();
    /// @notice Reverts when a user with no shares tries to claim yield.
    error NoShares();
    /// @notice Reverts when a required address is zero.
    error ZeroAddress();
    /// @notice Reverts when an amount is zero.
    error ZeroAmount();
    /// @notice Reverts when someone attempts to deploy the mock on Mezo testnet.
    error MockDisabledOnMezoTestnet();

    // =============================================================
    // Storage
    // =============================================================

    /// @notice Underlying MUSD token accepted as principal and paid as yield.
    IERC20 public immutable musdToken;
    /// @notice Global yield index scaled by `1e18` and used for pro-rata accrual.
    uint256 public yieldIndex;
    /// @notice Buffered yield held when total sMUSD supply is zero.
    uint256 public pendingYield;
    /// @notice Timestamp of the most recent owner-funded yield event.
    uint256 public lastYieldFundedAt;
    /// @notice Amount funded during the most recent owner-funded yield event.
    uint256 public lastYieldFundedAmount;

    /// @notice Claimable yield tracked per account after index synchronization.
    mapping(address account => uint256 amount) public claimableYield;
    /// @notice Last synchronized global yield index per account.
    mapping(address account => uint256 index) public supplyYieldIndex;

    // =============================================================
    // Constructor
    // =============================================================

    /// @param _owner Owner allowed to fund simulated yield.
    /// @param _musdToken Underlying MUSD token accepted by the vault.
    constructor(address _owner, IERC20 _musdToken) ERC20("External MUSD Savings Rate Mock", "sMUSD") Ownable(_owner) {
        require(block.chainid != MEZO_TESTNET_CHAIN_ID, MockDisabledOnMezoTestnet());
        require(address(_musdToken) != address(0), ZeroAddress());

        musdToken = _musdToken;
    }

    // =============================================================
    // External Functions
    // =============================================================

    /// @notice Deposits MUSD principal and mints 1:1 sMUSD receipt tokens.
    /// @param _amount Amount of MUSD principal deposited.
    function deposit(uint256 _amount) external nonReentrant {
        require(_amount > 0, ZeroAmount());

        musdToken.safeTransferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, _amount);

        emit Deposit(msg.sender, _amount);
    }

    /// @notice Withdraws MUSD principal by burning sMUSD and automatically claims pending yield first.
    /// @param _amount Amount of principal to withdraw.
    function withdraw(uint256 _amount) external nonReentrant {
        require(_amount > 0, ZeroAmount());
        require(balanceOf(msg.sender) >= _amount, InsufficientBalance());

        _claimYield(msg.sender);
        _burn(msg.sender, _amount);
        musdToken.safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _amount);
    }

    /// @inheritdoc IMUSDSavingsRate
    function claimYield() external nonReentrant returns (uint256 amount) {
        amount = _claimYield(msg.sender);
    }

    /// @inheritdoc IMUSDSavingsRate
    function yieldToken() external view returns (address) {
        return address(musdToken);
    }

    /// @inheritdoc IMUSDSavingsRate
    function balanceOf(address _account) public view override(ERC20, IMUSDSavingsRate) returns (uint256) {
        return super.balanceOf(_account);
    }

    /// @notice Funds demo yield using real MUSD already held by the owner and distributes it pro-rata to sMUSD holders.
    /// @param _amount Amount of MUSD yield to transfer into the vault and distribute.
    function fundYield(uint256 _amount) external onlyOwner nonReentrant {
        require(_amount > 0, ZeroAmount());

        musdToken.safeTransferFrom(msg.sender, address(this), _amount);
        _receiveYield(_amount);
        lastYieldFundedAt = block.timestamp;
        lastYieldFundedAmount = _amount;

        emit YieldFunded(msg.sender, _amount);
    }

    /// @notice Quotes the MUSD yield required to simulate a target annual rate over a given elapsed period.
    /// @dev This is useful for demo flows that want to approximate the public MUSD savings-rate presentation,
    ///      for example funding a weekly 5% annualized yield increment.
    /// @param _annualRateBps Target annualized rate in basis points. For 5%, pass `500`.
    /// @param _elapsedSeconds Elapsed accrual window to simulate. For a weekly step, pass `7 days`.
    /// @return amount Amount of MUSD yield that should be funded for the current total supply.
    function quoteYieldForAnnualRateBps(uint256 _annualRateBps, uint256 _elapsedSeconds)
        public
        view
        returns (uint256 amount)
    {
        require(_annualRateBps > 0, ZeroAmount());
        require(_elapsedSeconds > 0, ZeroAmount());

        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return 0;
        }

        amount = _totalSupply.mulDiv(_annualRateBps * _elapsedSeconds, 10_000 * 365 days);
    }

    /// @notice Funds demo yield using an annualized rate target rather than a raw amount.
    /// @dev The owner must hold and approve enough MUSD for the quoted amount. If total supply is zero,
    ///      this function funds nothing and returns zero.
    /// @param _annualRateBps Target annualized rate in basis points. For 5%, pass `500`.
    /// @param _elapsedSeconds Elapsed accrual window to simulate.
    /// @return amount Amount of MUSD funded into the mock vault.
    function fundYieldForAnnualRateBps(uint256 _annualRateBps, uint256 _elapsedSeconds)
        external
        onlyOwner
        nonReentrant
        returns (uint256 amount)
    {
        amount = quoteYieldForAnnualRateBps(_annualRateBps, _elapsedSeconds);

        if (amount == 0) {
            return 0;
        }

        musdToken.safeTransferFrom(msg.sender, address(this), amount);
        _receiveYield(amount);
        lastYieldFundedAt = block.timestamp;
        lastYieldFundedAmount = amount;

        emit YieldFunded(msg.sender, amount);
    }

    // =============================================================
    // Internal Functions
    // =============================================================

    /// @notice Claims yield for a specific account after synchronizing its accrual.
    /// @param _account Account whose claimable yield should be paid out.
    /// @return amount Amount of MUSD yield transferred to the account.
    function _claimYield(address _account) internal returns (uint256 amount) {
        require(balanceOf(_account) > 0, NoShares());

        _updateYieldFor(_account);

        amount = claimableYield[_account];
        if (amount > 0) {
            claimableYield[_account] = 0;
            musdToken.safeTransfer(_account, amount);
            emit YieldClaimed(_account, amount);
        }
    }

    /// @notice Receives new yield and updates the global yield index or buffers the yield when supply is zero.
    /// @param _amount Yield amount being funded.
    function _receiveYield(uint256 _amount) internal {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply > 0) {
            uint256 _distributedYield = _amount + pendingYield;
            pendingYield = 0;

            uint256 _ratio = (_distributedYield * 1e18) / _totalSupply;
            if (_ratio > 0) {
                yieldIndex += _ratio;
            }
            return;
        }

        pendingYield += _amount;
    }

    /// @notice Synchronizes the account's claimable yield using the global yield index.
    /// @param _account Account whose accrual should be updated.
    function _updateYieldFor(address _account) internal {
        uint256 _supplied = balanceOf(_account);
        uint256 _currentYieldIndex = yieldIndex;
        uint256 _accountYieldIndex = supplyYieldIndex[_account];

        supplyYieldIndex[_account] = _currentYieldIndex;

        if (_supplied == 0) {
            return;
        }

        uint256 _delta = _currentYieldIndex - _accountYieldIndex;
        if (_delta > 0) {
            claimableYield[_account] += (_supplied * _delta) / 1e18;
        }
    }

    /// @notice Updates yield accrual for both sides of a transfer before the ERC20 balances change.
    /// @param _from Sender in the token transfer.
    /// @param _to Receiver in the token transfer.
    /// @param _value Amount of sMUSD transferred.
    function _update(address _from, address _to, uint256 _value) internal override {
        _updateYieldFor(_from);
        _updateYieldFor(_to);
        super._update(_from, _to, _value);
    }
}
