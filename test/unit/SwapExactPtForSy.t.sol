/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {InsufficientOutput} from "../../src/lib/RmmErrors.sol";
import {Swap} from "../../src/lib/RmmEvents.sol";
import {SetUp} from "../SetUp.sol";

contract SwapExactPtForSyTest is SetUp {
    function test_swapExactPtForSy_TransfersTokens() public useDefaultPool {
        address to = address(0xbeef);

        uint256 preSYBalance = ERC20(address(SY)).balanceOf(to);
        uint256 prePTBalance = ERC20(address(PT)).balanceOf(address(this));

        uint256 preSYBalanceRMM = ERC20(address(SY)).balanceOf(address(rmm));
        uint256 prePTBalanceRMM = ERC20(address(PT)).balanceOf(address(rmm));

        uint256 amountIn = 1 ether;
        (uint256 amountOut,) = rmm.swapExactPtForSy(amountIn, 0, address(to));

        assertEq(ERC20(address(SY)).balanceOf(address(to)), preSYBalance + amountOut);
        assertEq(ERC20(address(PT)).balanceOf(address(this)), prePTBalance - amountIn);
        assertEq(ERC20(address(SY)).balanceOf(address(rmm)), preSYBalanceRMM - amountOut);
        assertEq(ERC20(address(PT)).balanceOf(address(rmm)), prePTBalanceRMM + amountIn);
    }

    function test_swapExactPtForSy_AdjustsReserves() public useDefaultPool {
        uint256 preReserveX = rmm.reserveX();
        uint256 preReserveY = rmm.reserveY();
        uint256 preLiquidity = rmm.totalLiquidity();
        uint256 preStrike = rmm.strike();

        uint256 amountIn = 1 ether;
        (uint256 amountOut, int256 deltaLiquidity) = rmm.swapExactPtForSy(amountIn, 0, address(this));

        assertEq(rmm.reserveX(), preReserveX - amountOut);
        assertEq(rmm.reserveY(), preReserveY + amountIn);
        assertEq(rmm.totalLiquidity(), preLiquidity + uint256(deltaLiquidity));
        assertEq(rmm.strike(), preStrike);
    }

    function test_swapExactPtForSy_RevertsIfInsufficientOutput() public useDefaultPool {
        vm.expectRevert();
        rmm.swapExactPtForSy(1 ether, type(uint256).max, address(this));
    }

    function test_swapExactPtForSy_EmitsEvent() public useDefaultPool {
        uint256 deltaPt = 1 ether;
        (,, uint256 minAmountOut, int256 deltaLiquidity,) = rmm.prepareSwapPtIn(deltaPt, block.timestamp, newIndex());
        vm.expectEmit(true, true, true, true);
        emit Swap(address(this), address(this), address(PT), address(SY), deltaPt, minAmountOut, deltaLiquidity);
        rmm.swapExactPtForSy(deltaPt, minAmountOut, address(this));
    }
}
