// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TreasuryAccount } from "./TreasuryAccount.sol";
import { ITreasuryPolicyEngine } from "../interfaces/ITreasuryPolicyEngine.sol";

/// @title TreasuryAccountFactory
/// @notice Deploys and initializes client-isolated Treasury Accounts.
contract TreasuryAccountFactory {
    /// @notice Emitted when a new Treasury Account is deployed.
    event TreasuryAccountDeployed(
        address indexed treasuryAccount, address indexed treasuryAdmin, address indexed operator, address approver
    );

    error InvalidPolicyEngine(address policyEngine);
    error InvalidMUSDToken(address musdToken);
    error InvalidTreasuryAdmin(address treasuryAdmin);

    IERC20 public immutable musdToken;
    ITreasuryPolicyEngine public immutable policyEngine;

    /// @param _musdToken MUSD token used by Treasury Accounts for repayment and destination allocations.
    /// @param _policyEngine Policy engine used for Treasury Account initialization.
    constructor(IERC20 _musdToken, ITreasuryPolicyEngine _policyEngine) {
        require(address(_musdToken) != address(0), InvalidMUSDToken(address(_musdToken)));
        require(address(_policyEngine) != address(0), InvalidPolicyEngine(address(_policyEngine)));

        musdToken = _musdToken;
        policyEngine = _policyEngine;
        _policyEngine.setFactory(address(this));
    }

    /// @notice Deploys a new Treasury Account for a treasury/client.
    /// @param _treasuryAdmin Treasury administrator for the new account.
    /// @param _config Initial policy configuration applied to the account.
    /// @return treasuryAccount Newly deployed Treasury Account address.
    function deployTreasuryAccount(address _treasuryAdmin, ITreasuryPolicyEngine.AccountPolicyConfig calldata _config)
        external
        returns (address treasuryAccount)
    {
        require(_treasuryAdmin != address(0), InvalidTreasuryAdmin(_treasuryAdmin));

        TreasuryAccount account = new TreasuryAccount(_treasuryAdmin, policyEngine, musdToken);
        treasuryAccount = address(account);

        policyEngine.initializeAccount(treasuryAccount, _treasuryAdmin, _config);

        emit TreasuryAccountDeployed(treasuryAccount, _treasuryAdmin, _config.operator, _config.approver);
    }
}
