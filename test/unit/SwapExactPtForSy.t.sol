/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {InsufficientOutput} from "../../src/lib/RmmErrors.sol";
import {SetUp} from "../SetUp.sol";

contract SwapExactPtForSyTest is SetUp {
    function test_swapExactPtForSy_TransfersTokens() public initDefaultPool {
        uint256 preSYBalance = ERC20(address(SY)).balanceOf(address(this));
        uint256 prePTBalance = ERC20(address(PT)).balanceOf(address(this));

        uint256 preSYBalanceRMM = ERC20(address(SY)).balanceOf(address(rmm));
        uint256 prePTBalanceRMM = ERC20(address(PT)).balanceOf(address(rmm));

        uint256 amountIn = 1 ether;
        (uint256 amountOut,) = rmm.swapExactPtForSy(amountIn, 0, address(this));

        assertEq(ERC20(address(SY)).balanceOf(address(this)), preSYBalance + amountOut);
        assertEq(ERC20(address(PT)).balanceOf(address(this)), prePTBalance - amountIn);
        assertEq(ERC20(address(SY)).balanceOf(address(rmm)), preSYBalanceRMM - amountOut);
        assertEq(ERC20(address(PT)).balanceOf(address(rmm)), prePTBalanceRMM + amountIn);
    }

    function test_swapExactPtForSy_RevertsIfInsufficientOutput() public initDefaultPool {
        vm.expectRevert(abi.encodeWithSelector(InsufficientOutput.selector));
        rmm.swapExactPtForSy(1 ether, 1 ether, address(this));
    }
}
