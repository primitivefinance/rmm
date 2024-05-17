/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PYIndex} from "./../src/RMM.sol";
import {SetUp, RMM} from "./SetUp.sol";

contract AllocateTest is SetUp {
    function test_allocate_MintsLiquidity() public initDefaultPool dealSY(address(this), 1_000 ether) {
        (uint256 deltaXWad, uint256 deltaYWad,,) =
            rmm.prepareAllocate(0.1 ether, 0.1 ether, PYIndex.wrap(YT.pyIndexCurrent()));

        uint256 preTotalLiquidity = rmm.totalLiquidity();
        uint256 deltaLiquidity = rmm.allocate(deltaXWad, deltaYWad, 0, address(this));
        assertEq(rmm.totalLiquidity(), preTotalLiquidity + deltaLiquidity);
    }

    function test_allocate_MintsLP() public initDefaultPool {
        deal(address(SY), address(this), 1_000 ether);

        uint256 preBalance = rmm.balanceOf(address(this));
        uint256 preTotalSupply = rmm.totalSupply();
        (uint256 deltaXWad, uint256 deltaYWad,, uint256 lpMinted) =
            rmm.prepareAllocate(0.1 ether, 0.1 ether, PYIndex.wrap(YT.pyIndexCurrent()));
        rmm.allocate(deltaXWad, deltaYWad, 0, address(this));
        assertEq(rmm.balanceOf(address(this)), preBalance + lpMinted);
        assertEq(rmm.totalSupply(), preTotalSupply + lpMinted);
    }

    function test_allocate_AdjustsPool() public initDefaultPool {
        deal(address(SY), address(this), 1_000 ether);

        uint256 preReserveX = rmm.reserveX();
        uint256 preReserveY = rmm.reserveY();

        (uint256 deltaXWad, uint256 deltaYWad,,) =
            rmm.prepareAllocate(0.1 ether, 0.1 ether, PYIndex.wrap(YT.pyIndexCurrent()));
        rmm.allocate(deltaXWad, deltaYWad, 0, address(this));

        assertEq(rmm.reserveX(), preReserveX + deltaXWad);
        assertEq(rmm.reserveY(), preReserveY + deltaYWad);
        assertEq(rmm.lastTimestamp(), block.timestamp);
    }

    function test_allocate_TransfersTokens() public initDefaultPool {
        deal(address(SY), address(this), 1_000 ether);

        uint256 thisPreBalanceSY = SY.balanceOf(address(this));
        uint256 thisPreBalancePT = PT.balanceOf(address(this));
        uint256 rmmPreBalanceSY = SY.balanceOf(address(rmm));
        uint256 rmmPreBalancePT = PT.balanceOf(address(rmm));

        (uint256 deltaXWad, uint256 deltaYWad,,) =
            rmm.prepareAllocate(0.1 ether, 0.1 ether, PYIndex.wrap(YT.pyIndexCurrent()));
        rmm.allocate(deltaXWad, deltaYWad, 0, address(this));

        assertEq(SY.balanceOf(address(this)), thisPreBalanceSY - deltaXWad);
        assertEq(PT.balanceOf(address(this)), thisPreBalancePT - deltaYWad);
        assertEq(SY.balanceOf(address(rmm)), rmmPreBalanceSY + deltaXWad);
        assertEq(PT.balanceOf(address(rmm)), rmmPreBalancePT + deltaYWad);
    }

    function test_allocate_EmitsAllocate() public initDefaultPool {
        deal(address(SY), address(this), 1_000 ether);

        (uint256 deltaXWad, uint256 deltaYWad, uint256 deltaLiquidity,) =
            rmm.prepareAllocate(0.1 ether, 0.1 ether, PYIndex.wrap(YT.pyIndexCurrent()));

        vm.expectEmit(true, true, true, true);

        emit RMM.Allocate(address(this), address(this), deltaXWad, deltaYWad, deltaLiquidity);
        rmm.allocate(deltaXWad, deltaYWad, 0, address(this));
    }

    function test_allocate_RevertsIfInsufficientLiquidityOut() public initDefaultPool {
        deal(address(SY), address(this), 1_000 ether);

        (uint256 deltaXWad, uint256 deltaYWad, uint256 deltaLiquidity,) =
            rmm.prepareAllocate(0.1 ether, 0.1 ether, PYIndex.wrap(YT.pyIndexCurrent()));

        vm.expectRevert(
            abi.encodeWithSelector(
                RMM.InsufficientLiquidityOut.selector, deltaXWad, deltaYWad, deltaLiquidity + 1, deltaLiquidity
            )
        );
        rmm.allocate(deltaXWad, deltaYWad, deltaLiquidity + 1, address(this));
    }
}
