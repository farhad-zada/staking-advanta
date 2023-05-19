// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract My721 is ERC721Upgradeable {
    function initialize(string memory _symbol) public initializer {
        __ERC721_init(_symbol, _symbol);
    }

    function mint(address to, uint256 tokenID) public {
        _mint(to, tokenID);
    }
}
