// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import { TreasuryAccount } from "./TreasuryAccount.sol";
import { ITreasuryPolicyEngine } from "../interfaces/ITreasuryPolicyEngine.sol";

/// @title TreasuryAccountFactory
/// @notice Deploys and initializes client-isolated Treasury Accounts recognized by TreasuryOS.
contract TreasuryAccountFactory is Ownable2Step, Pausable {
    // =============================================================
    // Events
    // =============================================================

    /// @notice Emitted when a treasury administrator is approved or revoked for official TreasuryOS onboarding.
    event TreasuryAdminApprovalUpdated(address indexed treasuryAdmin, bool approved);
    /// @notice Emitted when a new Treasury Account is deployed.
    event TreasuryAccountDeployed(
        address indexed treasuryAccount,
        address indexed treasuryAdmin,
        address indexed deployer,
        address operator,
        address approver
    );

    // =============================================================
    // Errors
    // =============================================================

    /// @notice Raised when the caller is not permitted to deploy an official Treasury Account for the admin.
    /// @param caller Caller attempting the deployment.
    /// @param treasuryAdmin Treasury administrator configured for the new account.
    error UnauthorizedDeployer(address caller, address treasuryAdmin);
    /// @notice Raised when the policy engine address is zero.
    /// @param policyEngine Invalid policy engine address.
    error InvalidPolicyEngine(address policyEngine);
    /// @notice Raised when the MUSD token address is zero.
    /// @param musdToken Invalid MUSD token address.
    error InvalidMUSDToken(address musdToken);
    /// @notice Raised when the treasury administrator address is zero.
    /// @param treasuryAdmin Invalid treasury administrator address.
    error InvalidTreasuryAdmin(address treasuryAdmin);
    /// @notice Raised when a treasury administrator has not been approved for official TreasuryOS onboarding.
    /// @param treasuryAdmin Treasury administrator that is not allowlisted.
    error TreasuryAdminNotApproved(address treasuryAdmin);
    /// @notice Raised when the Treasury Account implementation address is zero.
    /// @param accountImplementation Invalid implementation address.
    error InvalidAccountImplementation(address accountImplementation);

    // =============================================================
    // Storage
    // =============================================================

    /// @notice MUSD token used by Treasury Accounts for repayment and destination allocations.
    IERC20 public immutable musdToken;
    /// @notice Policy engine used for Treasury Account initialization and policy enforcement.
    ITreasuryPolicyEngine public immutable policyEngine;
    /// @notice Implementation cloned for each client Treasury Account.
    address public immutable accountImplementation;
    /// @notice Treasury administrators approved for official TreasuryOS account deployment.
    mapping(address treasuryAdmin => bool approved) public approvedTreasuryAdmins;
    /// @notice Registry of Treasury Accounts officially deployed through this factory.
    mapping(address treasuryAccount => bool registered) public isTreasuryAccount;

    // =============================================================
    // Constructor
    // =============================================================

    /// @param _musdToken MUSD token used by Treasury Accounts for repayment and destination allocations.
    /// @param _policyEngine Policy engine used for Treasury Account initialization.
    /// @param _accountImplementation Treasury Account implementation used for minimal proxies.
    constructor(IERC20 _musdToken, ITreasuryPolicyEngine _policyEngine, address _accountImplementation)
        Ownable(msg.sender)
    {
        require(address(_musdToken) != address(0), InvalidMUSDToken(address(_musdToken)));
        require(address(_policyEngine) != address(0), InvalidPolicyEngine(address(_policyEngine)));
        require(_accountImplementation != address(0), InvalidAccountImplementation(_accountImplementation));

        musdToken = _musdToken;
        policyEngine = _policyEngine;
        accountImplementation = _accountImplementation;
        _policyEngine.setFactory(address(this));
    }

    // =============================================================
    // External Functions
    // =============================================================

    /// @notice Approves or revokes a treasury administrator for official TreasuryOS onboarding.
    /// @param _treasuryAdmin Treasury administrator being updated.
    /// @param _approved New approval state.
    function setTreasuryAdminApproval(address _treasuryAdmin, bool _approved) external onlyOwner {
        require(_treasuryAdmin != address(0), InvalidTreasuryAdmin(_treasuryAdmin));

        approvedTreasuryAdmins[_treasuryAdmin] = _approved;

        emit TreasuryAdminApprovalUpdated(_treasuryAdmin, _approved);
    }

    /// @notice Pauses official Treasury Account deployment without affecting existing accounts.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses official Treasury Account deployment.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Deploys a new Treasury Account for a treasury/client.
    /// @dev The caller must either be the approved treasury administrator or the factory owner acting on their behalf.
    /// @param _treasuryAdmin Treasury administrator for the new account.
    /// @param _config Initial policy configuration applied to the account.
    /// @return treasuryAccount Newly deployed Treasury Account address.
    function deployTreasuryAccount(address _treasuryAdmin, ITreasuryPolicyEngine.AccountPolicyConfig calldata _config)
        external
        whenNotPaused
        returns (address treasuryAccount)
    {
        require(_treasuryAdmin != address(0), InvalidTreasuryAdmin(_treasuryAdmin));
        require(approvedTreasuryAdmins[_treasuryAdmin], TreasuryAdminNotApproved(_treasuryAdmin));
        require(msg.sender == _treasuryAdmin || msg.sender == owner(), UnauthorizedDeployer(msg.sender, _treasuryAdmin));

        treasuryAccount = Clones.clone(accountImplementation);
        TreasuryAccount(payable(treasuryAccount)).initialize(_treasuryAdmin, policyEngine, musdToken);

        policyEngine.initializeAccount(treasuryAccount, _treasuryAdmin, _config);
        isTreasuryAccount[treasuryAccount] = true;

        emit TreasuryAccountDeployed(treasuryAccount, _treasuryAdmin, msg.sender, _config.operator, _config.approver);
    }
}
