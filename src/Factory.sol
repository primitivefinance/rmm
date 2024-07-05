// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {RMM} from "./RMM.sol";

contract Factory {
    event NewPool(address indexed caller, address indexed pool, string name, string symbol);

    address public immutable WETH;

    address[] public pools;

    constructor(address weth_) {
        WETH = weth_;
    }

    function createRMM(string memory poolName, string memory poolSymbol, address PT, uint256 sigma, uint256 fee)
        external
        returns (RMM)
    {
        RMM rmm = new RMM(poolName, poolSymbol, PT, sigma, fee);
        emit NewPool(msg.sender, address(rmm), poolName, poolSymbol);
        pools.push(address(rmm));
        return rmm;
    }
}
