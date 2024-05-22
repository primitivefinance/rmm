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
uint256 constant PT_SLOT = 0 + offset;
uint256 constant SY_SLOT = 1 + offset;
uint256 constant YT_SLOT = 2 + offset;
uint256 constant RESERVE_X_SLOT = 3 + offset;
uint256 constant RESERVE_Y_SLOT = 4 + offset;
uint256 constant TOTAL_LIQUIDITY_SLOT = 5 + offset;
uint256 constant STRIKE_SLOT = 6 + offset;
uint256 constant SIGMA_SLOT = 7 + offset;
uint256 constant FEE_SLOT = 8 + offset;
uint256 constant MATURITY_SLOT = 9 + offset;
uint256 constant INIT_TIMESTAMP_SLOT = 10 + offset;
uint256 constant LAST_TIMESTAMP_SLOT = 11 + offset;
uint256 constant CURATOR_SLOT = 12 + offset;
uint256 constant LOCK_SLOT = 13 + offset;

IPAllActionV3 constant router = IPAllActionV3(0x00000000005BBB0EF59571E58418F9a4357b68A0);
IPMarket constant market = IPMarket(0x9eC4c502D989F04FfA9312C9D6E3F872EC91A0F9);
address constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0; //real wsteth
address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

contract RMMTest is Test {
    using MarketMathCore for MarketState;
    using MarketMathCore for int256;
    using MarketMathCore for uint256;
    using FixedPointMathLib for uint256;
    using PYIndexLib for IPYieldToken;
    using PYIndexLib for PYIndex;
    using MarketApproxPtInLib for MarketState;

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

        __subject__ = new RMM(WETH_ADDRESS, "LPToken", "LPT");
        vm.label(address(__subject__), "RMM");
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

    function getPtExchangeRate() internal returns (int256) {
        PYIndex index = YT.newIndex();
        MarketState memory mkt = market.readState(address(router));
        MarketPreCompute memory preCompute = mkt.getMarketPreCompute(index, block.timestamp);
        console2.log("scalar", preCompute.rateScalar);
        console2.log("anchor", preCompute.rateAnchor);
        console2.log("ta", preCompute.totalAsset);
        console2.log("lastlnimpliedrate", mkt.lastLnImpliedRate);
        return mkt.totalPt._getExchangeRate(mkt.totalSy, preCompute.rateScalar, preCompute.rateAnchor, 0);
    }

    function balanceWad(address token, address account) internal view returns (uint256) {
        return upscale(balanceNative(token, account), scalar(token));
    }

    function mintSY(uint256 amount) public {
        IERC20(wstETH).approve(address(SY), type(uint256).max);
        SY.deposit(address(this), address(wstETH), amount, 1);
    }

    function mintPtYt(uint256 amount) public returns (uint256 amountPY) {
        SY.transfer(address(YT), amount);
        amountPY = YT.mintPY(address(this), address(this));
    }

    modifier basic_sy() {
        uint256 price = uint256(getPtExchangeRate());
        console2.log("initial price", price);
        console2.log("rate anchor", pendleRateAnchor);
        console2.log("totalSY", pendleMarketState.totalSy);
        console2.log("totalPT", pendleMarketState.totalPt);
        console2.log("scalar", pendleRateScalar);
        subject().init({
            PT_: address(PT),
            priceX: price,
            amountX: uint256(pendleMarketState.totalSy) - 100 ether,
            strike_: uint256(pendleRateAnchor),
            sigma_: 0.01 ether,
            fee_: 0.00016 ether,
            curator_: address(0x55)
        });
        console2.log("tau", subject().futureTau(block.timestamp));

        _;
    }

    function test_basic_trading_function_result_sy() public basic_sy {
        PYIndex index = YT.newIndex();
        int256 result = subject().tradingFunction(index);
        console2.log("rx", subject().reserveX());
        console2.log("ry", subject().reserveY());
        assertTrue(abs(result) <= 10, "Trading function result is not within init epsilon.");
    }

    function test_swapX_over_time_sy() public basic_sy {
        PYIndex index = YT.newIndex();
        uint256 deltaX = 1 ether;
        console2.log("maturity", subject().maturity());
        vm.warp(block.timestamp + 5 days);
        (,, uint256 minAmountOut,,) = subject().prepareSwap(address(SY), address(PT), deltaX, block.timestamp, index);
        (uint256 amountOut, int256 deltaLiquidity) = subject().swapX(deltaX, 0, address(this), "");
        vm.warp(block.timestamp + 5 days);
        (,, minAmountOut,,) = subject().prepareSwap(address(SY), address(PT), deltaX, block.timestamp, index);
        (amountOut, deltaLiquidity) = subject().swapX(deltaX, 0, address(this), "");
    }

    function test_swap_y() public basic_sy {
        PYIndex index = YT.newIndex();
        uint256 deltaY = 1 ether;
        uint256 balanceSyBefore = SY.balanceOf(address(this));
        subject().prepareSwap(address(PT), address(SY), deltaY, block.timestamp, index);
        (uint256 amtOut,) = subject().swapY(deltaY, 0, address(this), "");
        console2.log("amtOut", amtOut);

        uint256 balanceSyAfter = SY.balanceOf(address(this));
        assertEq(balanceSyAfter - balanceSyBefore, amtOut, "SwapY did not return the expected amount of SY.");
    }

    // todo: whats the error?
    function test_basic_price() public basic_sy {
        PYIndex index = YT.newIndex();
        uint256 totalAsset = index.syToAsset(subject().reserveX());
        uint256 price = subject().approxSpotPrice(totalAsset);
        assertApproxEqAbs(price, uint256(getPtExchangeRate()), 10_000, "Price is not approximately 1 ether.");
    }

    function test_price_impact() public basic_sy {
        PYIndex index = YT.newIndex();
        uint256 totalAsset = index.syToAsset(subject().reserveX());
        uint256 price = subject().approxSpotPrice(totalAsset);
        console2.log("initialPrice", price);
        uint256 deltaY = 100 ether;
        (uint256 amountOut,) = subject().swapY(deltaY, 0, address(this), "");
        console2.log("amountOut", amountOut);
        uint256 priceAfter = subject().approxSpotPrice(totalAsset);
        console2.log("priceAfter", priceAfter);
    }

    function test_strike_converges_to_one_at_maturity() public basic_sy {
        PYIndex index = YT.newIndex();
        uint256 deltaX = 1 ether;
        vm.warp(subject().maturity());
        subject().prepareSwap(address(SY), address(PT), deltaX, block.timestamp, index);
        subject().swapX(deltaX, 0, address(this), "");
        assertEq(subject().strike(), 1 ether, "Strike is not approximately 1 ether.");
    }

    function test_spot_price_at_maturity() public basic_sy {
        PYIndex index = YT.newIndex();
        uint256 deltaX = 1 ether;
        vm.warp(subject().maturity());
        subject().prepareSwap(address(SY), address(PT), deltaX, block.timestamp, index);
        subject().swapX(deltaX, 0, address(this), "");
        assertApproxEqAbs(
            subject().approxSpotPrice(index.syToAsset(subject().reserveX())),
            1 ether,
            1e18,
            "Spot price is not approximately 1 ether."
        );
    }

    function test_mintSY_with_wstETH() public basic_sy {
        uint256 amountIn = 1 ether;
        uint256 expectedShares = amountIn; // 1:1 exchange rate for wstETH to shares

        uint256 sharesOut = subject().mintSY(address(this), wstETH, amountIn, 0);
        // assertEq(sharesOut, expectedShares, "Minting with wstETH did not return the expected amount of shares.");
    }

    // function test_mintSY_with_stETH() public basic_sy {
    //     uint256 amountIn = 1 ether;
    //     uint256 expectedShares = IWstETH(SY.wstETH()).wrap(amountIn); // Wrap stETH to wstETH

    //     uint256 sharesOut = subject().mintSY(SY.stETH(), amountIn);
    //     assertEq(sharesOut, expectedShares, "Minting with stETH did not return the expected amount of shares.");
    // }

    function test_mintSY_with_wETH() public basic_sy {
        IERC20(subject().WETH()).approve(address(subject()), type(uint256).max);
        deal(subject().WETH(), address(this), 1_000 ether);
        uint256 amountIn = 1 ether;

        uint256 sharesOut = subject().mintSY(address(this), subject().WETH(), amountIn, 0);
        // assertEq(sharesOut, expectedShares, "Minting with wETH did not return the expected amount of shares.");
    }

    function test_mintSY_with_ETH() public basic_sy {
        PYIndex index = YT.newIndex();
        uint256 amountIn = 1 ether;

        uint256 sharesOut = subject().mintSY{value: amountIn}(address(this), address(0), amountIn, 0);
        // assertEq(sharesOut, expectedShares, "Minting with ETH did not return the expected amount of shares.");
    }

    function test_pt_flash_swap_calculation() public basic_sy {
        PYIndex index = YT.newIndex();
        uint256 rPT = subject().reserveX();
        uint256 rSY = subject().reserveY();
        uint256 ytOut = subject().computeSYToYT(index, 1 ether, block.timestamp, 500 ether);
        console2.log("ytOut", ytOut);
        console2.log("rPT", rPT);
        console2.log("rSY", rSY);
    }

    function test_log_pendle_precompute() public basic_sy {
        PYIndex index = YT.newIndex();
        MarketPreCompute memory preCompute = pendleMarketState.getMarketPreCompute(index, block.timestamp);
        console2.log("rateScalar", preCompute.rateScalar);
        console2.log("rateAnchor", preCompute.rateAnchor);
        console2.log("total asset", preCompute.totalAsset);
        console2.log("fee rate", preCompute.feeRate);
    }

    function test_pendle_rate_equal_rmm_price() public basic_sy {
        uint256 price = subject().lastImpliedPrice();
        int256 pendlePrice = pendleMarketState.lastLnImpliedRate._getExchangeRateFromImpliedRate(timeToExpiry);

        assertApproxEqAbs(price, uint256(pendlePrice), 10_000, "Pendle price is not equal to RMM price.");
    }

    function test_pt_flash_swap_changes_balances() public basic_sy {
        // vm.warp(block.timestamp + 30 days);
        SY.transfer(address(0x55), SY.balanceOf(address(this)));
        PT.transfer(address(0x55), PT.balanceOf(address(this)));
        YT.transfer(address(0x55), YT.balanceOf(address(this)));
        uint256 stk1 = subject().strike();
        mintSY(1 ether);
        PYIndex index = YT.newIndex();
        uint256 rSY = subject().reserveX();
        uint256 rPT = subject().reserveY();
        uint256 priceBefore = subject().lastImpliedPrice();
        console2.log("SY balance before", SY.balanceOf(address(this)));
        uint256 ytOut = subject().computeSYToYT(index, 1 ether, block.timestamp, 2000 ether);
        console2.log("ytOut", ytOut);
        (uint256 amtOut,) = subject().swapY(ytOut, 0, address(this), "0x55");
        uint256 rSY2 = subject().reserveX();
        uint256 rPT2 = subject().reserveY();
        uint256 priceAfter = subject().lastImpliedPrice();
        uint256 stk2 = subject().strike();
        console2.log("priceBefore", priceBefore);
        console2.log("priceAfter", priceAfter);
        console2.log("amtOut", amtOut);
        console2.log("SY balance after", SY.balanceOf(address(this)));
        console2.log("YT balance after", YT.balanceOf(address(this)));
        console2.log("rPT", rPT);
        console2.log("rSY", rSY);
        console2.log("rPT2", rPT2);
        console2.log("rSY2", rSY2);
        console2.log("price given y", subject().approxSpotPrice2());
        console2.log("strike before", stk1);
        console2.log("strike after", stk2);
    }

    function test_sequential_swaps() public basic_sy {
        vm.warp(block.timestamp + 10 days);
        SY.transfer(address(0x55), SY.balanceOf(address(this)));
        PT.transfer(address(0x55), PT.balanceOf(address(this)));
        YT.transfer(address(0x55), YT.balanceOf(address(this)));
        uint256 totalYt;
        uint256 stk1 = subject().strike();
        mintSY(1 ether);
        PYIndex index = YT.newIndex();
        uint256 priceBefore = subject().lastImpliedPrice();
        console2.log("SY balance before", SY.balanceOf(address(this)));
        uint256 ytOut = subject().computeSYToYT(index, 1 ether, block.timestamp, 2000 ether);
        console2.log("ytOut", ytOut);
        (uint256 amtOut,) = subject().swapY(ytOut, 0, address(this), "0x55");
        totalYt += amtOut;
        uint256 priceInter = subject().lastImpliedPrice();
        uint256 stk2 = subject().strike();
        console2.log("SY balance after", SY.balanceOf(address(this)));
        console2.log("YT balance after", YT.balanceOf(address(this)));
        mintSY(1 ether);
        vm.warp(block.timestamp + 10 days);
        uint256 ytOut2 = subject().computeSYToYT(index, 1 ether, block.timestamp, 1000 ether);
        console2.log("ytOut2", ytOut2);
        (uint256 amtOut2,) = subject().swapY(ytOut2, 0, address(this), "0x55");
        totalYt += amtOut2;
        uint256 stk3 = subject().strike();
        uint256 priceAfter = subject().lastImpliedPrice();
        console2.log("totalYt", totalYt);
        console2.log("strike before", stk1);
        console2.log("strike after", stk2);
        console2.log("strike after", stk3);
        console2.log("priceBefore", priceBefore);
        console2.log("priceInter", priceInter);
        console2.log("priceAfter", priceAfter);
        console2.log("rx", subject().reserveX());
        console2.log("ry", subject().reserveY());
    }

    function callback(address token, uint256 amount, bytes calldata) external returns (bool) {
        console2.log("SYBalance after", SY.balanceOf(address(this)));
        uint256 amountPY = mintPtYt(SY.balanceOf(address(this)));
        console2.log("amountPY", amountPY);
        PT.transfer(msg.sender, amountPY);
        return true;
    }

    function test_approx_sy_pendle() public basic_sy {
        vm.warp(block.timestamp + 30 days);
        console2.log("market sy", pendleMarketState.totalSy);
        console2.log("market pt", pendleMarketState.totalPt);
        PYIndex index = YT.newIndex();
        console2.log("price before", getPtExchangeRate());
        MarketState memory mkt = market.readState(address(router));
        ApproxParams memory approx =
            ApproxParams({guessMin: 2 ether, guessMax: 1000 ether, guessOffchain: 0, maxIteration: 256, eps: 10_000});
        (uint256 netYtOutMarket,) = mkt.approxSwapExactSyForYt(index, 2 ether, block.timestamp, approx);
        console2.log("netYtOutMarket", netYtOutMarket);
        (uint256 netSyToAccount,) = market.swapExactPtForSy(address(this), netYtOutMarket, "0x5");
        console2.log("price inter", getPtExchangeRate());
        console2.log("lnimpliedrate inter", mkt.lastLnImpliedRate);
        // vm.warp(block.timestamp + 20 days);
        mkt = market.readState(address(router));
        approx =
            ApproxParams({guessMin: 2 ether, guessMax: 1000 ether, guessOffchain: 0, maxIteration: 256, eps: 10_000});
        (netYtOutMarket,) = mkt.approxSwapExactSyForYt(index, 2 ether, block.timestamp, approx);
        (netSyToAccount,) = market.swapExactPtForSy(address(this), netYtOutMarket, "0x5");
        console2.log("netYTToAccount", index.syToAsset(netSyToAccount));
        vm.warp(block.timestamp + 5);
        console2.log("price after", getPtExchangeRate());
    }

    function swapCallback(int256 exactPtIn, int256 syGiven, bytes memory) external {
        uint256 amountPy = mintPtYt(uint256(syGiven));
        PT.transfer(msg.sender, amountPy + 2.5 ether);
    }
}
