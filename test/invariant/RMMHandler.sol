/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/RMM.sol";

contract RMMHandler {
    RMM public rmm;

    uint256 public ghost_reserveX;
    uint256 public ghost_reserveY;
    uint256 public ghost_totalLiquidity;
    uint256 public ghost_totalSupply;

    constructor(RMM rmm_) {
        rmm = rmm_;
    }
}
