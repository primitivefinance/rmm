/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {MockRMM, PYIndex} from "../MockRMM.sol";

contract AdjustTest is Test {
    MockRMM rmm;

    function setUp() public {
        rmm = new MockRMM(address(0), "", "");
    }

    function test_adjust() public {
        int256 deltaX;
        int256 deltaY;
        int256 deltaLiquidity;
        rmm.adjust(deltaX, deltaY, deltaLiquidity, 0, PYIndex.wrap(0));
    }
}
