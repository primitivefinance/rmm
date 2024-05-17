/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PYIndex} from "./../src/RMM.sol";
import {SetUp, RMM} from "./SetUp.sol";

contract DeallocateTest is SetUp {
    function test_deallocate_BurnsLiquidity() public initDefaultPool dealSY(address(this), 1_000 ether) {
        (uint256 deltaXWad, uint256 deltaYWad,,) =
            rmm.prepareAllocate(0.1 ether, 0.1 ether, PYIndex.wrap(YT.pyIndexCurrent()));

        (uint256 deltaLiquidity) = rmm.allocate(deltaXWad, deltaYWad, 0, address(this));

        uint256 lptBurned;
        (deltaXWad, deltaYWad, lptBurned) = rmm.prepareDeallocate(deltaLiquidity / 2);

        uint256 preTotalLiquidity = rmm.totalLiquidity();
        rmm.deallocate(deltaLiquidity / 2, 0, 0, address(this));
        assertEq(rmm.totalLiquidity(), preTotalLiquidity - deltaLiquidity / 2);
    }

    function test_deallocate_AdjustsPool() public initDefaultPool dealSY(address(this), 1_000 ether) {
        (uint256 deltaXWad, uint256 deltaYWad,,) =
            rmm.prepareAllocate(0.1 ether, 0.1 ether, PYIndex.wrap(YT.pyIndexCurrent()));

        (uint256 deltaLiquidity) = rmm.allocate(deltaXWad, deltaYWad, 0, address(this));

        uint256 lptBurned;
        (deltaXWad, deltaYWad, lptBurned) = rmm.prepareDeallocate(deltaLiquidity / 2);

        uint256 preReserveX = rmm.reserveX();
        uint256 preReserveY = rmm.reserveY();

        rmm.deallocate(deltaLiquidity / 2, 0, 0, address(this));
        assertEq(rmm.reserveX(), preReserveX - deltaXWad);
        assertEq(rmm.reserveY(), preReserveY - deltaYWad);
        assertEq(rmm.lastTimestamp(), block.timestamp);
    }

    function test_deallocate_TransfersTokens() public initDefaultPool dealSY(address(this), 1_000 ether) {
        (uint256 deltaXWad, uint256 deltaYWad,,) =
            rmm.prepareAllocate(0.1 ether, 0.1 ether, PYIndex.wrap(YT.pyIndexCurrent()));
        (uint256 deltaLiquidity) = rmm.allocate(deltaXWad, deltaYWad, 0, address(this));
        uint256 lptBurned;

        uint256 thisPreBalanceSY = SY.balanceOf(address(this));
        uint256 thisPreBalancePT = PT.balanceOf(address(this));
        uint256 rmmPreBalanceSY = SY.balanceOf(address(rmm));
        uint256 rmmPreBalancePT = PT.balanceOf(address(rmm));

        (deltaXWad, deltaYWad, lptBurned) = rmm.prepareDeallocate(deltaLiquidity / 2);
        rmm.deallocate(deltaLiquidity / 2, 0, 0, address(this));

        assertEq(SY.balanceOf(address(this)), thisPreBalanceSY + deltaXWad);
        assertEq(PT.balanceOf(address(this)), thisPreBalancePT + deltaYWad);
        assertEq(SY.balanceOf(address(rmm)), rmmPreBalanceSY - deltaXWad);
        assertEq(PT.balanceOf(address(rmm)), rmmPreBalancePT - deltaYWad);
    }

    function test_deallocate_EmitsDeallocate() public initDefaultPool dealSY(address(this), 1_000 ether) {
        (uint256 deltaXWad, uint256 deltaYWad,,) =
            rmm.prepareAllocate(0.1 ether, 0.1 ether, PYIndex.wrap(YT.pyIndexCurrent()));
        (uint256 deltaLiquidity) = rmm.allocate(deltaXWad, deltaYWad, 0, address(this));
        uint256 lptBurned;

        (deltaXWad, deltaYWad, lptBurned) = rmm.prepareDeallocate(deltaLiquidity / 2);
        rmm.deallocate(deltaLiquidity / 2, 0, 0, address(this));

        vm.expectEmit(true, true, true, true);
        emit RMM.Deallocate(address(this), address(this), deltaXWad, deltaYWad, deltaLiquidity / 2);
        rmm.deallocate(deltaLiquidity / 2, 0, 0, address(this));
    }

    function test_deallocate_RevertsIfInsufficientSYOutput() public {
        vm.skip(true);
    }

    function test_deallocate_RevertsIfInsufficientPTOutput() public {
        vm.skip(true);
    }
}
