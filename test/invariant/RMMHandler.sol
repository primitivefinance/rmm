/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {CommonBase} from "forge-std/Base.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IPPrincipalToken} from "pendle/interfaces/IPPrincipalToken.sol";
import {PendleWstEthSY} from "pendle/core/StandardizedYield/implementations/PendleWstEthSY.sol";
import {IPYieldToken} from "pendle/interfaces/IPYieldToken.sol";
import {RMM} from "../../src/RMM.sol";
import {PYIndex} from "./../../src/RMM.sol";
import {AddressSet, LibAddressSet} from "../helpers/AddressSet.sol";

contract RMMHandler is CommonBase, StdUtils {
    using LibAddressSet for AddressSet;

    RMM public rmm;
    PendleWstEthSY public SY;
    IPYieldToken public YT;
    IPPrincipalToken public PT;

    uint256 public ghost_reserveX;
    uint256 public ghost_reserveY;
    uint256 public ghost_totalLiquidity;
    uint256 public ghost_totalSupply;

    mapping(bytes32 => uint256) public calls;
    uint256 public totalCalls;

    AddressSet internal actors;
    address internal currentActor;

    modifier createActor() {
        currentActor = msg.sender;
        actors.add(currentActor);
        _;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors.rand(actorIndexSeed);
        _;
    }

    modifier countCall(bytes32 key) {
        calls[key]++;
        totalCalls++;
        _;
    }

    constructor(RMM rmm_, IPPrincipalToken PT_, PendleWstEthSY SY_, IPYieldToken YT_) {
        rmm = rmm_;
        PT = PT_; // Not sure if passing around the PT here is the best way to do this...
        SY = SY_;
        YT = YT_;
    }

    // Utility functions

    function give(address token, address to, uint256 amount) public {
        ERC20(token).transfer(to, amount);
    }

    function init() public {
        /*
        priceX = bound(priceX, 1 ether, 10 ether);
        amountX = bound(amountX, 1 ether, 10 ether);
        strike = bound(strike, 1 ether, 10 ether);
        sigma = bound(sigma, 0 ether, 1 ether);
        fee = bound(fee, 0 ether, 1 ether);
        */

        uint256 priceX = 1 ether;
        uint256 amountX = 1 ether;
        uint256 strike = 1 ether;
        uint256 sigma = 0.015 ether;
        uint256 fee = 0.00016 ether;

        (uint256 totalLiquidity, uint256 amountY) = rmm.prepareInit(priceX, amountX, strike, sigma, PT.expiry());

        PT.approve(address(rmm), type(uint256).max);
        SY.approve(address(rmm), type(uint256).max);

        rmm.init(address(PT), priceX, amountX, strike, sigma, fee, address(0));

        ghost_reserveX += amountX;
        ghost_reserveY += amountY;
        ghost_totalLiquidity += totalLiquidity;
    }

    // Target functions

    function allocate() public createActor countCall("allocate") {
        give(address(PT), currentActor, 0.1 ether);
        give(address(SY), currentActor, 0.1 ether);

        vm.startPrank(currentActor);

        PT.approve(address(rmm), type(uint256).max);
        SY.approve(address(rmm), type(uint256).max);

        (uint256 deltaXWad, uint256 deltaYWad,,) =
            rmm.prepareAllocate(0.1 ether, 0.1 ether, PYIndex.wrap(rmm.YT().pyIndexCurrent()));
        uint256 deltaLiquidity = rmm.allocate(deltaXWad, deltaYWad, 0, address(this));

        vm.stopPrank();

        ghost_totalLiquidity += deltaLiquidity;
        ghost_reserveX += deltaXWad;
        ghost_reserveY += deltaYWad;
    }

    function deallocate(uint256 actorSeed) public useActor(actorSeed) countCall("deallocate") {
        vm.startPrank(currentActor);
        vm.stopPrank();

        // (uint256 deltaXWad, uint256 deltaYWad, uint256 lptBurned) = rmm.prepareDeallocate(deltaLiquidity / 2);

        // uint256 preTotalLiquidity = rmm.totalLiquidity();
        // rmm.deallocate(deltaLiquidity / 2, 0, 0, address(this));

        /*
        ghost_totalLiquidity -= deltaLiquidity;
        ghost_reserveX -= deltaXWad;
        ghost_reserveY -= deltaYWad;
        */
    }
}
