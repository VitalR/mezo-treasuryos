// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IBorrowerOperations } from "../../src/interfaces/IBorrowerOperations.sol";

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

    receive() external payable { }

    function setBorrowingFee(uint256 _borrowingFee) external {
        borrowingFee = _borrowingFee;
    }

    function getBorrowingFee(uint256) external view returns (uint256) {
        return borrowingFee;
    }

    function openTrove(uint256 _musdAmount, address _upperHint, address _lowerHint) external payable {
        totalCollateral += msg.value;
        totalDebtPrincipal += _musdAmount;
        lastCollateralDeposit = msg.value;
        lastDebtChange = _musdAmount;
        lastDebtIncrease = true;
        lastUpperHint = _upperHint;
        lastLowerHint = _lowerHint;
        lastAction = keccak256("openTrove");
    }

    function adjustTrove(
        uint256 _collWithdrawal,
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint
    ) external payable {
        totalCollateral = totalCollateral + msg.value - _collWithdrawal;

        if (_isDebtIncrease) {
            totalDebtPrincipal += _debtChange;
        } else {
            totalDebtPrincipal -= _debtChange;
        }

        lastCollateralDeposit = msg.value;
        lastCollateralWithdrawal = _collWithdrawal;
        lastDebtChange = _debtChange;
        lastDebtIncrease = _isDebtIncrease;
        lastUpperHint = _upperHint;
        lastLowerHint = _lowerHint;
        lastAction = keccak256("adjustTrove");

        if (_collWithdrawal > 0) {
            (bool _success,) = payable(msg.sender).call{ value: _collWithdrawal }("");
            require(_success);
        }
    }

    function addColl(address _upperHint, address _lowerHint) external payable {
        totalCollateral += msg.value;
        lastCollateralDeposit = msg.value;
        lastUpperHint = _upperHint;
        lastLowerHint = _lowerHint;
        lastAction = keccak256("addColl");
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
}
