/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/Test.sol";
import {IPYieldToken, PYIndexLib, PYIndex} from "pendle/core/StandardizedYield/PYIndex.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {InvalidTokenIn} from "../../src/lib/RmmErrors.sol";
import {SetUp, RMM} from "../SetUp.sol";
import "forge-std/console2.sol";

contract SwapExactTokenForYtTest is SetUp {
    using PYIndexLib for IPYieldToken;
    using FixedPointMathLib for uint256;

    function test_swapExactTokenForYt_SwapsWETH() public useSYPool withWETH(address(this), 1 ether) {
        uint256 amountIn = 1 ether;
        PYIndex index = YT.newIndex();
        console2.log("before");
        (uint256 syMinted, uint256 ytOut) =
            rmm.computeTokenToYT(index, address(weth), amountIn, 500 ether, block.timestamp, 0, 1_000);
        console2.log("after");
        console.log("syMinted", syMinted);
        rmm.swapExactTokenForYt(
            address(weth), amountIn, ytOut, syMinted, ytOut.mulDivDown(99, 100), 500 ether, 0.005 ether, address(this)
        );
    }

    function test_swapExactTokenForYt_RevertsIfInvalidTokenIn() public useDefaultPool {
        skip();
        vm.expectRevert(abi.encodeWithSelector(InvalidTokenIn.selector, address(0xbeef)));
        // rmm.swapExactTokenForYt(address(0xbeef), 1 ether, 0, 0, address(this));
    }
}
