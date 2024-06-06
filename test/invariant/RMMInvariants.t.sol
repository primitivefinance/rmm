/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../SetUp.sol";
import {RMMHandler} from "./RMMHandler.sol";

contract RMMInvariantsTest is SetUp {
    RMMHandler handler;

    function setUp() public virtual override {
        super.setUp();
        handler = new RMMHandler(rmm);

        bytes4[] memory selectors = new bytes4[](0);

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_ReserveX() public {
        assertEq(rmm.reserveX(), handler.ghost_reserveX());
    }
}
