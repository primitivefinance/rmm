/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SetUp} from "../SetUp.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract SwapExactSyForPtTest is SetUp {
    function test_swapExactSyForPt_TransfersTokens() public useDefaultPool {
        address to = address(0xbeef);

        deal(address(SY), address(this), 1 ether);

        uint256 preSYBalance = ERC20(address(SY)).balanceOf(address(this));
        uint256 prePTBalance = ERC20(address(PT)).balanceOf(to);

        uint256 preSYBalanceRMM = ERC20(address(SY)).balanceOf(address(rmm));
        uint256 prePTBalanceRMM = ERC20(address(PT)).balanceOf(address(rmm));

        uint256 amountIn = 1 ether;
        (uint256 amountOut,) = rmm.swapExactSyForPt(amountIn, 0, address(to));

        assertEq(ERC20(address(SY)).balanceOf(address(this)), preSYBalance - amountIn);
        assertEq(ERC20(address(PT)).balanceOf(address(to)), prePTBalance + amountOut);
        assertEq(ERC20(address(SY)).balanceOf(address(rmm)), preSYBalanceRMM + amountIn);
        assertEq(ERC20(address(PT)).balanceOf(address(rmm)), prePTBalanceRMM - amountOut);
    }

    function test_swapExactSyForPt_Adjusts() public useDefaultPool {
        address to = address(0xbeef);
        deal(address(SY), address(this), 1 ether);

        uint256 preReserveX = rmm.reserveX();
        uint256 preReserveY = rmm.reserveY();
        uint256 preTotalLiquidity = rmm.totalLiquidity();

        uint256 amountIn = 1 ether;
        (uint256 amountOut, int256 deltaLiquidity) = rmm.swapExactSyForPt(amountIn, 0, address(to));

        assertEq(rmm.reserveX(), preReserveX + amountIn);
        assertEq(rmm.reserveY(), preReserveY - amountOut);
        assertEq(rmm.totalLiquidity(), preTotalLiquidity + uint256(deltaLiquidity));
    }

    function test_swapExactSyForPt_RevertsIfInsufficientOutput(address to) public useDefaultPool {
        deal(address(SY), address(this), 1 ether);
        vm.expectRevert();
        rmm.swapExactSyForPt(1 ether, type(uint256).max, address(to));
    }
}
