// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {PYIndexLib, PYIndex} from "pendle/core/StandardizedYield/PYIndex.sol";
import {IPYieldToken} from "pendle/interfaces/IPYieldToken.sol";
import {computeTauWadYears, PoolPreCompute, computeLGivenX, computeY, solveL} from "./lib/RmmLib.sol";
import {RMM} from "./RMM.sol";

contract Factory {
    using PYIndexLib for IPYieldToken;
    using PYIndexLib for PYIndex;

    event NewPool(address indexed caller, address indexed pool, string name, string symbol);

    address public immutable WETH;

    address[] public pools;

    constructor(address weth_) {
        WETH = weth_;
    }

    function createRMM(
        string memory poolName,
        string memory poolSymbol,
        address PT_,
        uint256 priceX,
        uint256 amountX,
        uint256 strike_,
        uint256 sigma_,
        uint256 fee_,
        address curator_
    ) external returns (RMM) {
        RMM rmm = new RMM(WETH, poolName, poolSymbol, PT_, priceX, amountX, strike_, sigma_, fee_, curator_);
        emit NewPool(msg.sender, address(rmm), poolName, poolSymbol);
        pools.push(address(rmm));
        return rmm;
    }

    function prepareInit(
        uint256 priceX,
        uint256 amountX,
        uint256 strike_,
        uint256 sigma_,
        uint256 maturity_,
        PYIndex index
    ) public view returns (uint256 totalLiquidity_, uint256 amountY) {
        uint256 totalAsset = index.syToAsset(amountX);
        uint256 tau_ = computeTauWadYears(maturity_ - block.timestamp);
        PoolPreCompute memory comp = PoolPreCompute({reserveInAsset: totalAsset, strike_: strike_, tau_: tau_});
        uint256 initialLiquidity =
            computeLGivenX({reserveX_: totalAsset, S: priceX, strike_: strike_, sigma_: sigma_, tau_: tau_});
        amountY =
            computeY({reserveX_: totalAsset, liquidity: initialLiquidity, strike_: strike_, sigma_: sigma_, tau_: tau_});
        totalLiquidity_ = solveL(comp, initialLiquidity, amountY, sigma_);
    }
}
