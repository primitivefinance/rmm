/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SetUp, RMM, InitParams} from "./SetUp.sol";

contract InitTest is SetUp {
    function test_init_StoresInitParams() public {
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
    }

    function test_init_StoresTokens() public {
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

    function test_init_MintsLiquidity() public {
        InitParams memory initParams = getDefaultParams();

        (uint256 totalLiquidity,) = rmm.prepareInit(
            initParams.priceX, initParams.totalAsset, initParams.strike, initParams.sigma, initParams.maturity
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

    function test_init_AdjustsPool() public {
        InitParams memory initParams = getDefaultParams();

        (, uint256 amountY) = rmm.prepareInit(
            initParams.priceX, initParams.totalAsset, initParams.strike, initParams.sigma, initParams.maturity
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

        assertEq(rmm.lastTimestamp(), block.timestamp);
        assertEq(rmm.reserveX(), initParams.amountX);
        assertEq(rmm.reserveY(), amountY);
    }

    function test_init_TransfersTokens() public {
        InitParams memory initParams = getDefaultParams();

        (, uint256 amountY) = rmm.prepareInit(
            initParams.priceX, initParams.totalAsset, initParams.strike, initParams.sigma, initParams.maturity
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

    function test_init_EmitsInitEvent() public {
        InitParams memory initParams = getDefaultParams();

        (uint256 totalLiquidity, uint256 amountY) = rmm.prepareInit(
            initParams.priceX, initParams.totalAsset, initParams.strike, initParams.sigma, initParams.maturity
        );

        vm.expectEmit(true, true, true, true);

        emit RMM.Init(
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

    function test_init_RevertsIfAlreadyInitialized() public initDefaultPool {
        InitParams memory initParams = getDefaultParams();

        vm.expectRevert(RMM.AlreadyInitialized.selector);

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

    function test_init_RevertsWhenLocked() public {
        vm.skip(true);
    }
}