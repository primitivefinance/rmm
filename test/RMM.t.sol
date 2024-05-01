// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {RMM} from "../src/RMM.sol";

contract RMMTest is Test {
    RMM public counter;

    function setUp() public {
        counter = new RMM();
    }
}
