/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PYIndex, IPYieldToken} from "./../src/RMM.sol";
import {SetUp, RMM} from "./SetUp.sol";

contract SwapXTest is SetUp {
    function test_swapX_AdjustsPool() public initDefaultPool dealSY(address(this), 1_000 ether) {
        (uint256 deltaXWad, uint256 deltaYWad,,) =
            rmm.prepareAllocate(1 ether, 1 ether, PYIndex.wrap(YT.pyIndexCurrent()));
        rmm.allocate(deltaXWad, deltaYWad, 0, address(this));

        PYIndex index = PYIndex.wrap(YT.pyIndexCurrent());
        uint256 deltaX = 1 ether;
        (,, uint256 minAmountOut, int256 delLiq,) =
            rmm.prepareSwap(address(SY), address(PT), deltaX, block.timestamp, index);
        rmm.swapX(deltaX, minAmountOut, address(this), "");
    }

    function test_swapX_TransfersTokens() public {}
    function test_swapX_EmitsSwap() public {}
    function test_swapX_RevertsWhenInsufficientOutput() public {}
}
