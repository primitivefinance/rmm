/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SetUp, RMM} from "../SetUp.sol";

contract ApproxSpotPrice is SetUp {
    function test_approxSpotPrice_IncreasesOverTime() public useDefaultPool {
        uint256 preSpotPrice = rmm.approxSpotPrice(syToAsset(rmm.reserveX()));
        rmm.setLastTimestamp(block.timestamp + 10 days);
        uint256 postSpotPrice = rmm.approxSpotPrice(syToAsset(rmm.reserveX()));
        assertGt(postSpotPrice, preSpotPrice);
    }
}
