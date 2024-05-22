/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PYIndex, IPYieldToken} from "./../../src/RMM.sol";
import {SetUp, RMM} from "./SetUp.sol";
import {Swap} from "../../src/lib/RmmEvents.sol";
import {InsufficientOutput} from "../../src/lib/RmmErrors.sol";

contract SwapYTest is SetUp {
    function test_swapY_AdjustsPool() public initDefaultPool dealSY(address(this), 1_000 ether) {
        (uint256 deltaXWad, uint256 deltaYWad,,) =
            rmm.prepareAllocate(1 ether, 1 ether, PYIndex.wrap(YT.pyIndexCurrent()));
        rmm.allocate(deltaXWad, deltaYWad, 0, address(this));

        PYIndex index = PYIndex.wrap(YT.pyIndexCurrent());
        uint256 amountIn = 1 ether;
        (,, uint256 minAmountOut,,) = rmm.prepareSwap(address(PT), address(SY), amountIn, block.timestamp, index);

        uint256 preReserveX = rmm.reserveX();
        uint256 preReserveY = rmm.reserveY();

        (uint256 amountOut,) = rmm.swapY(amountIn, minAmountOut, address(this), "");

        assertEq(rmm.reserveX(), preReserveX - amountOut);
        assertEq(rmm.reserveY(), preReserveY + amountIn);
    }

    function test_swapY_TransfersTokens() public initDefaultPool dealSY(address(this), 1_000 ether) {
        (uint256 deltaXWad, uint256 deltaYWad,,) =
            rmm.prepareAllocate(1 ether, 1 ether, PYIndex.wrap(YT.pyIndexCurrent()));
        rmm.allocate(deltaXWad, deltaYWad, 0, address(this));

        PYIndex index = PYIndex.wrap(YT.pyIndexCurrent());
        uint256 amountIn = 1 ether;
        (,, uint256 minAmountOut,,) = rmm.prepareSwap(address(PT), address(SY), amountIn, block.timestamp, index);

        uint256 preRMMBalanceX = SY.balanceOf(address(rmm));
        uint256 preRMMBalanceY = PT.balanceOf(address(rmm));
        uint256 preBalanceX = SY.balanceOf(address(this));
        uint256 preBalanceY = PT.balanceOf(address(this));

        (uint256 amountOut,) = rmm.swapY(amountIn, minAmountOut, address(this), "");

        assertEq(preBalanceX + amountOut, SY.balanceOf(address(this)));
        assertEq(preBalanceY - amountIn, PT.balanceOf(address(this)));
        assertEq(preRMMBalanceX - amountOut, SY.balanceOf(address(rmm)));
        assertEq(preRMMBalanceY + amountIn, PT.balanceOf(address(rmm)));
    }

    function test_swapY_EmitsSwap() public initDefaultPool dealSY(address(this), 1_000 ether) {
        (uint256 deltaXWad, uint256 deltaYWad,,) =
            rmm.prepareAllocate(1 ether, 1 ether, PYIndex.wrap(YT.pyIndexCurrent()));
        rmm.allocate(deltaXWad, deltaYWad, 0, address(this));

        PYIndex index = PYIndex.wrap(YT.pyIndexCurrent());
        uint256 amountIn = 1 ether;
        (,, uint256 minAmountOut, int256 deltaLiquidity,) =
            rmm.prepareSwap(address(PT), address(SY), amountIn, block.timestamp, index);
        vm.expectEmit(true, true, true, true);

        emit Swap(address(this), address(this), address(PT), address(SY), amountIn, minAmountOut, deltaLiquidity);
        rmm.swapY(amountIn, minAmountOut, address(this), "");
    }

    function test_swapY_RevertsWhenInsufficientOutput() public initDefaultPool dealSY(address(this), 1_000 ether) {
        (uint256 deltaXWad, uint256 deltaYWad,,) =
            rmm.prepareAllocate(1 ether, 1 ether, PYIndex.wrap(YT.pyIndexCurrent()));
        rmm.allocate(deltaXWad, deltaYWad, 0, address(this));

        PYIndex index = PYIndex.wrap(YT.pyIndexCurrent());
        uint256 amountIn = 1 ether;
        (,, uint256 minAmountOut,,) = rmm.prepareSwap(address(PT), address(SY), amountIn, block.timestamp, index);
        vm.expectRevert(abi.encodeWithSelector(InsufficientOutput.selector, amountIn, minAmountOut + 1, minAmountOut));
        rmm.swapY(amountIn, minAmountOut + 1, address(this), "");
    }
}
