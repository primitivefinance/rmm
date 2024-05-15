/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SetUp} from "./SetUp.sol";

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

    function test_init_works() public {
        InitParams memory initParams = InitParams({
            priceX: 1 ether,
            totalAsset: 1 ether,
            strike: 1 ether,
            sigma: 0.015 ether,
            maturity: block.timestamp + 180 days,
            PT: address(PT),
            amountX: 1 ether,
            fee: 0.00016 ether,
            curator: address(0x55)
        });

        (uint256 totalLiquidity, uint256 amountY) = rmm.prepareInit(
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
    }

    function test_init_StoresTokens() public {}

    function test_init_EmitsInitEvent() public {}

    function test_init_RevertsIfAlreadyInitialized() public {}

    function test_init_RevertsWhenLocked() public {}
}
