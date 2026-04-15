// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IBorrowerOperations } from "../../src/interfaces/IBorrowerOperations.sol";
import { IGovernableVariables } from "../../src/interfaces/IGovernableVariables.sol";

contract MockBorrowerOperations is IBorrowerOperations {
    uint256 public totalCollateral;
    uint256 public totalDebtPrincipal;
    uint256 public borrowingFee = 1 ether;

    uint256 public lastCollateralDeposit;
    uint256 public lastCollateralWithdrawal;
    uint256 public lastDebtChange;
    bool public lastDebtIncrease;
    address public lastUpperHint;
    address public lastLowerHint;
    bytes32 public lastAction;
    IGovernableVariables public governableVariables;

    receive() external payable { }

    function setGovernableVariables(IGovernableVariables _governableVariables) external {
        governableVariables = _governableVariables;
    }

    function setBorrowingFee(uint256 _borrowingFee) external {
        borrowingFee = _borrowingFee;
    }

    function setAddresses(address[13] memory) external { }

    function setRefinancingFeePercentage(uint8) external { }

    function getBorrowingFee(uint256) external view returns (uint256) {
        return borrowingFee;
    }

    function getRedemptionRate(uint256) external pure returns (uint256) {
        return 0;
    }

    function minNetDebt() external pure returns (uint256) {
        return 0;
    }

    function openTrove(uint256 _musdAmount, address _upperHint, address _lowerHint) external payable {
        _openTrove(_musdAmount, _upperHint, _lowerHint, msg.value);
    }

    function restrictedOpenTrove(address, address, uint256 _debtAmount, address _upperHint, address _lowerHint)
        external
        payable
    {
        _openTrove(_debtAmount, _upperHint, _lowerHint, msg.value);
    }

    function proposeMinNetDebt(uint256) external { }

    function approveMinNetDebt() external { }

    function proposeBorrowingRate(uint256) external { }

    function approveBorrowingRate() external { }

    function proposeRedemptionRate(uint256) external { }

    function approveRedemptionRate() external { }

    function adjustTrove(
        uint256 _collWithdrawal,
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint
    ) external payable {
        _adjustTrove(
            _collWithdrawal, _debtChange, _isDebtIncrease, _upperHint, _lowerHint, msg.value, payable(msg.sender)
        );
    }

    function restrictedAdjustTrove(
        address,
        address _recipient,
        address,
        uint256 _collWithdrawal,
        uint256 _mUSDChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint
    ) external payable {
        _adjustTrove(
            _collWithdrawal, _mUSDChange, _isDebtIncrease, _upperHint, _lowerHint, msg.value, payable(_recipient)
        );
    }

    function addColl(address _upperHint, address _lowerHint) external payable {
        _addColl(_upperHint, _lowerHint, msg.value);
    }

    function moveCollateralGainToTrove(address, address _upperHint, address _lowerHint) external payable {
        _addColl(_upperHint, _lowerHint, msg.value);
    }

    function withdrawColl(uint256 _amount, address _upperHint, address _lowerHint) external {
        totalCollateral -= _amount;
        lastCollateralWithdrawal = _amount;
        lastUpperHint = _upperHint;
        lastLowerHint = _lowerHint;
        lastAction = keccak256("withdrawColl");

        (bool _success,) = payable(msg.sender).call{ value: _amount }("");
        require(_success);
    }

    function withdrawMUSD(uint256 _amount, address _upperHint, address _lowerHint) external {
        totalDebtPrincipal += _amount;
        lastDebtChange = _amount;
        lastDebtIncrease = true;
        lastUpperHint = _upperHint;
        lastLowerHint = _lowerHint;
        lastAction = keccak256("withdrawMUSD");
    }

    function repayMUSD(uint256 _amount, address _upperHint, address _lowerHint) external {
        totalDebtPrincipal -= _amount;
        lastDebtChange = _amount;
        lastDebtIncrease = false;
        lastUpperHint = _upperHint;
        lastLowerHint = _lowerHint;
        lastAction = keccak256("repayMUSD");
    }

    function closeTrove() external {
        uint256 _collateralToReturn = totalCollateral;

        totalCollateral = 0;
        totalDebtPrincipal = 0;
        lastAction = keccak256("closeTrove");

        (bool _success,) = payable(msg.sender).call{ value: _collateralToReturn }("");
        require(_success);
    }

    function restrictedCloseTrove(address, address, address _recipient) external {
        uint256 _collateralToReturn = totalCollateral;

        totalCollateral = 0;
        totalDebtPrincipal = 0;
        lastAction = keccak256("restrictedCloseTrove");

        (bool _success,) = payable(_recipient).call{ value: _collateralToReturn }("");
        require(_success);
    }

    function refinance(address, address) external {
        lastAction = keccak256("refinance");
    }

    function restrictedRefinance(address, address, address) external {
        lastAction = keccak256("restrictedRefinance");
    }

    function claimCollateral() external {
        lastAction = keccak256("claimCollateral");
    }

    function restrictedClaimCollateral(address, address) external {
        lastAction = keccak256("restrictedClaimCollateral");
    }

    function _openTrove(uint256 _musdAmount, address _upperHint, address _lowerHint, uint256 _collateralAmount)
        internal
    {
        totalCollateral += _collateralAmount;
        totalDebtPrincipal += _musdAmount;
        lastCollateralDeposit = _collateralAmount;
        lastDebtChange = _musdAmount;
        lastDebtIncrease = true;
        lastUpperHint = _upperHint;
        lastLowerHint = _lowerHint;
        lastAction = keccak256("openTrove");
    }

    function _adjustTrove(
        uint256 _collWithdrawal,
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint,
        uint256 _collateralAmount,
        address payable _recipient
    ) internal {
        totalCollateral = totalCollateral + _collateralAmount - _collWithdrawal;

        if (_isDebtIncrease) {
            totalDebtPrincipal += _debtChange;
        } else {
            totalDebtPrincipal -= _debtChange;
        }

        lastCollateralDeposit = _collateralAmount;
        lastCollateralWithdrawal = _collWithdrawal;
        lastDebtChange = _debtChange;
        lastDebtIncrease = _isDebtIncrease;
        lastUpperHint = _upperHint;
        lastLowerHint = _lowerHint;

        lastAction = keccak256("adjustTrove");

        if (_collWithdrawal > 0) {
            (bool _success,) = _recipient.call{ value: _collWithdrawal }("");
            require(_success);
        }
    }

    function _addColl(address _upperHint, address _lowerHint, uint256 _collateralAmount) internal {
        totalCollateral += _collateralAmount;
        lastCollateralDeposit = _collateralAmount;
        lastUpperHint = _upperHint;
        lastLowerHint = _lowerHint;
        lastAction = keccak256("addColl");
    }
}
