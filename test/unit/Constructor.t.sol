/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SetUp, RMM, InitParams, DEFAULT_NAME, DEFAULT_SYMBOL} from "../SetUp.sol";

contract ConstructorTest is SetUp {
    function test_constructor_InitializesParameters() public useDefaultPool {
        InitParams memory initParams = getDefaultParams();

        assertEq(rmm.WETH(), address(weth));
        assertEq(rmm.name(), DEFAULT_NAME);
        assertEq(rmm.symbol(), DEFAULT_SYMBOL);
        assertEq(address(rmm.PT()), address(PT));
        assertEq(address(rmm.SY()), address(SY));
        assertEq(address(rmm.YT()), address(YT));
        assertEq(rmm.strike(), initParams.strike);
        assertEq(rmm.reserveX(), initParams.amountX);
    }
}
