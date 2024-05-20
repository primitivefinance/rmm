/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, RMM} from "./SetUp.sol";

contract ConstructorTest is Test {
    function test_constructor_InitializesParameters() public {
        address weth = address(0xbeef);
        string memory name = "RMM-LP-TOKEN";
        string memory symbol = "RMM-LPT";

        RMM rmm = new RMM(weth, name, symbol);

        assertEq(rmm.WETH(), weth);
        assertEq(rmm.name(), name);
        assertEq(rmm.symbol(), symbol);
    }
}
