// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

contract RMM {
    address public immutable WETH;
    uint256 public reserveX;
    uint256 public reserveY;
    uint256 public totalLiquidity;
    uint256 public mean;
    uint256 public width;
    uint256 public fee;
    uint256 public maturity;
    uint256 public lastTimestamp;
    address public curator;

    constructor(address weth_) {
        WETH = weth_;
    }
}
