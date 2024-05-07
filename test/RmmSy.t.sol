// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {RMM, toInt, toUint, upscale, downscaleDown, scalar, sum, abs} from "../src/RMM.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ReturnsTooLittleToken} from "solmate/test/utils/weird-tokens/ReturnsTooLittleToken.sol";
import {ReturnsTooMuchToken} from "solmate/test/utils/weird-tokens/ReturnsTooMuchToken.sol";
import {MissingReturnToken} from "solmate/test/utils/weird-tokens/MissingReturnToken.sol";
import {ReturnsFalseToken} from "solmate/test/utils/weird-tokens/ReturnsFalseToken.sol";
import {IPMarket} from "pendle/interfaces/IPMarket.sol";
import "pendle/core/Market/MarketMathCore.sol";
import "pendle/interfaces/IPAllActionV3.sol";
import {IPPrincipalToken} from "pendle/interfaces/IPPrincipalToken.sol";
import {IStandardizedYield} from "pendle/interfaces/IStandardizedYield.sol";
import {IPYieldToken} from "pendle/interfaces/IPYieldToken.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

// slot numbers. double check these if changes are made.
uint256 constant offset = 6; // ERC20 inheritance adds 6 storage slots.
uint256 constant TOKEN_X_SLOT = 0 + offset;
uint256 constant TOKEN_Y_SLOT = 1 + offset;
uint256 constant RESERVE_X_SLOT = 2 + offset;
uint256 constant RESERVE_Y_SLOT = 3 + offset;
uint256 constant TOTAL_LIQUIDITY_SLOT = 4 + offset;
uint256 constant STRIKE_SLOT = 5 + offset;
uint256 constant SIGMA_SLOT = 6 + offset;
uint256 constant FEE_SLOT = 7 + offset;
uint256 constant MATURITY_SLOT = 8 + offset;
uint256 constant INIT_TIMESTAMP_SLOT = 9 + offset;
uint256 constant LAST_TIMESTAMP_SLOT = 10 + offset;
uint256 constant CURATOR_SLOT = 11 + offset;
uint256 constant LOCK_SLOT = 12 + offset;

IPAllActionV3 constant router = IPAllActionV3(0x00000000005BBB0EF59571E58418F9a4357b68A0);
IPMarket constant market = IPMarket(0x9eC4c502D989F04FfA9312C9D6E3F872EC91A0F9);
address constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0; //real wsteth

contract RMMTest is Test {
    using MarketMathCore for MarketState;
    using MarketMathCore for int256;
    using MarketMathCore for uint256;
    using FixedPointMathLib for uint256;

    RMM public __subject__;
    MockERC20 public tokenX;
    MockERC20 public tokenY;

    IStandardizedYield public SY;
    IPPrincipalToken public PT;
    IPYieldToken public YT;
    MarketState public pendleMarketState;
    int256 pendleRateAnchor;
    int256 pendleRateScalar;
    uint256 timeToExpiry;

    function setUp() public {
        vm.createSelectFork({urlOrAlias: "mainnet", blockNumber: 17_162_783});

        __subject__ = new RMM(address(0), "LPToken", "LPT");
        vm.label(address(__subject__), "RMM");
        console2.log("got here?");
        (SY, PT, YT) = IPMarket(market).readTokens();
        pendleMarketState = market.readState(address(router));
        timeToExpiry = pendleMarketState.expiry - block.timestamp;
        pendleRateScalar = pendleMarketState._getRateScalar(timeToExpiry);
        pendleRateAnchor = pendleMarketState.totalPt._getRateAnchor(
            pendleMarketState.lastLnImpliedRate, pendleMarketState.totalSy, pendleRateScalar, timeToExpiry
        );

        deal(wstETH, address(this), 1_000_000e18);

        mintSY(100_000 ether);
        mintPtYt(50_000 ether);

        IERC20(wstETH).approve(address(subject()), type(uint256).max);
        IERC20(SY).approve(address(subject()), type(uint256).max);
        IERC20(PT).approve(address(subject()), type(uint256).max);
        IERC20(YT).approve(address(subject()), type(uint256).max);

        IERC20(wstETH).approve(address(router), type(uint256).max);
        IERC20(SY).approve(address(router), type(uint256).max);
        IERC20(PT).approve(address(router), type(uint256).max);
        IERC20(YT).approve(address(router), type(uint256).max);
        IERC20(market).approve(address(router), type(uint256).max);
    }

    function subject() public view returns (RMM) {
        return __subject__;
    }

    function balanceNative(address token, address account) internal view returns (uint256) {
        if (token == address(0)) {
            return address(this).balance;
        }

        return MockERC20(token).balanceOf(account);
    }

    function getPtExchangeRate() internal view returns (int256) {
        return
            pendleMarketState.totalPt._getExchangeRate(pendleMarketState.totalSy, pendleRateScalar, pendleRateAnchor, 0);
    }

    function balanceWad(address token, address account) internal view returns (uint256) {
        return upscale(balanceNative(token, account), scalar(token));
    }

    function mintSY(uint256 amount) public {
        IERC20(wstETH).approve(address(SY), type(uint256).max);
        SY.deposit(address(this), address(wstETH), amount, 1);
    }

    function mintPtYt(uint256 amount) public {
        SY.transfer(address(YT), amount);
        YT.mintPY(address(this), address(this));
    }

    modifier basic_sy() {
        uint256 price = SY.exchangeRate().mulWadDown(uint256(getPtExchangeRate()));
        console2.log("initial price", price);
        console2.log("rate anchor", pendleRateAnchor);
        subject().init({
            tokenX_: address(SY),
            tokenY_: address(PT),
            priceX: price,
            amountX: 10 ether,
            strike_: price,
            sigma_: 0.2 ether,
            fee_: 0.0005 ether,
            maturity_: PT.expiry(),
            curator_: address(0x55)
        });

        _;
    }

    function test_basic_trading_function_result_sy() public basic_sy {
        int256 result = subject().tradingFunction();
        assertTrue(result >= 0 && result <= 30, "Trading function result is not within init epsilon.");
    }
}
