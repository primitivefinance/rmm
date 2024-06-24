/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {SetUp} from "../SetUp.sol";
import {MockRMM, PYIndex} from "../MockRMM.sol";

contract AdjustTest is SetUp {
    MockRMM mock;

    function test_adjust() public {
        vm.skip(true);

        int256 deltaX;
        int256 deltaY;
        int256 deltaLiquidity;
        // mock.adjust(deltaX, deltaY, deltaLiquidity, 0, PYIndex.wrap(0));
    }
}
