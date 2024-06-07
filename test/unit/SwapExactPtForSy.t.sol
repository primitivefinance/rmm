/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SetUp} from "../SetUp.sol";

contract SwapExactPtForSyTest is SetUp {
    function test_swapExactPtForSy_works() public initDefaultPool {
        rmm.swapExactPtForSy(1 ether, 0, address(this));
    }
}
