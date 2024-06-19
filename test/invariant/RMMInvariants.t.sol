/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../SetUp.sol";
import {RMMHandler} from "./RMMHandler.sol";

contract RMMInvariantsTest is SetUp {
    RMMHandler handler;

    function setUp() public virtual override {
        super.setUp();
        handler = new RMMHandler(rmm, PT, SY, YT);

        mintSY(address(handler), 100 ether);
        mintSY(address(this), 50 ether);
        mintPY(address(handler), 50 ether);

        handler.init();

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = RMMHandler.allocate.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));

        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 10
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_works() public view {
        assertNotEq(address(rmm.PT()), address(0));
    }

    function invariant_ReserveX() public {
        assertEq(rmm.reserveX(), handler.ghost_reserveX());
    }

    function invariant_ReserveY() public {
        assertEq(rmm.reserveY(), handler.ghost_reserveY());
    }
}
