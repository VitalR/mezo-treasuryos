// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract MockTigrisLPToken is ERC20, ERC20Burnable {
    constructor() ERC20("Mock Tigris LP", "mTLP") { }

    function mint(address _recipient, uint256 _amount) external {
        _mint(_recipient, _amount);
    }
}
