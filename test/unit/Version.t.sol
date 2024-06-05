/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SetUp, RMM} from "../SetUp.sol";

contract VersionTest is SetUp {
    function test_version() public view {
        assertEq(rmm.version(), "0.1.1-rc0");
    }
}
