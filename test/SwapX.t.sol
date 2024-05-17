/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PYIndex} from "./../src/RMM.sol";
import {SetUp, RMM} from "./SetUp.sol";

contract SwapXTest is SetUp {
    function test_swapX_AdjustsPool() public {}
    function test_swapX_TransfersTokens() public {}
    function test_swapX_EmitsSwap() public {}
    function test_swapX_RevertsWhenInsufficientOutput() public {}
}
