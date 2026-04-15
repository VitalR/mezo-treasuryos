// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IBorrowerOperations } from "../../src/interfaces/IBorrowerOperations.sol";
import { IGovernableVariables } from "../../src/interfaces/IGovernableVariables.sol";
import { ITroveManager } from "../../src/interfaces/ITroveManager.sol";
import { MockMUSDToken } from "./MockMUSDToken.sol";

contract MockTroveManager is ITroveManager {
    uint256 public MUSD_GAS_COMPENSATION;
    mapping(address borrower => uint256 debt) public entireDebts;
    mapping(address borrower => uint256 collateral) public entireCollaterals;

    constructor() {
        MUSD_GAS_COMPENSATION = 0;
    }

    function setGasCompensation(uint256 _gasCompensation) external {
        MUSD_GAS_COMPENSATION = _gasCompensation;
    }

    function setPosition(address _borrower, uint256 _debt, uint256 _collateral) external {
        entireDebts[_borrower] = _debt;
        entireCollaterals[_borrower] = _collateral;
    }

    function getEntireDebtAndColl(address _borrower) external view returns (uint256 debt, uint256 coll) {
        return (entireDebts[_borrower], entireCollaterals[_borrower]);
    }
}

contract MockGovernableVariables is IGovernableVariables {
    address public troveManager;

    constructor(address _troveManager) {
        troveManager = _troveManager;
    }

    function setTroveManager(address _troveManager) external {
        troveManager = _troveManager;
    }
}

contract MockBorrowerOperations is IBorrowerOperations {
    uint256 public borrowingFee;

    uint256 public lastCollateralDeposit;
    uint256 public lastCollateralWithdrawal;
    uint256 public lastDebtChange;
    bool public lastDebtIncrease;
    address public lastUpperHint;
    address public lastLowerHint;
    bytes32 public lastAction;

    MockTroveManager public troveManagerContract;
    IGovernableVariables public governableVariables;
    MockMUSDToken public musdTokenContract;

    constructor() {
        troveManagerContract = new MockTroveManager();
        governableVariables = new MockGovernableVariables(address(troveManagerContract));
        musdTokenContract = new MockMUSDToken();
    }

    receive() external payable { }

    function setBorrowingFee(uint256 _borrowingFee) external {
        borrowingFee = _borrowingFee;
    }

    function setGasCompensation(uint256 _gasCompensation) external {
        troveManagerContract.setGasCompensation(_gasCompensation);
    }

    function musdToken() external view returns (address) {
        return address(musdTokenContract);
    }

    function totalDebt(address _borrower) external view returns (uint256) {
        return troveManagerContract.entireDebts(_borrower);
    }

    function totalCollateral(address _borrower) external view returns (uint256) {
        return troveManagerContract.entireCollaterals(_borrower);
    }

    function setAddresses(address[13] memory) external { }

    function setRefinancingFeePercentage(uint8) external { }

    function openTrove(uint256 _debtAmount, address _upperHint, address _lowerHint) external payable {
        uint256 _entireDebt = _debtAmount + borrowingFee + troveManagerContract.MUSD_GAS_COMPENSATION();

        troveManagerContract.setPosition(msg.sender, _entireDebt, msg.value);
        musdTokenContract.mint(msg.sender, _debtAmount);
        lastCollateralDeposit = msg.value;
        lastCollateralWithdrawal = 0;
        lastDebtChange = _debtAmount;
        lastDebtIncrease = true;
        lastUpperHint = _upperHint;
        lastLowerHint = _lowerHint;
        lastAction = keccak256("openTrove");
    }

    function restrictedOpenTrove(
        address _borrower,
        address _recipient,
        uint256 _debtAmount,
        address _upperHint,
        address _lowerHint
    ) external payable {
        uint256 _entireDebt =
            _debtAmount + borrowingFee + troveManagerContract.MUSD_GAS_COMPENSATION();

        troveManagerContract.setPosition(_borrower, _entireDebt, msg.value);
        musdTokenContract.mint(_recipient, _debtAmount);
        lastCollateralDeposit = msg.value;
        lastCollateralWithdrawal = 0;
        lastDebtChange = _debtAmount;
        lastDebtIncrease = true;
        lastUpperHint = _upperHint;
        lastLowerHint = _lowerHint;
        lastAction = keccak256("restrictedOpenTrove");
    }

    function proposeMinNetDebt(uint256) external { }

    function approveMinNetDebt() external { }

    function proposeBorrowingRate(uint256) external { }

    function approveBorrowingRate() external { }

    function proposeRedemptionRate(uint256) external { }

    function approveRedemptionRate() external { }

    function addColl(address _upperHint, address _lowerHint) external payable {
        troveManagerContract.setPosition(
            msg.sender,
            troveManagerContract.entireDebts(msg.sender),
            troveManagerContract.entireCollaterals(msg.sender) + msg.value
        );
        lastCollateralDeposit = msg.value;
        lastCollateralWithdrawal = 0;
        lastUpperHint = _upperHint;
        lastLowerHint = _lowerHint;
        lastAction = keccak256("addColl");
    }

    function moveCollateralGainToTrove(address, address _upperHint, address _lowerHint) external payable {
        troveManagerContract.setPosition(
            msg.sender,
            troveManagerContract.entireDebts(msg.sender),
            troveManagerContract.entireCollaterals(msg.sender) + msg.value
        );
        lastCollateralDeposit = msg.value;
        lastCollateralWithdrawal = 0;
        lastUpperHint = _upperHint;
        lastLowerHint = _lowerHint;
        lastAction = keccak256("moveCollateralGainToTrove");
    }

    function withdrawColl(uint256 _amount, address _upperHint, address _lowerHint) external {
        troveManagerContract.setPosition(
            msg.sender,
            troveManagerContract.entireDebts(msg.sender),
            troveManagerContract.entireCollaterals(msg.sender) - _amount
        );
        lastCollateralWithdrawal = _amount;
        lastUpperHint = _upperHint;
        lastLowerHint = _lowerHint;
        lastAction = keccak256("withdrawColl");

        (bool _success,) = payable(msg.sender).call{ value: _amount }("");
        require(_success);
    }

    function withdrawMUSD(uint256 _amount, address _upperHint, address _lowerHint) external {
        troveManagerContract.setPosition(
            msg.sender,
            troveManagerContract.entireDebts(msg.sender) + _amount,
            troveManagerContract.entireCollaterals(msg.sender)
        );
        musdTokenContract.mint(msg.sender, _amount);
        lastDebtChange = _amount;
        lastDebtIncrease = true;
        lastUpperHint = _upperHint;
        lastLowerHint = _lowerHint;
        lastAction = keccak256("withdrawMUSD");
    }

    function repayMUSD(uint256 _amount, address _upperHint, address _lowerHint) external {
        musdTokenContract.burnFrom(msg.sender, _amount);
        troveManagerContract.setPosition(
            msg.sender,
            troveManagerContract.entireDebts(msg.sender) - _amount,
            troveManagerContract.entireCollaterals(msg.sender)
        );
        lastDebtChange = _amount;
        lastDebtIncrease = false;
        lastUpperHint = _upperHint;
        lastLowerHint = _lowerHint;
        lastAction = keccak256("repayMUSD");
    }

    function closeTrove() external {
        uint256 _collateralToReturn = troveManagerContract.entireCollaterals(msg.sender);
        uint256 _closeDebt = troveManagerContract.entireDebts(msg.sender) - troveManagerContract.MUSD_GAS_COMPENSATION();

        if (_closeDebt > 0) {
            musdTokenContract.burnFrom(msg.sender, _closeDebt);
        }

        troveManagerContract.setPosition(msg.sender, 0, 0);
        lastAction = keccak256("closeTrove");

        (bool _success,) = payable(msg.sender).call{ value: _collateralToReturn }("");
        require(_success);
    }

    function restrictedCloseTrove(address, address, address _recipient) external {
        uint256 _collateralToReturn = troveManagerContract.entireCollaterals(msg.sender);
        uint256 _closeDebt = troveManagerContract.entireDebts(msg.sender) - troveManagerContract.MUSD_GAS_COMPENSATION();

        if (_closeDebt > 0) {
            musdTokenContract.burnFrom(msg.sender, _closeDebt);
        }

        troveManagerContract.setPosition(msg.sender, 0, 0);
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

    function adjustTrove(
        uint256 _collWithdrawal,
        uint256 _debtChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint
    ) external payable {
        uint256 _nextDebt = troveManagerContract.entireDebts(msg.sender);
        if (_debtChange > 0) {
            _nextDebt = _isDebtIncrease ? _nextDebt + _debtChange : _nextDebt - _debtChange;
        }

        uint256 _nextCollateral = troveManagerContract.entireCollaterals(msg.sender) + msg.value - _collWithdrawal;
        troveManagerContract.setPosition(msg.sender, _nextDebt, _nextCollateral);

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
        uint256 _nextDebt = troveManagerContract.entireDebts(msg.sender);
        if (_mUSDChange > 0) {
            _nextDebt = _isDebtIncrease ? _nextDebt + _mUSDChange : _nextDebt - _mUSDChange;
        }

        uint256 _nextCollateral = troveManagerContract.entireCollaterals(msg.sender) + msg.value - _collWithdrawal;
        troveManagerContract.setPosition(msg.sender, _nextDebt, _nextCollateral);

        lastCollateralDeposit = msg.value;
        lastCollateralWithdrawal = _collWithdrawal;
        lastDebtChange = _mUSDChange;
        lastDebtIncrease = _isDebtIncrease;
        lastUpperHint = _upperHint;
        lastLowerHint = _lowerHint;
        lastAction = keccak256("restrictedAdjustTrove");

        if (_collWithdrawal > 0) {
            (bool _success,) = payable(_recipient).call{ value: _collWithdrawal }("");
            require(_success);
        }
    }

    function claimCollateral() external {
        lastAction = keccak256("claimCollateral");
    }

    function restrictedClaimCollateral(address, address) external {
        lastAction = keccak256("restrictedClaimCollateral");
    }

    function getBorrowingFee(uint256) external view returns (uint256) {
        return borrowingFee;
    }

    function getRedemptionRate(uint256) external pure returns (uint256) {
        return 0;
    }

    function minNetDebt() external pure returns (uint256) {
        return 0;
    }
}
