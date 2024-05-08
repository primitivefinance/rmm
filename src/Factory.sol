// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {RMM} from "./RMM.sol";

contract Factory {
    event NewPool(address indexed caller, address indexed pool, string name, string symbol);

    address public immutable WETH;

    constructor(address weth_) {
        WETH = weth_;
    }

    function createRMM(string memory poolName, string memory poolSymbol) external returns (RMM) {
        RMM rmm = new RMM(WETH, poolName, poolSymbol);
        emit NewPool(msg.sender, address(rmm), poolName, poolSymbol);
        return rmm;
    }
}
