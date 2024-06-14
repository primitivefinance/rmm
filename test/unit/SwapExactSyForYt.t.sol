/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {PYIndexLib, IPYieldToken, PYIndex} from "pendle/core/StandardizedYield/PYIndex.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SetUp} from "../SetUp.sol";

contract SwapExactSyForYtTest is SetUp {
    using PYIndexLib for IPYieldToken;
    using PYIndexLib for PYIndex;
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;

    function test_swapExactSyForYt_TransfersTokens() public useSYPool withSY(address(this), 10 ether) {
        address to = address(0xbeef);

        uint256 preSYBalance = ERC20(address(SY)).balanceOf(address(this));
        uint256 preYTBalance = ERC20(address(YT)).balanceOf(to);
        uint256 preSYBalanceRMM = ERC20(address(SY)).balanceOf(address(rmm));

        uint256 amountIn = 1 ether;

        PYIndex index = YT.newIndex();
        uint256 ytOut = rmm.computeSYToYT(index, 1 ether, 500 ether, block.timestamp, 0, 10_000);
        (uint256 amountInWad, uint256 amountOutWad,,,) = rmm.prepareSwapPtIn(ytOut, block.timestamp, index);
        uint256 delta = index.assetToSyUp(amountInWad) - amountOutWad;
        (uint256 amtOut,) =
            rmm.swapExactSyForYt(1 ether, ytOut, ytOut.mulDivDown(95, 100), 500 ether, 10_000, address(this));

        assertEq(ERC20(address(SY)).balanceOf(address(this)), preSYBalance - amountIn - delta, "bad sy minus");
        assertEq(ERC20(address(YT)).balanceOf(to), preYTBalance + amtOut, "bad yt");
        assertEq(ERC20(address(SY)).balanceOf(address(rmm)), preSYBalanceRMM + amountIn, "bad sy plus");
    }
}
