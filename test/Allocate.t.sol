/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PYIndex} from "./../src/RMM.sol";
import {SetUp} from "./SetUp.sol";

contract AllocateTest is SetUp {
    function test_allocate_MintsLiquidity() public initDefaultPool {
        deal(address(SY), address(this), 1_000 ether);

        (uint256 deltaXWad, uint256 deltaYWad,,) =
            rmm.prepareAllocate(0.1 ether, 0.1 ether, PYIndex.wrap(YT.pyIndexCurrent()));

        uint256 preTotalLiquidity = rmm.totalLiquidity();
        uint256 deltaLiquidity = rmm.allocate(deltaXWad, deltaYWad, 0, address(this));
        assertEq(rmm.totalLiquidity(), preTotalLiquidity + deltaLiquidity, "wrong total liquidity");
    }

    function test_allocate_AdjustsPool() public initDefaultPool {
        (uint256 deltaXWad, uint256 deltaYWad,,) =
            rmm.prepareAllocate(0.1 ether, 0.1 ether, PYIndex.wrap(YT.pyIndexCurrent()));
        rmm.allocate(deltaXWad, deltaYWad, 0, address(this));
    }

    function test_allocate_TransfersTokens() public {
        vm.skip(true);
    }

    function test_allocate_EmitsAllocate() public {
        vm.skip(true);
    }

    function test_allocate_RevertsIfInsufficientLiquidityOut() public {
        vm.skip(true);
    }
}
