/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import {abs} from "./../../src/lib/RmmLib.sol";
import {SetUp} from "../SetUp.sol";
import {RMMHandler} from "./RMMHandler.sol";

contract RMMInvariantsTest is SetUp {
    RMMHandler handler;

    function setUp() public virtual override {
        super.setUp();

        // This will redeploy the RMM contract without initializing the pool
        setUpRMM(getDefaultParams());
        handler = new RMMHandler(rmm, PT, SY, YT, weth);

        mintSY(address(handler), 1000 ether);
        mintSY(address(this), 2000 ether);
        mintPY(address(handler), 2000 ether);

        handler.init();

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = RMMHandler.allocate.selector;
        selectors[1] = RMMHandler.deallocate.selector;
        selectors[2] = RMMHandler.swapExactSyForYt.selector;
        selectors[3] = RMMHandler.swapExactPtForSy.selector;
        selectors[4] = RMMHandler.swapExactSyForPt.selector;
        // selectors[5] = RMMHandler.swapExactYtForSy.selector;
        // selectors[6] = RMMHandler.swapExactTokenForYt.selector;

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
        console.log("SwapExactSyForPt: ", handler.calls(RMMHandler.swapExactSyForPt.selector));
        console.log("SwapExactYtForSy: ", handler.calls(RMMHandler.swapExactYtForSy.selector));
    }

    /// forge-config: default.invariant.runs = 10
    /// forge-config: default.invariant.depth = 10
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_TradingFunction() public {
        assertTrue(abs(rmm.tradingFunction(newIndex())) <= 100, "Invariant out of valid range");
    }

    /// forge-config: default.invariant.runs = 10
    /// forge-config: default.invariant.depth = 10
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_ReserveX() public view {
        assertEq(rmm.reserveX(), handler.ghost_reserveX());
    }

    /// forge-config: default.invariant.runs = 10
    /// forge-config: default.invariant.depth = 10
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_ReserveY() public view {
        assertEq(rmm.reserveY(), handler.ghost_reserveY());
    }
}
