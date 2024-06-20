/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {CommonBase} from "forge-std/Base.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {PYIndex, PYIndexLib} from "pendle/core/StandardizedYield/PYIndex.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IPPrincipalToken} from "pendle/interfaces/IPPrincipalToken.sol";
import {PendleWstEthSY} from "pendle/core/StandardizedYield/implementations/PendleWstEthSY.sol";
import {IPYieldToken} from "pendle/interfaces/IPYieldToken.sol";
import {RMM} from "../../src/RMM.sol";
import {PYIndex} from "./../../src/RMM.sol";
import {AddressSet, LibAddressSet} from "../helpers/AddressSet.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract RMMHandler is CommonBase, StdUtils, StdCheats {
    using LibAddressSet for AddressSet;
    using PYIndexLib for IPYieldToken;
    using FixedPointMathLib for uint256;

    RMM public rmm;
    PendleWstEthSY public SY;
    IPYieldToken public YT;
    IPPrincipalToken public PT;

    uint256 public ghost_reserveX;
    uint256 public ghost_reserveY;
    uint256 public ghost_totalLiquidity;
    uint256 public ghost_totalSupply;

    mapping(bytes4 => uint256) public calls;
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
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    modifier countCall(bytes4 key) {
        calls[key]++;
        totalCalls++;
        _;
    }

    constructor(RMM rmm_, IPPrincipalToken PT_, PendleWstEthSY SY_, IPYieldToken YT_) {
        rmm = rmm_;
        PT = PT_;
        SY = SY_;
        YT = YT_;
    }

    // Utility functions

    function give(address token, address to, uint256 amount) public {
        ERC20(token).transfer(to, amount);
    }

    function mintPY(uint256 amount, address to) internal returns (uint256 amountPY) {
        SY.transfer(address(YT), amount);
        amountPY = YT.mintPY(to, to);
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

    function allocate(uint256 deltaX, uint256 deltaY) public createActor countCall(this.allocate.selector) {
        deltaX = bound(deltaX, 0.1 ether, 0.5 ether);
        deltaY = bound(deltaY, 0.1 ether, 0.5 ether);

        deal(address(SY), currentActor, deltaX);
        deal(address(PT), currentActor, deltaY);

        vm.startPrank(currentActor);

        // rmm.mintSY{value: deltaX + deltaY}(currentActor, address(0), deltaX + deltaY, 0);
        // mintPY(deltaY, currentActor);

        SY.approve(address(rmm), deltaX);
        PT.approve(address(rmm), deltaY);

        (uint256 deltaXWad, uint256 deltaYWad,,) =
            rmm.prepareAllocate(0.1 ether, 0.1 ether, PYIndex.wrap(rmm.YT().pyIndexCurrent()));
        uint256 deltaLiquidity = rmm.allocate(deltaXWad, deltaYWad, 0, address(currentActor));

        vm.stopPrank();

        ghost_totalLiquidity += deltaLiquidity;
        ghost_reserveX += deltaXWad;
        ghost_reserveY += deltaYWad;
    }

    function deallocate(uint256 actorSeed) public useActor(actorSeed) countCall(this.deallocate.selector) {
        uint256 deltaLiquidity = rmm.totalLiquidity() * rmm.balanceOf(currentActor) / rmm.totalSupply();
        (uint256 deltaXWad, uint256 deltaYWad,) = rmm.prepareDeallocate(deltaLiquidity);
        rmm.deallocate(deltaLiquidity, 0, 0, address(this));

        ghost_reserveX -= deltaXWad;
        ghost_reserveY -= deltaYWad;
        ghost_totalLiquidity -= deltaLiquidity;
    }

    function swapExactSyForYt() public createActor countCall(this.swapExactSyForYt.selector) {
        uint256 exactSYIn = 1 ether;
        deal(address(SY), address(currentActor), exactSYIn);

        vm.startPrank(currentActor);
        SY.approve(address(rmm), exactSYIn);
        PYIndex index = YT.newIndex();
        uint256 ytOut = rmm.computeSYToYT(index, exactSYIn, 500 ether, block.timestamp, 0, 10_000);
        (uint256 amtOut,) =
            rmm.swapExactSyForYt(exactSYIn, ytOut, ytOut.mulDivDown(95, 100), 500 ether, 10_000, address(msg.sender));
        vm.stopPrank();
    }

    function swapExactTokenForYt() public createActor countCall(this.swapExactTokenForYt.selector) {}

    function swapExactPtForSy() public createActor countCall(this.swapExactPtForSy.selector) {}

    function swapExactSyForPt() public createActor countCall(this.swapExactSyForPt.selector) {}

    function swapExactYtForSy() public createActor countCall(this.swapExactYtForSy.selector) {}
}
