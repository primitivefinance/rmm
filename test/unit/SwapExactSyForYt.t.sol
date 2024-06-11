/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {PYIndexLib, IPYieldToken, PYIndex} from "pendle/core/StandardizedYield/PYIndex.sol";
import {SetUp} from "../SetUp.sol";

contract SwapExactSyForYtTest is SetUp {
    using PYIndexLib for IPYieldToken;

    function test_swapExactSyForYt_TransfersTokens() public initSYPool {
        address to = address(0xbeef);

        deal(address(SY), address(this), 1 ether);
        uint256 preSYBalance = ERC20(address(SY)).balanceOf(address(this));
        uint256 preYTBalance = ERC20(address(YT)).balanceOf(to);
        uint256 preSYBalanceRMM = ERC20(address(SY)).balanceOf(address(rmm));

        uint256 amountIn = 1 ether;

        PYIndex index = YT.newIndex();
        uint256 ytOut = rmm.computeSYToYT(index, 1 ether, block.timestamp, 500 ether);
        (uint256 amountOut,) = rmm.swapExactSyForYt(ytOut, 0, address(to));

        assertEq(ERC20(address(SY)).balanceOf(address(this)), preSYBalance - amountIn);
        assertEq(ERC20(address(YT)).balanceOf(to), preYTBalance + amountOut);
        assertEq(ERC20(address(SY)).balanceOf(address(rmm)), preSYBalanceRMM + amountIn);
    }
}
