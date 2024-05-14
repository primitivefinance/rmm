/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {RMM} from "./../src/RMM.sol";

contract SetUp is Test {
    RMM public rmm;
    WETH public weth;

    address public wstETH;

    function setUp() public {
        weth = new WETH();
        rmm = new RMM(address(weth), "Test", "TST");
    }
}
