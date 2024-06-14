/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IPYieldToken, PYIndexLib, PYIndex} from "pendle/core/StandardizedYield/PYIndex.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {InvalidTokenIn} from "../../src/lib/RmmErrors.sol";
import {SetUp, RMM} from "../SetUp.sol";

contract SwapExactTokenForYtTest is SetUp {
    using PYIndexLib for IPYieldToken;
    using FixedPointMathLib for uint256;

    function test_swapExactTokenForYt_SwapsWETH() public useDefaultPool {
        uint256 amountIn = 1 ether;
        PYIndex index = YT.newIndex();
        (uint256 syMinted, uint256 ytOut) =
            rmm.computeTokenToYT(index, address(weth), amountIn, 500 ether, block.timestamp, 0, 1_000);
        rmm.swapExactTokenForYt(
            address(weth), 0, ytOut, syMinted, ytOut.mulDivDown(99, 100), 500 ether, 0.005 ether, address(this)
        );
    }

    function test_swapExactTokenForYt_RevertsIfInvalidTokenIn() public useDefaultPool {
        skip();
        vm.expectRevert(abi.encodeWithSelector(InvalidTokenIn.selector, address(0xbeef)));
        // rmm.swapExactTokenForYt(address(0xbeef), 1 ether, 0, 0, address(this));
    }
}
