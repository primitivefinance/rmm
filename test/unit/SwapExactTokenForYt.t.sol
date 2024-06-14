/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {InvalidTokenIn} from "../../src/lib/RmmErrors.sol";
import {SetUp, RMM} from "../SetUp.sol";

contract SwapExactTokenForYtTest is SetUp {
    function test_swapExactTokenForYt_SwapsWETH() public useDefaultPool {
        // rmm.swapExactTokenForYt(address(weth), 1 ether, 0, 0, address(this));
    }

    function test_swapExactTokenForYt_RevertsIfInvalidTokenIn() public useDefaultPool {
        skip();
        vm.expectRevert(abi.encodeWithSelector(InvalidTokenIn.selector, address(0xbeef)));
        // rmm.swapExactTokenForYt(address(0xbeef), 1 ether, 0, 0, address(this));
    }
}
