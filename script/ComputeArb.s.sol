// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {RMM, PoolPreCompute} from "../src/RMM.sol";
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

    string public constant ENV_PRIVATE_KEY = "PRIVATE_KEY";

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        testnetFork = vm.createFork(vm.envString("TESTNET_RPC_URL"));

        vm.selectFork(mainnetFork);

        (SY, PT, YT) = IPMarket(market).readTokens();
        mktState = market.readState(address(router));
        timeToExpiry = mktState.expiry - block.timestamp;
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

    function getDy() public view returns (uint256) {
        return rmm.reserveY() - 50 ether;
    }

    function getDy(uint256 targetPrice, RmmParams memory params) public pure returns (int256) {
        uint256 sqrtTau = FixedPointMathLib.sqrt(params.tau) * 1e9;
        int256 gamma = int256(1 ether - params.fee);

        int256 logP = log(int256(targetPrice.divWadDown(params.K)));
        int256 innerP = logP.wadDiv(int256(params.sigma)) - int256(params.sigma.mulWadDown(sqrtTau).divWadDown(2 ether));
        int256 cdfP = Gaussian.cdf(innerP);
        int256 delta = int256(params.L.mulWadDown(params.K)) * cdfP;

        int256 dy = (delta - int256(params.rY)).wadDiv(gamma - 1 ether).wadMul(cdfP).wadDiv(int256(params.rY).wadDiv(int256(params.K.mulWadDown(params.L))) + 1 ether);
        return dy;
    }

    function getDx(uint256 targetPrice, RmmParams memory params) public pure returns (int256) {
        uint256 sqrtTau = FixedPointMathLib.sqrt(params.tau) * 1e9;
        int256 gamma = int256(1 ether - params.fee);

        int256 logP = log(int256(targetPrice.divWadDown(params.K)));
        console2.log("logP: ", logP);
        int256 innerP = logP.wadDiv(int256(params.sigma)) + int256(params.sigma.mulWadDown(sqrtTau).divWadDown(2 ether));
        console2.log("innerP: ", innerP);
        int256 cdfP = Gaussian.cdf(innerP);
        console2.log("cdfP: ", cdfP);
        int256 delta = int256(params.L).wadMul(1 ether - cdfP);
        // console2.log("delta: ", delta);
        // int256 dx = (delta - int256(params.rX)).wadDiv((gamma - 1 ether).wadMul(1 ether - cdfP).wadDiv(int256(params.rX).wadDiv(int256(params.L)) + 1 ether));
        // console2.log("dx: ", dx);
        return delta;
    }

    //  pub async fn get_dx(&self) -> Result<I256> {
    //     let ArbInputs {
    //         i_wad,
    //         target_price_wad,
    //         strike,
    //         sigma,
    //         tau: _,
    //         gamma,
    //         rx,
    //         ry: _,
    //         liq,
    //     } = self.get_arb_inputs().await?;

    //     let log_p = self
    //         .0
    //         .atomic_arbitrage
    //         .log(target_price_wad * i_wad / strike)
    //         .call()
    //         .await?;
    //     let inner_p = log_p * i_wad / sigma + (sigma / 2);
    //     let cdf_p = self.0.atomic_arbitrage.cdf(inner_p).call().await?;
    //     let delta = liq * (i_wad - cdf_p) / i_wad;
    //     let dx = (delta - rx) * i_wad * i_wad
    //         / (((gamma - i_wad) * (i_wad - cdf_p)) / (rx * i_wad / liq) + i_wad);
    //     info!("dx: {:?}", dx / i_wad);
    //     Ok(dx / i_wad)
    // }



    function run() public {
        uint256 pk = vm.envUint(ENV_PRIVATE_KEY);

        PYIndex mainnetIndex = YT.newIndex();

        // compute optimal arbitrage to rmm pool
        uint256 pendleRate = uint256(getPtExchangeRate(mainnetIndex));

        vm.selectFork(testnetFork);
        PYIndex index = YT.newIndex();

        uint256 L = rmm.totalLiquidity();

        PoolPreCompute memory comp = rmm.preparePoolPreCompute(index, block.timestamp);

        uint256 rmmPrice = computeSpotPrice(comp.reserveInAsset, L, comp.strike_, rmm.sigma(), comp.tau_);
        // pendleRate = rmmPrice - 0.02 ether;

        console2.log("rmmPrice: ", rmmPrice);
        console2.log("pendleRate: ", pendleRate);
        console2.log("asset reserve: ", comp.reserveInAsset);

        if (pendleRate > rmmPrice) {
            int256 dy = getDyGivenS(address(rmm), pendleRate, index);
            console2.log("dy: ", dy);
            uint256 amt = computeOptimalArbRaisePrice(address(rmm), pendleRate, uint256(dy), index);
            console2.log("Amount to lower: ", amt);
        } else {
            console2.log("lower!");
            int256 dx = getDxGivenS(address(rmm), pendleRate, index);
            console2.log("dx: ", dx);
            uint256 amt = computeOptimalArbLowerPrice(address(rmm), pendleRate, uint256(dx), index);
            console2.log("Amount to raise: ", amt);
        }

        vm.startBroadcast(pk);
        vm.stopBroadcast();
    }
}
