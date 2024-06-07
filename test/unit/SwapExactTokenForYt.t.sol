/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SetUp, RMM} from "../SetUp.sol";

contract SwapExactTokenForYtTest is SetUp {
    function test_swapExactTokenForYt_SwapsWETH() public initDefaultPool {
        rmm.swapExactTokenForYt(address(weth), 1 ether, 0, 0, address(this));
    }
}
