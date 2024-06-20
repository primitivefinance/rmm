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
        mintSY(address(this), 50 ether);
        mintPY(address(handler), 50 ether);

        handler.init();

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = RMMHandler.allocate.selector;
        selectors[1] = RMMHandler.deallocate.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));

        targetContract(address(handler));
    }

    function afterInvariant() public view {
        console.log("Calls: ", handler.totalCalls());
        console.log("Allocate: ", handler.calls(RMMHandler.allocate.selector));
        console.log("Deallocate: ", handler.calls(RMMHandler.deallocate.selector));
    }

    function invariant_TradingFunction() public {
        IPYieldToken YT = handler.YT();
        PYIndex index = YT.newIndex();
        assertTrue(abs(rmm.tradingFunction(index)) <= 100, "Invariant out of valid range");
    }

    function invariant_ReserveX() public view {
        assertEq(rmm.reserveX(), handler.ghost_reserveX());
    }

    function invariant_ReserveY() public view {
        assertEq(rmm.reserveY(), handler.ghost_reserveY());
    }
}
