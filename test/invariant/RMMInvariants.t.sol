/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import {PYIndex, PYIndexLib} from "pendle/core/StandardizedYield/PYIndex.sol";
import {abs} from "./../../src/lib/RmmLib.sol";
import {IPYieldToken} from "pendle/interfaces/IPYieldToken.sol";
import {SetUp} from "../SetUp.sol";
import {RMMHandler} from "./RMMHandler.sol";

contract RMMInvariantsTest is SetUp {
    using PYIndexLib for IPYieldToken;

    RMMHandler handler;

    function setUp() public virtual override {
        super.setUp();
        handler = new RMMHandler(rmm, PT, SY, YT);

        mintSY(address(handler), 100 ether);
        mintSY(address(this), 100 ether);
        mintPY(address(handler), 100 ether);

        handler.init();

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = RMMHandler.allocate.selector;
        selectors[1] = RMMHandler.deallocate.selector;
        selectors[2] = RMMHandler.swapExactSyForYt.selector;
        selectors[3] = RMMHandler.swapExactTokenForYt.selector;
        selectors[4] = RMMHandler.swapExactPtForSy.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));

        targetContract(address(handler));
    }

    function afterInvariant() public view {
        console.log("Calls: ", handler.totalCalls());
        console.log("Allocate: ", handler.calls(RMMHandler.allocate.selector));
        console.log("Deallocate: ", handler.calls(RMMHandler.deallocate.selector));
        console.log("SwapExactSyForYt: ", handler.calls(RMMHandler.swapExactSyForYt.selector));
        console.log("SwapExactTokenForYt: ", handler.calls(RMMHandler.swapExactTokenForYt.selector));
        console.log("SwapExactPtForSy: ", handler.calls(RMMHandler.swapExactPtForSy.selector));
    }

    /// forge-config: default.invariant.runs = 100
    /// forge-config: default.invariant.depth = 2
    /// forge-config: default.invariant.fail-on-revert = false
    function invariant_TradingFunction() public {
        IPYieldToken YT = handler.YT();
        PYIndex index = YT.newIndex();
        assertTrue(abs(rmm.tradingFunction(index)) <= 100, "Invariant out of valid range");
    }

    /// forge-config: default.invariant.runs = 100
    /// forge-config: default.invariant.depth = 2
    /// forge-config: default.invariant.fail-on-revert = false
    function invariant_ReserveX() public view {
        assertEq(rmm.reserveX(), handler.ghost_reserveX());
    }

    /// forge-config: default.invariant.runs = 100
    /// forge-config: default.invariant.depth = 2
    /// forge-config: default.invariant.fail-on-revert = false
    function invariant_ReserveY() public view {
        assertEq(rmm.reserveY(), handler.ghost_reserveY());
    }
}
