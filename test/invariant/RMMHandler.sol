/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {CommonBase} from "forge-std/Base.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";
import {PYIndex, PYIndexLib} from "pendle/core/StandardizedYield/PYIndex.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IPPrincipalToken} from "pendle/interfaces/IPPrincipalToken.sol";
import {PendleWstEthSY} from "pendle/core/StandardizedYield/implementations/PendleWstEthSY.sol";
import {IPYieldToken} from "pendle/interfaces/IPYieldToken.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {RMM} from "../../src/RMM.sol";
import {PYIndex} from "./../../src/RMM.sol";
import {AddressSet, LibAddressSet} from "../helpers/AddressSet.sol";

import "forge-std/console2.sol";

contract RMMHandler is CommonBase, StdUtils, StdCheats {
    using LibAddressSet for AddressSet;
    using PYIndexLib for IPYieldToken;
    using FixedPointMathLib for uint256;

    RMM public rmm;
    PendleWstEthSY public SY;
    IPYieldToken public YT;
    IPPrincipalToken public PT;
    WETH public weth;

    uint256 public ghost_reserveX;
    uint256 public ghost_reserveY;
    int256 public ghost_totalLiquidity;
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

    constructor(RMM rmm_, IPPrincipalToken PT_, PendleWstEthSY SY_, IPYieldToken YT_, WETH weth_) {
        rmm = rmm_;
        PT = PT_;
        SY = SY_;
        YT = YT_;
        weth = weth_;
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
        uint256 priceX;
        uint256 amountX;
        uint256 strike;
        uint256 sigma;
        uint256 fee;

        priceX = bound(priceX, 1.05 ether, 1.15 ether);
        amountX = bound(amountX, 100 ether, 1000 ether);
        strike = bound(strike, 1.05 ether, 1.15 ether);
        sigma = bound(sigma, 0.03 ether, 0.05 ether);
        fee = bound(fee, 0.0001 ether, 0.001 ether);

        PYIndex index = IPYieldToken(PT.YT()).newIndex();

        (uint256 totalLiquidity, uint256 amountY) = rmm.prepareInit(priceX, amountX, strike, sigma, index);

        PT.approve(address(rmm), type(uint256).max);
        SY.approve(address(rmm), type(uint256).max);
        YT.approve(address(rmm), type(uint256).max);

        rmm.init(priceX, amountX, strike);

        ghost_reserveX += amountX;
        ghost_reserveY += amountY;
        ghost_totalLiquidity += int256(totalLiquidity);
    }

    // Target functions

    function allocate(uint256 deltaX, uint256 deltaY) public createActor countCall(this.allocate.selector) {
        deltaX = bound(deltaX, 0.1 ether, 10 ether);

        vm.startPrank(currentActor);

        (uint256 deltaXWad, uint256 deltaYWad, uint256 deltaLiquidity,) = rmm.prepareAllocate(true, deltaX);

        deal(address(SY), currentActor, deltaXWad);
        deal(address(PT), currentActor, deltaYWad);

        SY.approve(address(rmm), deltaXWad);
        PT.approve(address(rmm), deltaYWad);
        uint256 realDeltaLiquidity = rmm.allocate(true, deltaX, deltaLiquidity, address(currentActor));

        vm.stopPrank();

        ghost_totalLiquidity += int256(realDeltaLiquidity);
        ghost_reserveX += deltaXWad;
        ghost_reserveY += deltaYWad;
    }

    function deallocate(uint256 actorSeed) public useActor(actorSeed) countCall(this.deallocate.selector) {
        uint256 deltaLiquidity = rmm.totalLiquidity() * rmm.balanceOf(currentActor) / rmm.totalSupply();
        (uint256 deltaXWad, uint256 deltaYWad,) = rmm.prepareDeallocate(deltaLiquidity);
        rmm.deallocate(deltaLiquidity, 0, 0, address(this));

        ghost_reserveX -= deltaXWad;
        ghost_reserveY -= deltaYWad;
        ghost_totalLiquidity -= int256(deltaLiquidity);
    }

    function swapExactSyForYt() public createActor countCall(this.swapExactSyForYt.selector) {
        uint256 exactSYIn = 1 ether;
        deal(address(SY), address(currentActor), exactSYIn);

        PYIndex index = YT.newIndex();
        uint256 ytOut = rmm.computeSYToYT(index, exactSYIn, 0, block.timestamp, 0, 1_000);

        vm.startPrank(currentActor);
        SY.approve(address(rmm), exactSYIn);
        (uint256 amountInWad, uint256 amountOutWad,, int256 deltaLiquidity,) =
            rmm.prepareSwapPtIn(ytOut, block.timestamp, index);
        rmm.swapExactSyForYt(exactSYIn, ytOut, ytOut.mulDivDown(95, 100), ytOut, 1_000, address(msg.sender));
        vm.stopPrank();
        console2.log("h");
        console2.log("ghost_reserveX", ghost_reserveX);
        console2.log("rx", rmm.reserveX());
        console2.log("ghost_reserveY", ghost_reserveY);
        console2.log("ry", rmm.reserveY());
        console2.log("ghost_totalLiquidity", ghost_totalLiquidity);
        console2.log("amountOutWad", amountOutWad);
        console2.log("amountInWad", amountInWad);
        console2.log("deltaLiquidity", deltaLiquidity);
        ghost_reserveX -= amountOutWad;
        console2.log("h1");
        ghost_reserveY += amountInWad;
        console2.log("h2");
        ghost_totalLiquidity += int256(deltaLiquidity);
    }

    function swapExactTokenForYt() public createActor countCall(this.swapExactTokenForYt.selector) {
        uint256 amountTokenIn = 1 ether;
        deal(currentActor, amountTokenIn);

        vm.startPrank(currentActor);
        weth.deposit{value: amountTokenIn}();

        PYIndex index = YT.newIndex();

        (uint256 syMinted, uint256 ytOut) = rmm.computeTokenToYT(
            index, address(weth), amountTokenIn, 0, block.timestamp, 0, 1_000
        );

        weth.approve(address(rmm), amountTokenIn);
        (uint256 amountInWad, uint256 amountOutWad, int256 deltaLiquidity) = rmm.swapExactTokenForYt(
            address(weth),
            amountTokenIn,
            ytOut,
            syMinted,
            ytOut,
            10 ether,
            0.005 ether,
            address(currentActor)
        );

        vm.stopPrank();

        ghost_reserveX -= amountOutWad;
        ghost_reserveY += amountInWad;
        ghost_totalLiquidity += deltaLiquidity;
    }

    function swapExactPtForSy() public createActor countCall(this.swapExactPtForSy.selector) {
        uint256 amountIn = 1 ether;
        deal(address(PT), currentActor, amountIn);
        vm.startPrank(currentActor);
        PT.approve(address(rmm), amountIn);
        (uint256 amountOut, int256 deltaLiquidity) = rmm.swapExactPtForSy(amountIn, 0, address(currentActor));
        vm.stopPrank();

        ghost_reserveX -= amountOut;
        ghost_reserveY += amountIn;
        ghost_totalLiquidity += int256(deltaLiquidity);
    }

    function swapExactSyForPt() public createActor countCall(this.swapExactSyForPt.selector) {
        uint256 amountIn = 1 ether;
        deal(address(SY), currentActor, amountIn);
        vm.startPrank(currentActor);
        SY.approve(address(rmm), amountIn);
        (uint256 amountOut, int256 deltaLiquidity) = rmm.swapExactSyForPt(amountIn, 0, address(currentActor));
        vm.stopPrank();

        ghost_reserveX += amountIn;
        ghost_reserveY -= amountOut;
        ghost_totalLiquidity += int256(deltaLiquidity);
    }

    function swapExactYtForSy() public createActor countCall(this.swapExactYtForSy.selector) {
        uint256 ytIn = 1 ether;

        deal(address(YT), currentActor, ytIn);
        vm.startPrank(currentActor);
        YT.approve(address(rmm), ytIn);
        console2.log("YT Balance", YT.balanceOf(currentActor));
        (uint256 amountOut, uint256 amountIn, int256 deltaLiquidity) =
            rmm.swapExactYtForSy(ytIn, 1000 ether, address(currentActor));
        vm.stopPrank();

        // the workflow here is:
        // 1. YT -> RMM
        // 2. Flash amountYt of PT from RMM, so the reserveY should be reduced by ytIn
        // 3. recombine the YT and PT into SY
        // 4. send the SY to rmm to cover the cost of the PT
        // 5. remainder SY sent to currentActor
        // in the end the reserves are mutated such that rY = rYStart - ytIn, rX = rXStart + syCreated - sySwapped
        // ghost_reserveX += amountIn;
        console2.log("ghost_reserveY", ghost_reserveY);
        console2.log("amountIn", amountIn);
        console2.log("ghost_reserveY - amountIn", ghost_reserveY - amountIn);
        console2.log("rmm.reserveY()", rmm.reserveY());
        ghost_reserveY -= ytIn;
        // ghost_totalLiquidity += int256(deltaLiquidity);
    }

    function increaseTime(uint256 amount) public countCall(this.increaseTime.selector) {
        amount = bound(amount, 1, 86400);

        vm.warp(block.timestamp + amount);
    }
}
