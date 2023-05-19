// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface ILevels {
    function getLevel(address who) external view returns (uint64);

    // Admin functions
    function setLevel(address who, uint64 _level) external returns (bool);
}
