// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
error NotAdmin();

contract Levels is OwnableUpgradeable {
    mapping(address => uint64) private levels;
    mapping(address => bool) private admins;

    function initialize() public initializer {
        admins[msg.sender] = true;
        __Ownable_init();
    }

    modifier isAdmin() {
        if (!admins[msg.sender]) revert NotAdmin();
        _;
    }

    function getLevel(address who) public view returns (uint64) {
        return levels[who];
    }

    //Adming functions
    function setLevel(
        address who,
        uint64 _level
    ) public isAdmin returns (bool success) {
        levels[who] = _level;
        if (levels[who] != _level) {
            return false;
        }
        return true;
    }

    function setAdmin(address admin, bool boolean) public onlyOwner {
        admins[admin] = boolean;
    }
}
