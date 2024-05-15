/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SetUp, RMM} from "./SetUp.sol";

contract InitTest is SetUp {
    struct InitParams {
        uint256 priceX;
        uint256 totalAsset;
        uint256 strike;
        uint256 sigma;
        uint256 maturity;
        address PT;
        uint256 amountX;
        uint256 fee;
        address curator;
    }

    modifier initDefaultPool() {
        rmm.init(address(PT), 1 ether, 1 ether, 1 ether, 0.015 ether, 0.00016 ether, address(0x55));
        _;
    }

    function test_init_StoresInitParams() public {
        InitParams memory initParams = InitParams({
            priceX: 1 ether,
            totalAsset: 1 ether,
            strike: 1 ether,
            sigma: 0.015 ether,
            maturity: PT.expiry(),
            PT: address(PT),
            amountX: 1 ether,
            fee: 0.00016 ether,
            curator: address(0x55)
        });

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

    function test_init_StoresTokens() public initDefaultPool {
        assertEq(address(rmm.PT()), address(PT));
        assertEq(address(rmm.YT()), address(YT));
        assertEq(address(rmm.SY()), address(SY));
    }

    function test_init_EmitsInitEvent() public {
        InitParams memory initParams = InitParams({
            priceX: 1 ether,
            totalAsset: 1 ether,
            strike: 1 ether,
            sigma: 0.015 ether,
            maturity: PT.expiry(),
            PT: address(PT),
            amountX: 1 ether,
            fee: 0.00016 ether,
            curator: address(0x55)
        });

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

    function test_init_RevertsIfAlreadyInitialized() public {}

    function test_init_RevertsWhenLocked() public {}
}
