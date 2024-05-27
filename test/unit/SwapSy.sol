/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PYIndex, IPYieldToken} from "./../../src/RMM.sol";
import {SetUp, RMM} from "./SetUp.sol";
import {Swap} from "../../src/lib/RmmEvents.sol";
import {InsufficientOutput} from "../../src/lib/RmmErrors.sol";

contract SwapSyTest is SetUp {
    function test_swapSy_AdjustsPool() public initDefaultPool dealSY(address(this), 1_000 ether) {
        (uint256 deltaXWad, uint256 deltaYWad,,) =
            rmm.prepareAllocate(1 ether, 1 ether, PYIndex.wrap(YT.pyIndexCurrent()));
        rmm.allocate(deltaXWad, deltaYWad, 0, address(this));

        PYIndex index = PYIndex.wrap(YT.pyIndexCurrent());
        uint256 amountIn = 1 ether;
        (,, uint256 minAmountOut,,) = rmm.prepareSwapSy(amountIn, block.timestamp, index);

        uint256 preReserveX = rmm.reserveX();
        uint256 preReserveY = rmm.reserveY();

        (uint256 amountOut,) = rmm.swapExactSyForPt(amountIn, 0, address(this));

        assertEq(rmm.reserveX(), preReserveX + amountIn);
        assertEq(rmm.reserveY(), preReserveY - amountOut);
    }

    function test_swapSy_TransfersTokens() public initDefaultPool dealSY(address(this), 1_000 ether) {
        (uint256 deltaXWad, uint256 deltaYWad,,) =
            rmm.prepareAllocate(1 ether, 1 ether, PYIndex.wrap(YT.pyIndexCurrent()));
        rmm.allocate(deltaXWad, deltaYWad, 0, address(this));

        PYIndex index = PYIndex.wrap(YT.pyIndexCurrent());
        uint256 amountIn = 1 ether;
        (,, uint256 minAmountOut,,) = rmm.prepareSwapSy(amountIn, block.timestamp, index);

        uint256 preRMMBalanceX = SY.balanceOf(address(rmm));
        uint256 preRMMBalanceY = PT.balanceOf(address(rmm));
        uint256 preBalanceX = SY.balanceOf(address(this));
        uint256 preBalanceY = PT.balanceOf(address(this));

        (uint256 amountOut,) = rmm.swapExactSyForPt(amountIn, 0, address(this));

        assertEq(preBalanceX - amountIn, SY.balanceOf(address(this)));
        assertEq(preBalanceY + amountOut, PT.balanceOf(address(this)));
        assertEq(preRMMBalanceX + amountIn, SY.balanceOf(address(rmm)));
        assertEq(preRMMBalanceY - amountOut, PT.balanceOf(address(rmm)));
    }

    function test_swapSy_EmitsSwap() public initDefaultPool dealSY(address(this), 1_000 ether) {
        (uint256 deltaXWad, uint256 deltaYWad,,) =
            rmm.prepareAllocate(1 ether, 1 ether, PYIndex.wrap(YT.pyIndexCurrent()));
        rmm.allocate(deltaXWad, deltaYWad, 0, address(this));

        PYIndex index = PYIndex.wrap(YT.pyIndexCurrent());
        uint256 amountIn = 1 ether;
        (,, uint256 minAmountOut, int256 deltaLiquidity,) = rmm.prepareSwapSy(amountIn, block.timestamp, index);
        vm.expectEmit(true, true, true, true);

        emit Swap(address(this), address(this), address(SY), address(PT), amountIn, minAmountOut, deltaLiquidity);
        rmm.swapExactSyForPt(amountIn, 0, address(this));
    }

    function test_swapSy_RevertsWhenInsufficientOutput() public initDefaultPool dealSY(address(this), 1_000 ether) {
        (uint256 deltaXWad, uint256 deltaYWad,,) =
            rmm.prepareAllocate(1 ether, 1 ether, PYIndex.wrap(YT.pyIndexCurrent()));
        rmm.allocate(deltaXWad, deltaYWad, 0, address(this));

        PYIndex index = PYIndex.wrap(YT.pyIndexCurrent());
        uint256 amountIn = 1 ether;
        (,, uint256 minAmountOut,,) = rmm.prepareSwapSy(amountIn, block.timestamp, index);
        vm.expectRevert(abi.encodeWithSelector(InsufficientOutput.selector, amountIn, minAmountOut + 1, minAmountOut));
        rmm.swapExactSyForPt(amountIn, minAmountOut + 1, address(this));
    }
}
