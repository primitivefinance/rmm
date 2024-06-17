// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {PendleERC20SY} from "pendle/core/StandardizedYield/implementations/PendleERC20SY.sol";
import {Factory} from "../src/Factory.sol";
import {SYBase} from "pendle/core/StandardizedYield/SYBase.sol";
import {IStandardizedYield} from "pendle/interfaces/IStandardizedYield.sol";
import {PendleYieldContractFactoryV2} from "pendle/core/YieldContractsV2/PendleYieldContractFactoryV2.sol";
import {PendleYieldTokenV2} from "pendle/core/YieldContractsV2/PendleYieldTokenV2.sol";
import {BaseSplitCodeFactory} from "pendle/core/libraries/BaseSplitCodeFactory.sol";
import {RMM} from "../src/RMM.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import "pendle/core/Market/MarketMathCore.sol";
import "pendle/interfaces/IPAllActionV3.sol";
import {IPPrincipalToken} from "pendle/interfaces/IPPrincipalToken.sol";
import {IPMarket} from "pendle/interfaces/IPMarket.sol";
import {IStandardizedYield} from "pendle/interfaces/IStandardizedYield.sol";
import {IPYieldToken} from "pendle/interfaces/IPYieldToken.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract DeployPool is Script {
    using MarketMathCore for MarketState;
    using MarketMathCore for int256;
    using MarketMathCore for uint256;
    using FixedPointMathLib for uint256;
    using PYIndexLib for IPYieldToken;
    using PYIndexLib for PYIndex;

    string public constant ENV_PRIVATE_KEY = "PRIVATE_KEY";
    address payable public constant RMM_ADDRESS = payable(address(0));
    address public constant SY_ADDRESS = address(0);
    address public constant PT_ADDRESS = address(0);
    uint256 public constant fee = 0.0002 ether;
    address public constant curator = address(0);
    Factory FACTORY = Factory(0xA61D6761ce83F1A2E3B128B7a5033e99BcdAa7d5);
    IPMarket market = IPMarket(0xC374f7eC85F8C7DE3207a10bB1978bA104bdA3B2);
    IPAllActionV3 router = IPAllActionV3(0x00000000005BBB0EF59571E58418F9a4357b68A0);
    address wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0; //real wsteth
    RMM public rmm;

    IStandardizedYield public SY;
    IPPrincipalToken public PT;
    IPYieldToken public YT;
    MarketState public mktState;
    int256 rateAnchor;
    int256 rateScalar;
    uint256 timeToExpiry;

    address sender;

    function setUp() public {
        (SY, PT, YT) = IPMarket(market).readTokens();
        mktState = market.readState(address(router));
        console2.log("expiry", mktState.expiry);
        console2.log("timestamp", block.timestamp);
        timeToExpiry = mktState.expiry - block.timestamp;
    }

    function getPendleMarketData(PYIndex index)
        public
        view
        returns (MarketState memory ms, MarketPreCompute memory mp)
    {
        ms = market.readState(address(router));
        mp = ms.getMarketPreCompute(index, block.timestamp);
    }

    function getPtExchangeRate(PYIndex index) public view returns (int256) {
        (MarketState memory ms, MarketPreCompute memory mp) = getPendleMarketData(index);
        return ms.totalPt._getExchangeRate(mp.totalAsset, mp.rateScalar, mp.rateAnchor, 0);
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

    function run() public {
        uint256 pk = vm.envUint(ENV_PRIVATE_KEY);
        vm.startBroadcast(pk);
        sender = vm.addr(pk);
        rmm = FACTORY.createRMM("Lido Staked ETH 24 Dec 2025", "stETH-24DEC25");
        console2.log("rmm address: ", address(rmm));

        mintSY(10_000 ether);
        mintPtYt(5_000 ether);

        IERC20(wstETH).approve(address(rmm), type(uint256).max);
        IERC20(SY).approve(address(rmm), type(uint256).max);
        IERC20(PT).approve(address(rmm), type(uint256).max);
        IERC20(YT).approve(address(rmm), type(uint256).max);

        IERC20(wstETH).approve(address(router), type(uint256).max);
        IERC20(SY).approve(address(router), type(uint256).max);
        IERC20(PT).approve(address(router), type(uint256).max);
        IERC20(YT).approve(address(router), type(uint256).max);
        IERC20(market).approve(address(router), type(uint256).max);

        PYIndex index = YT.newIndex();
        (MarketState memory ms, MarketPreCompute memory mp) = getPendleMarketData(index);
        uint256 price = uint256(getPtExchangeRate(index));
        rmm.init({
            PT_: address(PT),
            priceX: price,
            amountX: uint256(ms.totalSy),
            strike_: uint256(mp.rateAnchor),
            sigma_: 0.02 ether,
            fee_: fee,
            curator_: address(0x55)
        });

        vm.stopBroadcast();
    }
}
