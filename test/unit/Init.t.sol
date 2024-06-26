/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SetUp, RMM, InitParams} from "../SetUp.sol";
import {Init} from "../../src/lib/RmmEvents.sol";
import {AlreadyInitialized, InvalidStrike} from "../../src/lib/RmmErrors.sol";
import {PYIndex, PYIndexLib, IPYieldToken} from "./../../src/RMM.sol";

contract InitTest is SetUp {
    using PYIndexLib for IPYieldToken;
    using PYIndexLib for PYIndex;

    function test_init_StoresInitParams()
        public
        withSY(address(this), 2000000 ether)
        withPY(address(this), 1000000 ether)
    {
        InitParams memory initParams = getDefaultParams();

        rmm.init(
            initParams.PT,
            initParams.priceX,
            initParams.amountX,
            initParams.strike,
            initParams.sigma,
            initParams.fee,
            initParams.curator
        );

        assertEq(rmm.strike(), initParams.strike);
        assertEq(rmm.sigma(), initParams.sigma);
        assertEq(rmm.fee(), initParams.fee);
        assertEq(rmm.maturity(), initParams.maturity);
        assertEq(rmm.curator(), initParams.curator);
        assertEq(rmm.lastTimestamp(), block.timestamp);
        assertEq(rmm.initTimestamp(), block.timestamp);
    }

    function test_init_StoresTokens()
        public
        withSY(address(this), 2000000 ether)
        withPY(address(this), 1000000 ether)
    {
        InitParams memory initParams = getDefaultParams();

        rmm.init(
            initParams.PT,
            initParams.priceX,
            initParams.amountX,
            initParams.strike,
            initParams.sigma,
            initParams.fee,
            initParams.curator
        );

        assertEq(address(rmm.PT()), address(PT));
        assertEq(address(rmm.YT()), address(YT));
        assertEq(address(rmm.SY()), address(SY));
    }

    function test_init_MintsLiquidity()
        public
        withSY(address(this), 2000000 ether)
        withPY(address(this), 1000000 ether)
    {
        InitParams memory initParams = getDefaultParams();
        PYIndex index = IPYieldToken(PT.YT()).newIndex();

        (uint256 totalLiquidity,) = rmm.prepareInit(
            initParams.priceX, initParams.amountX, initParams.strike, initParams.sigma, initParams.maturity, index
        );

        rmm.init(
            initParams.PT,
            initParams.priceX,
            initParams.amountX,
            initParams.strike,
            initParams.sigma,
            initParams.fee,
            initParams.curator
        );

        assertEq(rmm.totalLiquidity(), totalLiquidity);
        assertEq(rmm.balanceOf(address(this)), totalLiquidity - rmm.BURNT_LIQUIDITY());
        assertEq(rmm.balanceOf(address(0)), rmm.BURNT_LIQUIDITY());
    }

    function test_init_AdjustsPool() public withSY(address(this), 2000000 ether) withPY(address(this), 1000000 ether) {
        InitParams memory initParams = getDefaultParams();
        PYIndex index = IPYieldToken(PT.YT()).newIndex();

        (, uint256 amountY) = rmm.prepareInit(
            initParams.priceX, initParams.amountX, initParams.strike, initParams.sigma, initParams.maturity, index
        );

        rmm.init(
            initParams.PT,
            initParams.priceX,
            initParams.amountX,
            initParams.strike,
            initParams.sigma,
            initParams.fee,
            initParams.curator
        );

        assertEq(rmm.lastTimestamp(), block.timestamp, "lastTimestamp");
        assertEq(rmm.reserveX(), initParams.amountX, "reserveX");
        assertEq(rmm.reserveY(), amountY, "reserveY");
    }

    function test_init_TransfersTokens()
        public
        withSY(address(this), 2000000 ether)
        withPY(address(this), 1000000 ether)
    {
        InitParams memory initParams = getDefaultParams();
        PYIndex index = IPYieldToken(PT.YT()).newIndex();

        (, uint256 amountY) = rmm.prepareInit(
            initParams.priceX, initParams.amountX, initParams.strike, initParams.sigma, initParams.maturity, index
        );

        uint256 thisPreBalanceSY = SY.balanceOf(address(this));
        uint256 thisPreBalancePT = PT.balanceOf(address(this));
        uint256 rmmPreBalanceSY = SY.balanceOf(address(rmm));
        uint256 rmmPreBalancePT = PT.balanceOf(address(rmm));

        rmm.init(
            initParams.PT,
            initParams.priceX,
            initParams.amountX,
            initParams.strike,
            initParams.sigma,
            initParams.fee,
            initParams.curator
        );

        assertEq(SY.balanceOf(address(this)), thisPreBalanceSY - initParams.amountX);
        assertEq(PT.balanceOf(address(this)), thisPreBalancePT - amountY);
        assertEq(SY.balanceOf(address(rmm)), rmmPreBalanceSY + initParams.amountX);
        assertEq(PT.balanceOf(address(rmm)), rmmPreBalancePT + amountY);
    }

    function test_init_EmitsInitEvent()
        public
        withSY(address(this), 2000000 ether)
        withPY(address(this), 1000000 ether)
    {
        InitParams memory initParams = getDefaultParams();
        PYIndex index = IPYieldToken(PT.YT()).newIndex();

        (uint256 totalLiquidity, uint256 amountY) = rmm.prepareInit(
            initParams.priceX, initParams.amountX, initParams.strike, initParams.sigma, initParams.maturity, index
        );

        vm.expectEmit(true, true, true, true);

        emit Init(
            address(this),
            address(SY),
            address(PT),
            initParams.amountX,
            amountY,
            totalLiquidity,
            initParams.strike,
            initParams.sigma,
            initParams.fee,
            initParams.maturity,
            initParams.curator
        );

        rmm.init(
            initParams.PT,
            initParams.priceX,
            initParams.amountX,
            initParams.strike,
            initParams.sigma,
            initParams.fee,
            initParams.curator
        );
    }

    function test_init_RevertsIfAlreadyInitialized()
        public
        useDefaultPool
        withSY(address(this), 2000000 ether)
        withPY(address(this), 1000000 ether)
    {
        InitParams memory initParams = getDefaultParams();

        vm.expectRevert(AlreadyInitialized.selector);

        rmm.init(
            initParams.PT,
            initParams.priceX,
            initParams.amountX,
            initParams.strike,
            initParams.sigma,
            initParams.fee,
            initParams.curator
        );
    }

    function test_init_RevertsIfInvalidStrike()
        public
        withSY(address(this), 2000000 ether)
        withPY(address(this), 1000000 ether)
    {
        InitParams memory initParams = getDefaultParams();

        vm.expectRevert(abi.encodeWithSelector(InvalidStrike.selector));

        rmm.init(
            initParams.PT,
            initParams.priceX,
            initParams.amountX,
            1 ether,
            initParams.sigma,
            initParams.fee,
            initParams.curator
        );
    }

    function test_init_RevertsWhenLocked()
        public
        withSY(address(this), 2000000 ether)
        withPY(address(this), 1000000 ether)
    {
        vm.skip(true);
    }
}
