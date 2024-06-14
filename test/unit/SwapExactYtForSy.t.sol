/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {console} from "forge-std/Test.sol";
import {PYIndexLib, IPYieldToken} from "pendle/core/StandardizedYield/PYIndex.sol";
import {SetUp} from "../SetUp.sol";

contract SwapExactYtForSyTest is SetUp {
    using PYIndexLib for IPYieldToken;

    function test_swapExactYtForSy_TransfersTokens() public useSYPool {
        address to = address(0xbeef);
        deal(address(YT), address(this), 10 ether);
        uint256 preSYBalance = ERC20(address(SY)).balanceOf(address(this));
        uint256 preYTBalance = ERC20(address(YT)).balanceOf(to);

        uint256 preSYBalanceRMM = ERC20(address(SY)).balanceOf(address(rmm));
        uint256 preYTBalanceRMM = ERC20(address(YT)).balanceOf(address(rmm));

        /*
        (uint256 amountInWad, uint256 amountOutWad, uint256 amountIn, int256 deltaLiquidity, uint256 strike_) =
            rmm.prepareSwapSyForExactPt(1 ether, block.timestamp, YT.newIndex());
            */

        uint256 amountIn = 1 ether;
        (uint256 amountOut,,) = rmm.swapExactYtForSy(amountIn, 1000 ether, address(to));

        /*
        assertEq(ERC20(address(YT)).balanceOf(address(this)), preYTBalance - amountIn);
        assertEq(ERC20(address(SY)).balanceOf(to), preSYBalance + amountOut);
        assertEq(ERC20(address(YT)).balanceOf(address(rmm)), preYTBalanceRMM + amountIn);
        assertEq(ERC20(address(SY)).balanceOf(address(rmm)), preSYBalanceRMM - amountOut);
        */
    }
}
