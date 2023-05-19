//This if for purpose of testing
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract MyToken is ERC20Upgradeable {
    function initialize(
        string memory name_,
        string memory symbol_
    ) public initializer {
        __ERC20_init(name_, symbol_);
    }

    function mintToken(address to, uint256 amount) public {
        require(amount > 0, "Not zero mint.");
        require(to != address(0), "Not zero address.");
        _mint(to, amount * 10 ** 18);
    }
}
