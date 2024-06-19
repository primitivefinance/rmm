// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {RMM} from "../src/RMM.sol";
import {LiquidityManager} from "../src/LiquidityManager.sol";
import {Factory} from "../src/Factory.sol";

import {IPMarket} from "pendle/interfaces/IPMarket.sol";
import {IStandardizedYield} from "pendle/interfaces/IStandardizedYield.sol";
import {IPYieldToken} from "pendle/interfaces/IPYieldToken.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import "pendle/core/Market/MarketMathCore.sol";
import "pendle/interfaces/IPAllActionV3.sol";

contract ComputeArb is Script {
    using MarketMathCore for MarketState;
    using MarketMathCore for int256;
    using MarketMathCore for uint256;
    using FixedPointMathLib for uint256;
    using PYIndexLib for IPYieldToken;
    using PYIndexLib for PYIndex;

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
        mainnetFork = vm.createFork("MAINNET_RPC_URL");
        testnetFork = vm.createFork("TESTNET_RPC_URL");

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

    function run() public {
        uint256 pk = vm.envUint(ENV_PRIVATE_KEY);

        PYIndex mainnetIndex = YT.newIndex();

        // compute optimal arbitrage to rmm pool

        uint256 pendleRate = uint256(getPtExchangeRate(mainnetIndex));

        vm.selectFork(testnetFork);
        PYIndex index = YT.newIndex();
        uint256 rX = rmm.reserveX();

        uint256 rmmPrice = rmm.approxSpotPrice(index.syToAsset(rX));

        vm.startBroadcast(pk);
        vm.stopBroadcast();
    }
}
