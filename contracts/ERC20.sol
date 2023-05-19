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
//busd: 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
//meto: 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9
