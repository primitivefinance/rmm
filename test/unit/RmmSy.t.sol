// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {RMM, toInt, toUint, upscale, downscaleDown, scalar, sum, abs, PoolPreCompute} from "../../src/RMM.sol";
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

uint256 constant eps = 0.005 ether;

uint256 constant impliedRateTime = 365 * 86400;

IPAllActionV3 constant router = IPAllActionV3(0x00000000005BBB0EF59571E58418F9a4357b68A0);
IPMarket constant market = IPMarket(0x9eC4c502D989F04FfA9312C9D6E3F872EC91A0F9);
address constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0; //real wsteth
address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

contract ForkRMMTest is Test {
    using MarketMathCore for MarketState;
    using MarketMathCore for int256;
    using MarketMathCore for uint256;
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;
    using PYIndexLib for IPYieldToken;
    using PYIndexLib for PYIndex;
    using MarketApproxPtInLib for MarketState;

    RMM public __subject__;
    MockERC20 public tokenX;
    MockERC20 public tokenY;

    IStandardizedYield public SY;
    IPPrincipalToken public PT;
    IPYieldToken public YT;

    uint256 timeToExpiry;

    function setUp() public {
        vm.createSelectFork({urlOrAlias: "mainnet", blockNumber: 17_162_783});

        __subject__ = new RMM(WETH_ADDRESS, "LPToken", "LPT");
        vm.label(address(__subject__), "RMM");
        (SY, PT, YT) = IPMarket(market).readTokens();
        (MarketState memory ms,) = getPendleMarketData();
        timeToExpiry = ms.expiry - block.timestamp;

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

    function getPendleMarketData() public returns (MarketState memory ms, MarketPreCompute memory mp) {
        PYIndex index = YT.newIndex();
        ms = market.readState(address(router));
        mp = ms.getMarketPreCompute(index, block.timestamp);
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
        (MarketState memory ms, MarketPreCompute memory mp) = getPendleMarketData();
        return ms.totalPt._getExchangeRate(mp.totalAsset, mp.rateScalar, mp.rateAnchor, 0);
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
        (MarketState memory ms, MarketPreCompute memory mp) = getPendleMarketData();
        uint256 price = uint256(getPtExchangeRate());
        subject().init({
            PT_: address(PT),
            priceX: price,
            amountX: uint256(ms.totalSy - 100 ether),
            strike_: uint256(mp.rateAnchor),
            sigma_: 0.025 ether,
            fee_: 0.0003 ether,
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

    function test_swapSy_over_time_sy() public basic_sy {
        PYIndex index = YT.newIndex();
        uint256 deltaSy = 1 ether;
        console2.log("maturity", subject().maturity());
        vm.warp(block.timestamp + 5 days);
        (,, uint256 minAmountOut,,) = subject().prepareSwapSyIn(deltaSy, block.timestamp, index);
        (uint256 amountOut, int256 deltaLiquidity) = subject().swapExactSyForPt(deltaSy, 0, address(this));
        vm.warp(block.timestamp + 5 days);
        (,, minAmountOut,,) = subject().prepareSwapSyIn(deltaSy, block.timestamp, index);
        (amountOut, deltaLiquidity) = subject().swapExactSyForPt(deltaSy, 0, address(this));
    }

    function test_swap_pt() public basic_sy {
        PYIndex index = YT.newIndex();
        uint256 deltaPt = 1 ether;
        uint256 balanceSyBefore = SY.balanceOf(address(this));
        subject().prepareSwapPtIn(deltaPt, block.timestamp, index);
        (uint256 amtOut,) = subject().swapExactPtForSy(deltaPt, 0, address(this));
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
        uint256 deltaPt = 100 ether;
        (uint256 amountOut,) = subject().swapExactPtForSy(deltaPt, 0, address(this));
        console2.log("amountOut", amountOut);
        uint256 priceAfter = subject().approxSpotPrice(totalAsset);
        console2.log("priceAfter", priceAfter);
    }

    function test_strike_converges_to_one_at_maturity() public basic_sy {
        PYIndex index = YT.newIndex();
        uint256 deltaSy = 1 ether;
        vm.warp(subject().maturity());
        subject().prepareSwapSyIn(deltaSy, block.timestamp, index);
        subject().swapExactSyForPt(deltaSy, 0, address(this));
        assertEq(subject().strike(), 1 ether, "Strike is not approximately 1 ether.");
    }

    function test_spot_price_at_maturity() public basic_sy {
        PYIndex index = YT.newIndex();
        uint256 deltaSy = 1 ether;
        vm.warp(subject().maturity());
        subject().prepareSwapSyIn(deltaSy, block.timestamp, index);
        subject().swapExactSyForPt(deltaSy, 0, address(this));
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

    function test_pt_flash_swap_changes_balances() public basic_sy {
        SY.transfer(address(0x55), SY.balanceOf(address(this)));
        PT.transfer(address(0x55), PT.balanceOf(address(this)));
        YT.transfer(address(0x55), YT.balanceOf(address(this)));
        mintSY(1 ether);
        uint256 stkBefore = subject().strike();
        PYIndex index = YT.newIndex();
        uint256 rPT = subject().reserveX();
        uint256 rSY = subject().reserveY();
        console2.log("SY balance before", SY.balanceOf(address(this)));
        uint256 ytOut = subject().computeSYToYT(index, 1 ether, block.timestamp, 500 ether, 0.005 ether);
        console2.log("ytOut", ytOut);
        console2.log("rPT", rPT);
        console2.log("rSY", rSY);
        (uint256 amtOut,) = subject().swapExactSyForYt(ytOut, ytOut.mulDivDown(95, 100), eps, address(this));
        console2.log("amtOut", amtOut);
        console2.log("SY balance after", SY.balanceOf(address(this)));
        console2.log("YT balance after", YT.balanceOf(address(this)));
        console2.log("stk before", stkBefore);
        console2.log("stk after", subject().strike());
    }

    function test_pt_flash_swap_adjusts_balances_correctly() public basic_sy {
        PYIndex index = YT.newIndex();

        SY.transfer(address(0x55), SY.balanceOf(address(this)));
        PT.transfer(address(0x55), PT.balanceOf(address(this)));
        YT.transfer(address(0x55), YT.balanceOf(address(this)));

        // assert balance of address(this) is 0 for SY, PT, and YT
        assertEq(SY.balanceOf(address(this)), 0, "SY balance of address(this) is not 0.");
        assertEq(PT.balanceOf(address(this)), 0, "PT balance of address(this) is not 0.");
        assertEq(YT.balanceOf(address(this)), 0, "YT balance of address(this) is not 0.");

        // mint 1 SY for the flash swap
        mintSY(1 ether);

        uint256 ytOut = subject().computeSYToYT(index, 1 ether, block.timestamp, 500 ether, 10_000);
        (uint256 amtOut,) = subject().swapExactSyForYt(ytOut, 0, eps, address(this));

        // assert balance of address(this) is 0 for SY, PT, and YT
        assertEq(PT.balanceOf(address(this)), 0, "PT balance at the end of the test is not 0.");
        assertApproxEqAbs(SY.balanceOf(address(this)), 0, 10_000, "SY balance at the end of the test is not approx 0.");
        assertEq(
            YT.balanceOf(address(this)), ytOut, "YT balance at the end of the test is not equal to the returned ytOut."
        );
        assertEq(
            YT.balanceOf(address(this)),
            amtOut,
            "YT balance at the end of the test is not equal to the returned amtOut."
        );
    }

    function test_approx_sy_pendle() public basic_sy {
        (MarketState memory ms, MarketPreCompute memory mp) = getPendleMarketData();
        console2.log("market sy", ms.totalSy);
        console2.log("market pt", ms.totalPt);
        vm.warp(block.timestamp + 30 days);
        int256 rateAnchor = getPendleRateAnchor();
        ApproxParams memory approx =
            ApproxParams({guessMin: 1 ether, guessMax: 500 ether, guessOffchain: 0, maxIteration: 256, eps: 10_000});
        (uint256 netYtOutMarket,) = ms.approxSwapExactSyForYt(YT.newIndex(), 1 ether, block.timestamp, approx);
        console2.log("netYtOutMarket", netYtOutMarket);
        console2.log("rateAnchor", rateAnchor);
    }

    function test_pt_flash_swap_calculation() public basic_sy {
        PYIndex index = YT.newIndex();
        uint256 rPT = subject().reserveX();
        uint256 rSY = subject().reserveY();
        vm.warp(block.timestamp + 30 days);
        uint256 k = getRmmStrikePrice();
        uint256 ytOut = subject().computeSYToYT(index, 1 ether, block.timestamp, 500 ether, eps);
        console2.log("k", k);
        console2.log("ytOut", ytOut);
        console2.log("rPT", rPT);
        console2.log("rSY", rSY);
    }

    function test_pendle_rateAnchor_over_time() public basic_sy {
        int256 rate1 = getPendleRateAnchor();
        vm.warp(block.timestamp + 10 days);
        int256 rate2 = getPendleRateAnchor();
        console2.log("rate1", rate1);
        console2.log("rate2", rate2);
        console2.log("rate1 - rate2", rate1 - rate2);
    }

    function test_rmm_k_over_time() public basic_sy {
        uint256 k1 = getRmmStrikePrice();
        vm.warp(block.timestamp + 10 days);
        uint256 k2 = getRmmStrikePrice();
        console2.log("k1", k1);
        console2.log("k2", k2);
        console2.log("k1 - k2", k1 - k2);
    }

    function test_diff_k_rateAnchor_over_time() public basic_sy {
        uint256 k1 = getRmmStrikePrice();
        int256 rate1 = getPendleRateAnchor();
        vm.warp(block.timestamp + 10 days);
        uint256 k2 = getRmmStrikePrice();
        int256 rate2 = getPendleRateAnchor();
        console2.log("k1", k1);
        console2.log("rate1", rate1);
        console2.log("k2", k2);
        console2.log("rate2", rate2);
        console2.log("k1 - k2", k1 - k2);
        console2.log("rate1 - rate2", rate1 - rate2);
    }

    function getPendleRateAnchor() public returns (int256 rateAnchor) {
        (, MarketPreCompute memory mp) = getPendleMarketData();
        rateAnchor = mp.rateAnchor;
    }

    function getRmmStrikePrice() public returns (uint256 k) {
        PYIndex index = YT.newIndex();
        PoolPreCompute memory comp = subject().preparePoolPreCompute(index, block.timestamp);
        k = comp.strike_;
    }

    function test_exact_yt_for_sy() public basic_sy {
        uint256 ytIn = 1 ether;
        uint256 maxSyIn = 1000 ether;
        subject().swapExactYtForSy(ytIn, maxSyIn, address(this));
    }

    function test_Swapping1YtForSyUpdatesBalancesCorrectly() public basic_sy {
        PT.transfer(address(0x55), PT.balanceOf(address(this)));
        YT.transfer(address(0x55), YT.balanceOf(address(this)));

        assertEq(PT.balanceOf(address(this)), 0, "PT balance of address(this) is not 0.");
        assertEq(YT.balanceOf(address(this)), 0, "YT balance of address(this) is not 0.");

        mintPtYt(1 ether);

        SY.transfer(address(0x55), SY.balanceOf(address(this)));
        PT.transfer(address(0x55), PT.balanceOf(address(this)));
        assertEq(PT.balanceOf(address(this)), 0, "PT balance of address(this) is not 0.");
        assertEq(SY.balanceOf(address(this)), 0, "SY balance of address(this) is not 0.");

        uint256 ytIn = YT.balanceOf(address(this));
        uint256 maxSyIn = 10 ether;
        (uint256 amountOut,,) = subject().swapExactYtForSy(ytIn, maxSyIn, address(this));
        assertEq(YT.balanceOf(address(this)), 0, "YT balance of address(this) is not 0.");
        assertEq(SY.balanceOf(address(this)), amountOut, "SY balance of address(this) is not equal to amountOut.");
    }

    function test_compute_eth_to_yt() public basic_sy {
        SY.transfer(address(0x55), SY.balanceOf(address(this)));
        PT.transfer(address(0x55), PT.balanceOf(address(this)));
        YT.transfer(address(0x55), YT.balanceOf(address(this)));

        // assert balance of address(this) is 0 for SY, PT, and YT
        assertEq(SY.balanceOf(address(this)), 0, "SY balance of address(this) is not 0.");
        assertEq(PT.balanceOf(address(this)), 0, "PT balance of address(this) is not 0.");
        assertEq(YT.balanceOf(address(this)), 0, "YT balance of address(this) is not 0.");

        uint256 amountIn = 1 ether;
        PYIndex index = YT.newIndex();
        (uint256 syMinted, uint256 ytOut) =
            subject().computeTokenToYT(index, address(0), amountIn, block.timestamp, 500 ether, eps);
        subject().swapExactTokenForYt{value: amountIn}(address(0), 0, ytOut, syMinted, ytOut, address(this));
        assertApproxEqAbs(
            YT.balanceOf(address(this)), ytOut, 1_000, "YT balance of address(this) is not equal to ytOut."
        );
    }

    function test_compute_token_to_yt() public basic_sy {
        SY.transfer(address(0x55), SY.balanceOf(address(this)));
        PT.transfer(address(0x55), PT.balanceOf(address(this)));
        YT.transfer(address(0x55), YT.balanceOf(address(this)));

        // assert balance of address(this) is 0 for SY, PT, and YT
        assertEq(SY.balanceOf(address(this)), 0, "SY balance of address(this) is not 0.");
        assertEq(PT.balanceOf(address(this)), 0, "PT balance of address(this) is not 0.");
        assertEq(YT.balanceOf(address(this)), 0, "YT balance of address(this) is not 0.");

        uint256 amountIn = 1 ether;
        PYIndex index = YT.newIndex();
        (uint256 syMinted, uint256 ytOut) =
            subject().computeTokenToYT(index, address(subject().WETH()), amountIn, block.timestamp, 500 ether, eps);
        deal(subject().WETH(), address(this), amountIn);
        IERC20(subject().WETH()).approve(address(subject()), amountIn);
        subject().swapExactTokenForYt(address(subject().WETH()), amountIn, ytOut, syMinted, ytOut, address(this));
        assertApproxEqAbs(
            YT.balanceOf(address(this)), ytOut, 1_000, "YT balance of address(this) is not equal to ytOut."
        );
    }

    // TODO: add functionality for handling these on the new swaps
    // function test_swapX_usingIbToken() public basic_sy {
    //     uint256 wstethBalanceInitial = IERC20(wstETH).balanceOf(address(this));
    //     uint256 deltaX = 1 ether;
    //     uint256 minSYMinted = SY.previewDeposit(address(wstETH), deltaX);
    //     subject().swapX(address(wstETH), minSYMinted, deltaX, 0, address(this), "");
    //     uint256 wstethBalanceAfter = IERC20(wstETH).balanceOf(address(this));
    //     assertTrue(
    //         wstethBalanceAfter < wstethBalanceInitial, "wstETH balance after swap is not greater than initial balance."
    //     );
    //     assertTrue(
    //         wstethBalanceInitial - 1e18 == wstethBalanceAfter,
    //         "wstETH balance after swap is not 1e18 less than initial balance."
    //     );
    // }

    // function test_swapX_usingNativeToken() public basic_sy {
    //     uint256 balanceEthInitial = address(this).balance;
    //     uint256 deltaX = 1 ether;
    //     uint256 minSYMinted = SY.previewDeposit(address(0), deltaX);
    //     subject().swapX{value: deltaX}(address(0), minSYMinted, deltaX, 0, address(this), "");
    //     uint256 balanceEthAfter = address(this).balance;
    //     assertTrue(balanceEthAfter < balanceEthInitial, "wstETH balance after swap is not less than initial balance.");
    //     assertTrue(
    //         balanceEthInitial - 1e18 == balanceEthAfter,
    //         "wstETH balance after swap is not 1e18 less than initial balance."
    //     );
    // }

    // function test_swapX_usingWETH() public basic_sy {
    //     deal(subject().WETH(), address(this), 1 ether);
    //     IERC20(subject().WETH()).approve(address(subject()), type(uint256).max);
    //     uint256 balanceWethInitial = IERC20(subject().WETH()).balanceOf(address(this));
    //     uint256 deltaX = 1 ether;
    //     uint256 minSYMinted = SY.previewDeposit(address(subject().WETH()), deltaX);
    //     subject().swapX(address(subject().WETH()), minSYMinted, deltaX, 0, address(this), "");
    //     uint256 balanceWethAfter = IERC20(subject().WETH()).balanceOf(address(this));
    //     assertTrue(balanceWethAfter < balanceWethInitial, "wstETH balance after swap is not less than initial balance.");
    //     assertTrue(
    //         balanceWethInitial - 1e18 == balanceWethAfter,
    //         "wstETH balance after swap is not 1e18 less than initial balance."
    //     );
    // }
}
