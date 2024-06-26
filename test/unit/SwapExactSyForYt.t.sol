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

    struct State {
        uint256 exactSYIn;
        PYIndex index;
        uint256 ytOut;
        uint256 delta;
        uint256 amountOut;
        address to;
    }

    function test_swapExactSyForYt_TransfersTokens() public useSYPool withSY(address(this), 10 ether) {
        State memory state;
        state.to = address(0xbeef);
        state.exactSYIn = 1 ether;
        state.index = YT.newIndex();

        uint256[] memory preBalances = new uint256[](3);
        preBalances[0] = ERC20(address(SY)).balanceOf(address(this));
        preBalances[1] = ERC20(address(YT)).balanceOf(state.to);
        preBalances[2] = ERC20(address(SY)).balanceOf(address(rmm));

        state.ytOut = rmm.computeSYToYT(state.index, state.exactSYIn, 500 ether, block.timestamp, 0, 10_000);
        (uint256 amountInWad, uint256 amountOutWad,,,) = rmm.prepareSwapPtIn(state.ytOut, block.timestamp, state.index);
        state.delta = amountInWad - amountOutWad;
        (uint256 amtOut,) = rmm.swapExactSyForYt(
            state.exactSYIn, state.ytOut, state.ytOut.mulDivDown(95, 100), 500 ether, 10_000, state.to
        );

        assertEq(ERC20(address(SY)).balanceOf(address(this)), preBalances[0] - state.delta);
        assertEq(ERC20(address(YT)).balanceOf(state.to), preBalances[1] + amtOut);
        assertEq(ERC20(address(SY)).balanceOf(address(rmm)), preBalances[2] - amountOutWad);
    }
}
