/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import {PYIndex, PYIndexLib} from "pendle/core/StandardizedYield/PYIndex.sol";
import {abs} from "./../../src/lib/RmmLib.sol";
import {IPYieldToken} from "pendle/interfaces/IPYieldToken.sol";
import {SetUp} from "../SetUp.sol";
import {RMMHandler} from "./RMMHandler.sol";
import "forge-std/console2.sol";

contract RMMInvariantsTest is SetUp {
    using PYIndexLib for IPYieldToken;

    RMMHandler handler;

    function setUp() public virtual override {
        super.setUp();
        handler = new RMMHandler(rmm, PT, SY, YT, weth);

        mintSY(address(handler), 1000 ether);
        mintSY(address(this), 2000 ether);
        mintPY(address(handler), 2000 ether);

        handler.init();

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = RMMHandler.allocate.selector;
        selectors[1] = RMMHandler.deallocate.selector;
        selectors[2] = RMMHandler.swapExactSyForYt.selector;
        selectors[3] = RMMHandler.swapExactPtForSy.selector;
        selectors[4] = RMMHandler.swapExactSyForPt.selector;
        selectors[5] = RMMHandler.swapExactYtForSy.selector;
        selectors[6] = RMMHandler.swapExactTokenForYt.selector;
        
        console.logBytes4(selectors[0]);
        console.logBytes4(selectors[1]);
        console.logBytes4(selectors[2]);
        console.logBytes4(selectors[3]);
        console.logBytes4(selectors[4]);
        console.logBytes4(selectors[5]);
        console.logBytes4(selectors[6]);
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));

        console2.log("got here?");
        targetContract(address(handler));
        console2.log("here?");
    }

    function afterInvariant() public view {
        console.log("Calls: ", handler.totalCalls());
        console.log("Allocate: ", handler.calls(RMMHandler.allocate.selector));
        console.log("Deallocate: ", handler.calls(RMMHandler.deallocate.selector));
        console.log("SwapExactSyForYt: ", handler.calls(RMMHandler.swapExactSyForYt.selector));
        console.log("SwapExactTokenForYt: ", handler.calls(RMMHandler.swapExactTokenForYt.selector));
        console.log("SwapExactPtForSy: ", handler.calls(RMMHandler.swapExactPtForSy.selector));
        console.log("SwapExactSyForPt: ", handler.calls(RMMHandler.swapExactSyForPt.selector));
        console.log("SwapExactYtForSy: ", handler.calls(RMMHandler.swapExactYtForSy.selector));
    }

    /// forge-config: default.invariant.runs = 10
    /// forge-config: default.invariant.depth = 100
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_TradingFunction() public {
        IPYieldToken YT = handler.YT();
        PYIndex index = YT.newIndex();
        assertTrue(abs(rmm.tradingFunction(index)) <= 100, "Invariant out of valid range");
    }

    /// forge-config: default.invariant.runs = 10
    /// forge-config: default.invariant.depth = 100
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_ReserveX() public view {
        assertEq(rmm.reserveX(), handler.ghost_reserveX());
    }

    /// forge-config: default.invariant.runs = 10
    /// forge-config: default.invariant.depth = 100
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_ReserveY() public view {
        console2.log("here?");
        assertEq(rmm.reserveY(), handler.ghost_reserveY());
    }
}
