// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20, RMM, PoolPreCompute} from "../src/RMM.sol";
import {LiquidityManager} from "../src/LiquidityManager.sol";
import {Factory} from "../src/Factory.sol";

import {computeSpotPrice} from "../src/lib/RmmLib.sol";

import {IPMarket} from "pendle/interfaces/IPMarket.sol";
import {IStandardizedYield} from "pendle/interfaces/IStandardizedYield.sol";
import {IPYieldToken} from "pendle/interfaces/IPYieldToken.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {RmmArbitrage, RmmParams} from "./RmmArbitrage.sol";
import {ArbMath} from "./ArbMath.sol";
import {Gaussian} from "../lib/solstat/src/Gaussian.sol";
import { SignedWadMathLib } from "./SignedWadMathLib.sol";

import "pendle/core/Market/MarketMathCore.sol";
import "pendle/interfaces/IPAllActionV3.sol";

contract ComputeArb is Script, RmmArbitrage, ArbMath {
    using MarketMathCore for MarketState;
    using MarketMathCore for int256;
    using MarketMathCore for uint256;
    using FixedPointMathLib for uint256;
    using PYIndexLib for IPYieldToken;
    using PYIndexLib for PYIndex;
using SignedWadMathLib for int256;

    uint256 mainnetFork;
    uint256 testnetFork;

    IPMarket market = IPMarket(0xC374f7eC85F8C7DE3207a10bB1978bA104bdA3B2);
    IPAllActionV3 router = IPAllActionV3(0x00000000005BBB0EF59571E58418F9a4357b68A0);
    address wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0; //real wsteth

    IStandardizedYield public SY;
    IPPrincipalToken public PT;
    IPYieldToken public YT;
    MarketState public mktState;

    int256 rateAnchor;
    int256 rateScalar;
    uint256 timeToExpiry;

    RMM rmm = RMM(payable(0xE3fFcA31BBA27392aF23B8018bd59c399f843093));

    address sender;

    string public constant ENV_PRIVATE_KEY = "PRIVATE_KEY";

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        testnetFork = vm.createFork(vm.envString("TESTNET_RPC_URL"));

        vm.selectFork(mainnetFork);

        (SY, PT, YT) = IPMarket(market).readTokens();
        mktState = market.readState(address(router));
        timeToExpiry = mktState.expiry - block.timestamp;
    }

    function mintSY(uint256 amount) public {
        console2.log("balance wsteth", IERC20(wstETH).balanceOf(sender));
        IERC20(wstETH).approve(address(SY), type(uint256).max);
        SY.deposit(sender, address(wstETH), amount, 1);
    }

    function mintPtYt(uint256 amount) public {
        SY.transfer(address(YT), amount);
        YT.mintPY(sender, sender);
    }


    function getPtExchangeRate(PYIndex index) public view returns (int256) {
        (MarketState memory ms, MarketPreCompute memory mp) = getPendleMarketData(index);
        return ms.totalPt._getExchangeRate(mp.totalAsset, mp.rateScalar, mp.rateAnchor, 0);
    }

    function getPendleMarketData(PYIndex index)
        public
        view
        returns (MarketState memory ms, MarketPreCompute memory mp)
    {
        ms = market.readState(address(router));
        mp = ms.getMarketPreCompute(index, block.timestamp);
    }

    function run() public {
        uint256 pk = vm.envUint(ENV_PRIVATE_KEY);
        sender = vm.addr(pk);

        PYIndex mainnetIndex = YT.newIndex();

        // compute optimal arbitrage to rmm pool
        uint256 pendleRate = uint256(getPtExchangeRate(mainnetIndex));

        vm.selectFork(testnetFork);
        PYIndex index = YT.newIndex();
        vm.startBroadcast(pk);

        IERC20(wstETH).approve(address(rmm), type(uint256).max);
        IERC20(SY).approve(address(rmm), type(uint256).max);
        IERC20(PT).approve(address(rmm), type(uint256).max);
        IERC20(YT).approve(address(rmm), type(uint256).max);

        uint256 L = rmm.totalLiquidity();

        PoolPreCompute memory comp = rmm.preparePoolPreCompute(index, block.timestamp);

        uint256 rmmPrice = computeSpotPrice(comp.reserveInAsset, L, comp.strike_, rmm.sigma(), comp.tau_);

        console2.log("rmmPrice: ", rmmPrice);
        console2.log("pendleRate: ", pendleRate);
        console2.log("asset reserve: ", comp.reserveInAsset);

        if (pendleRate > rmmPrice) {
            int256 dy = getDyGivenS(address(rmm), pendleRate, index);
            console2.log("dy: ", dy);
            uint256 amt = computeOptimalArbRaisePrice(address(rmm), pendleRate, uint256(dy), index);
            console2.log("Amount to lower: ", amt);
            mintSY(amt);
            mintPtYt(rmm.SY().balanceOf(address(this)));
            (uint256 amtOut, ) = rmm.swapExactPtForSy(amt, 0, address(this));
            console2.log("amtOut: ", amtOut);
        } else {
            console2.log("lower!");
            int256 dx = getDxGivenS(address(rmm), pendleRate, index);
            console2.log("dx: ", dx);
            uint256 amt = index.assetToSy(computeOptimalArbLowerPrice(address(rmm), pendleRate, uint256(dx), index));
            mintSY(amt);
            (uint256 amtOut, ) = rmm.swapExactSyForPt(amt, 0, address(this));
            console2.log("amtOut: ", amtOut);
        }

        vm.stopBroadcast();
    }
}
