/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SetUp, RMM} from "../SetUp.sol";

contract ApproxSpotPriceTest is SetUp {
    function test_approxSpotPrice_IncreasesOverTime() public useDefaultPool {
        uint256 preSpotPrice = rmm.approxSpotPrice(syToAsset(rmm.reserveX()));
        rmm.setLastTimestamp(block.timestamp + 10 days);
        uint256 postSpotPrice = rmm.approxSpotPrice(syToAsset(rmm.reserveX()));
        assertGt(postSpotPrice, preSpotPrice);
    }

    function test_approxSpotPrice_OneAtMaturity() public useDefaultPool {
        vm.warp(rmm.maturity());
        rmm.swapExactSyForPt(1 ether, 0, address(this));
        uint256 maturityPrice = rmm.approxSpotPrice(syToAsset(rmm.reserveX()));
        assertEq(maturityPrice, 1 ether);
    }
}
