// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {RMM, toInt, toUint, upscale, downscaleDown, scalar, sum, abs} from "../../src/RMM.sol";

import {Test, console2} from "forge-std/Test.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import "pendle/core/Market/MarketMathCore.sol";
import {IPPrincipalToken} from "pendle/interfaces/IPPrincipalToken.sol";
import {IStandardizedYield} from "pendle/interfaces/IStandardizedYield.sol";
import {IPYieldToken} from "pendle/interfaces/IPYieldToken.sol";

import {PendleERC20SY} from "pendle/core/StandardizedYield/implementations/PendleERC20SY.sol";
import {SYBase} from "pendle/core/StandardizedYield/SYBase.sol";
import {PendleYieldContractFactoryV2} from "pendle/core/YieldContractsV2/PendleYieldContractFactoryV2.sol";
import {PendleYieldTokenV2} from "pendle/core/YieldContractsV2/PendleYieldTokenV2.sol";
import {BaseSplitCodeFactory} from "pendle/core/libraries/BaseSplitCodeFactory.sol";

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

contract RMMTest is Test {
    using MarketMathCore for MarketState;
    using MarketMathCore for int256;
    using MarketMathCore for uint256;
    using FixedPointMathLib for uint256;
    using PYIndexLib for IPYieldToken;
    using PYIndexLib for PYIndex;

    RMM public __subject__;
    address public wstETH;
    IStandardizedYield public SY;
    IPPrincipalToken public PT;
    IPYieldToken public YT;
    MarketState public pendleMarketState;
    int256 pendleRateAnchor;
    int256 pendleRateScalar;
    uint256 timeToExpiry;

    function setUp() public {
        vm.warp(0);
        __subject__ = new RMM(address(0), "LPToken", "LPT");
        vm.label(address(__subject__), "RMM");

        uint32 _expiry = 1_717_214_400;

        wstETH = address(new MockERC20("Wrapped stETH", "wstETH", 18));
        SYBase SY_ = new PendleERC20SY("Standard Yield wstETH", "SYwstETH", wstETH);
        SY = IStandardizedYield(SY_);
        (address ytCodeContractA, uint256 ytCodeSizeA, address ytCodeContractB, uint256 ytCodeSizeB) =
            BaseSplitCodeFactory.setCreationCode(type(PendleYieldTokenV2).creationCode);
        PendleYieldContractFactoryV2 YCF = new PendleYieldContractFactoryV2({
            _ytCreationCodeContractA: ytCodeContractA,
            _ytCreationCodeSizeA: ytCodeSizeA,
            _ytCreationCodeContractB: ytCodeContractB,
            _ytCreationCodeSizeB: ytCodeSizeB
        });

        YCF.initialize(1, 2e17, 0, address(this));
        YCF.createYieldContract(address(SY), _expiry, true);
        YT = IPYieldToken(YCF.getYT(address(SY), _expiry));
        PT = IPPrincipalToken(YCF.getPT(address(SY), _expiry));

        deal(wstETH, address(this), 1_000_000e18);

        mintSY(100_000 ether);
        mintPtYt(50_000 ether);

        IERC20(wstETH).approve(address(subject()), type(uint256).max);
        IERC20(SY).approve(address(subject()), type(uint256).max);
        IERC20(PT).approve(address(subject()), type(uint256).max);
        IERC20(YT).approve(address(subject()), type(uint256).max);
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

    modifier basic() {
        uint256 price = 1 ether; //uint256(getPtExchangeRate());
        console2.log("initial price", price);
        console2.log("rate anchor", pendleRateAnchor);
        console2.log("totalSY", pendleMarketState.totalSy);
        console2.log("totalPT", pendleMarketState.totalPt);
        uint256 amountX = YT.newIndex().assetToSy(price);
        console2.log("amountX", amountX);
        subject().init({
            PT_: address(PT),
            priceX: price,
            amountX: amountX, // using the equivalent amount of tokens
            strike_: 1 ether, //uint256(pendleRateAnchor),
            sigma_: 0.015 ether,
            fee_: 0.00016 ether,
            curator_: address(0x55)
        });

        _;
    }

    function test_basic_trading_function_result() public basic {
        PYIndex index = YT.newIndex();
        int256 result = subject().tradingFunction(index);
        assertTrue(abs(result) < 10, "Trading function result is not within init epsilon.");
    }

    // todo: whats the error?
    function test_basic_price() public basic {
        uint256 price = subject().approxSpotPrice(YT.newIndex().syToAsset(subject().reserveX()));
        assertApproxEqAbs(price, 1 ether, 10_000, "Price is not approximately 1 ether.");
    }

    // no fee btw
    function test_basic_adjust_invalid_allocate() public basic {
        uint256 deltaX = 1 ether;
        uint256 approximatedDeltaY = 0.685040862443611931 ether;

        deal(address(subject().SY()), address(this), deltaX);
        deal(address(subject().PT()), address(this), approximatedDeltaY);
        SY.approve(address(subject()), deltaX);
        PT.approve(address(subject()), approximatedDeltaY);

        vm.expectRevert();
        subject().adjust(toInt(deltaX), -toInt(approximatedDeltaY - 3), toInt(1 ether));
    }

    function test_basic_adjust_single_allocate_x_increases() public basic {
        PYIndex index = YT.newIndex();
        uint256 deltaX = 1;

        deal(address(subject().SY()), address(this), deltaX);
        SY.approve(address(subject()), deltaX);

        subject().adjust(toInt(deltaX), toInt(0), toInt(0));
        int256 post = subject().tradingFunction(index);

        assertTrue(abs(post) < 10, "Trading function invalid.");
    }

    function test_basic_adjust_single_allocate_y_increases() public basic {
        PYIndex index = YT.newIndex();
        uint256 deltaY = 4;

        deal(address(subject().PT()), address(this), deltaY);
        PT.approve(address(subject()), deltaY);

        subject().adjust(toInt(0), toInt(deltaY), toInt(0));
        int256 post = subject().tradingFunction(index);

        assertTrue(abs(post) < 10, "Trading function invalid.");
    }

    // todo: improve test
    function test_basic_solve_y() public basic {
        uint256 deltaX = 1 ether;
        uint256 computedYGivenXAdjustment = subject().computeY(
            subject().reserveX() + deltaX,
            subject().totalLiquidity(),
            subject().strike(),
            subject().sigma(),
            subject().lastTau()
        );
        console2.log("computedYGivenXAdjustment", computedYGivenXAdjustment);

        uint256 nextReserveY = subject().solveY(
            subject().reserveX() + deltaX,
            subject().totalLiquidity(),
            subject().strike(),
            subject().sigma(),
            subject().lastTau()
        );
        console2.log("nextReserveY", nextReserveY);

        uint256 actualDeltaY = subject().reserveY() - nextReserveY;
        console2.log("actualDeltaY", actualDeltaY);

        uint256 approximatedDeltaY = 0.685040862443611931 ether;
        uint256 diff =
            approximatedDeltaY > actualDeltaY ? approximatedDeltaY - actualDeltaY : actualDeltaY - approximatedDeltaY;
        console2.log("diff", diff, approximatedDeltaY > actualDeltaY);
    }

    // todo: improve test
    function test_basic_solve_x() public basic {
        PYIndex index = YT.newIndex();
        uint256 deltaX = 1 ether;
        (,, uint256 approximatedDeltaY,,) =
            subject().prepareSwap(address(SY), address(PT), deltaX, block.timestamp, index);

        uint256 proportionalLGivenX = deltaX * subject().totalLiquidity() / subject().reserveX();
        uint256 proportionalLGivenY = approximatedDeltaY * subject().totalLiquidity() / subject().reserveY();
        console2.log("proportionalLGivenX", proportionalLGivenX);
        console2.log("proportionalLGivenY", proportionalLGivenY);

        uint256 computedXGivenYAdjustment = subject().computeX(
            subject().reserveY() - approximatedDeltaY,
            subject().totalLiquidity(),
            subject().strike(),
            subject().sigma(),
            subject().lastTau()
        );
        console2.log("computedXGivenYAdjustment", computedXGivenYAdjustment);

        uint256 nextReserveX = subject().solveX(
            subject().reserveY() - approximatedDeltaY,
            subject().totalLiquidity(),
            subject().strike(),
            subject().sigma(),
            subject().lastTau()
        );
        uint256 actualDeltaX = nextReserveX - subject().reserveX();
        console2.log("nextReserveX", nextReserveX);
        console2.log("actualDeltaX", actualDeltaX);
    }

    function test_swap_x() public basic {
        PYIndex index = YT.newIndex();
        uint256 deltaX = 1 ether;
        uint256 minAmountOut = 0.685040862443611931 ether;
        deal(address(subject().PT()), address(subject()), minAmountOut * 150 / 100);
        deal(address(subject().SY()), address(this), deltaX);
        SY.approve(address(subject()), deltaX);

        int256 initial = subject().tradingFunction(index);
        console2.log("loss", uint256(685_040_862_443_611_928) - uint256(685_001_492_551_417_433));
        console2.log("loss %", uint256(39_369_892_194_495) * 1 ether / uint256(685_001_492_551_417_433));
        (uint256 amountOut, int256 deltaLiquidity) = subject().swapX(deltaX, minAmountOut, address(this), "");
        int256 terminal = subject().tradingFunction(index);
        console2.logInt(initial);
        console2.logInt(terminal);
        console2.logUint(amountOut);
        console2.logInt(deltaLiquidity);
    }

    function test_swapX_callback() public basic {
        PYIndex index = YT.newIndex();
        uint256 deltaX = 1 ether;
        (,, uint256 minAmountOut,,) = subject().prepareSwap(address(SY), address(PT), deltaX, block.timestamp, index);
        deal(address(subject().PT()), address(subject()), minAmountOut);
        CallbackProvider provider = new CallbackProvider();
        vm.prank(address(provider));
        (uint256 amountOut,) = subject().swapX(deltaX, minAmountOut, address(this), "0x1");
        assertTrue(amountOut >= minAmountOut, "Amount out is not greater than min amount out.");
        assertTrue(PT.balanceOf(address(this)) >= amountOut, "Token Y balance is not greater than 0.");
    }

    function test_swapX_over_time_basic() public basic {
        PYIndex index = YT.newIndex();
        uint256 deltaX = 1 ether;
        (,, uint256 minAmountOut,,) = subject().prepareSwap(address(SY), address(PT), deltaX, block.timestamp, index);
        deal(address(subject().PT()), address(subject()), 1 ether);
        deal(address(subject().SY()), address(this), deltaX);
        SY.approve(address(subject()), deltaX);

        int256 initial = subject().tradingFunction(index);
        vm.warp(365 days / 2);

        uint256 expectedL = 2_763_676_832_322_849_396;
        console2.log("expectedL", expectedL);
        (uint256 amountOut, int256 deltaLiquidity) = subject().swapX(deltaX, minAmountOut, address(this), "");
        int256 terminal = subject().tradingFunction(index);

        console2.log("initialInvariant", initial);
        console2.log("terminalInvariant", terminal);
        console2.log("amountOut", amountOut);
        console2.log("deltaLiquidity", deltaLiquidity);
        // assertTrue(abs(terminal) < 10, "Trading function invalid.");
    }

    function test_price_increase_over_time() public basic {
        PYIndex index = YT.newIndex();
        uint256 timeDelta = 10 days;

        uint256 initial = subject().approxSpotPrice(index.syToAsset(subject().reserveX()));
        vm.warp(timeDelta);
        vm.store(address(subject()), bytes32(LAST_TIMESTAMP_SLOT), bytes32(uint256(block.timestamp)));
        uint256 terminal = subject().approxSpotPrice(index.syToAsset(subject().reserveX()));

        console2.logUint(initial);
        console2.logUint(terminal);

        assertTrue(terminal > initial, "Price did not increase over time.");
    }

    // avoids stack too deep in tests.
    struct InitParams {
        uint256 priceX;
        uint256 amountX;
        uint256 strike;
        uint256 sigma;
        uint256 fee;
        uint256 maturity;
        address curator;
    }

    InitParams basicParams = InitParams({
        priceX: 1 ether,
        amountX: 1 ether,
        strike: 1 ether,
        sigma: 0.015 ether,
        fee: 0,
        maturity: 1_717_214_400,
        curator: address(0x55)
    });

    // init

    function test_swapX_basic() public basic {
        PYIndex index = YT.newIndex();
        uint256 deltaX = 1 ether;
        (,, uint256 minAmountOut,,) = subject().prepareSwap(address(SY), address(PT), deltaX, block.timestamp, index);
        deal(address(PT), address(subject()), minAmountOut);
        deal(address(SY), address(this), deltaX);
        SY.approve(address(subject()), deltaX);

        uint256 prevBalanceX = balanceWad(address(SY), address(this));
        uint256 prevBalanceY = balanceWad(address(PT), address(this));
        uint256 prevReserveY = subject().reserveY();
        uint256 prevPrice = subject().approxSpotPrice(index.syToAsset(subject().reserveX()));
        uint256 prevLiquidity = subject().totalLiquidity();
        (uint256 amountOut, int256 deltaLiquidity) = subject().swapX(deltaX, minAmountOut - 3, address(this), "");

        assertTrue(amountOut >= minAmountOut, "Amount out is not greater than or equal to min amount out.");
        assertTrue(abs(subject().tradingFunction(index)) < 100, "Invalid trading function state.");
        assertEq(subject().reserveX(), basicParams.amountX + deltaX, "Reserve X did not increase by delta X.");
        assertEq(subject().reserveY(), prevReserveY - amountOut, "Reserve Y did not decrease by amount out.");
        assertEq(
            subject().totalLiquidity(),
            sum(prevLiquidity, deltaLiquidity),
            "Total liquidity did not increase by delta liquidity."
        );

        assertEq(
            balanceWad(address(SY), address(this)), prevBalanceX - deltaX, "Balance X did not decrease by delta X."
        );
        assertEq(
            balanceWad(address(PT), address(this)),
            prevBalanceY + amountOut,
            "Balance Y did not increase by amount out."
        );
        assertTrue(
            subject().approxSpotPrice(index.syToAsset(subject().reserveX())) < prevPrice,
            "Price did not decrease after selling X."
        );
    }

    function test_swapX_reverts_InsufficientOutput() public basic {
        PYIndex index = YT.newIndex();
        uint256 deltaX = 1 ether;
        (,, uint256 minAmountOut,,) = subject().prepareSwap(address(SY), address(PT), deltaX, block.timestamp, index);
        deal(address(PT), address(subject()), minAmountOut);
        deal(address(SY), address(this), deltaX);
        SY.approve(address(subject()), deltaX);

        vm.expectRevert(
            abi.encodeWithSelector(
                RMM.InsufficientOutput.selector, upscale(deltaX, scalar(address(SY))), minAmountOut + 10, minAmountOut
            )
        );
        subject().swapX(deltaX, minAmountOut + 10, address(this), "");
    }

    function test_swapX_event() public basic {
        PYIndex index = YT.newIndex();
        uint256 deltaX = 1 ether;
        (,, uint256 minAmountOut, int256 delLiq,) =
            subject().prepareSwap(address(SY), address(PT), deltaX, block.timestamp, index);
        deal(address(PT), address(subject()), minAmountOut);
        deal(address(SY), address(this), deltaX);
        SY.approve(address(subject()), deltaX);

        vm.expectEmit();
        emit RMM.Swap(address(this), address(this), address(SY), address(PT), deltaX, minAmountOut, delLiq);
        subject().swapX(deltaX, minAmountOut, address(this), "");
    }

    function test_swapY() public basic {
        PYIndex index = YT.newIndex();
        uint256 deltaY = 1 ether;
        (,, uint256 minAmountOut,,) = subject().prepareSwap(address(PT), address(SY), deltaY, block.timestamp, index);
        deal(address(SY), address(subject()), minAmountOut);
        deal(address(PT), address(this), deltaY);
        PT.approve(address(subject()), deltaY);

        uint256 prevBalanceX = balanceWad(address(SY), address(this));
        uint256 prevBalanceY = balanceWad(address(PT), address(this));
        uint256 prevPrice = subject().approxSpotPrice(index.syToAsset(subject().reserveX()));
        uint256 prevReserveY = subject().reserveY();
        uint256 prevLiquidity = subject().totalLiquidity();
        (uint256 amountOut, int256 deltaLiquidity) = subject().swapY(deltaY, minAmountOut, address(this), "");

        assertTrue(amountOut >= minAmountOut, "Amount out is not greater than or equal to min amount out.");
        assertTrue(abs(subject().tradingFunction(index)) < 100, "Trading function invalid");
        assertEq(subject().reserveX(), basicParams.amountX - amountOut, "Reserve X did not decrease by amount in.");
        assertEq(subject().reserveY(), prevReserveY + deltaY, "Reserve Y did not increase by delta Y.");
        assertEq(
            subject().totalLiquidity(),
            sum(prevLiquidity, deltaLiquidity),
            "Total liquidity did not increase by delta liquidity."
        );

        assertEq(
            balanceWad(address(SY), address(this)), prevBalanceX + amountOut, "Balance X did not increase by amount in."
        );
        assertEq(
            balanceWad(address(PT), address(this)), prevBalanceY - deltaY, "Balance Y did not decrease by delta Y."
        );
        assertTrue(
            subject().approxSpotPrice(index.syToAsset(subject().reserveX())) > prevPrice,
            "Price did not increase after buying Y."
        );
    }

    function test_swapY_reverts_InsufficientOutput() public basic {
        PYIndex index = YT.newIndex();
        uint256 deltaY = 1 ether;
        (,, uint256 minAmountOut,,) = subject().prepareSwap(address(PT), address(SY), deltaY, block.timestamp, index);

        mintSY(minAmountOut);
        mintPtYt(deltaY);

        vm.expectRevert(
            abi.encodeWithSelector(
                RMM.InsufficientOutput.selector, upscale(deltaY, scalar(address(PT))), minAmountOut + 10, minAmountOut
            )
        );
        subject().swapY(deltaY, minAmountOut + 10, address(this), "");
    }

    function test_swapY_event() public basic {
        PYIndex index = YT.newIndex();
        uint256 deltaY = 1 ether;
        (,, uint256 minAmountOut, int256 delLiq,) =
            subject().prepareSwap(address(PT), address(SY), deltaY, block.timestamp, index);
        deal(address(SY), address(subject()), minAmountOut);
        deal(address(PT), address(this), deltaY);
        PT.approve(address(subject()), deltaY);

        vm.expectEmit();
        emit RMM.Swap(address(this), address(this), address(PT), address(SY), deltaY, minAmountOut, delLiq);
        subject().swapY(deltaY, minAmountOut, address(this), "");
    }

    function test_swapY_callback() public basic {
        PYIndex index = YT.newIndex();
        uint256 deltaY = 1 ether;
        (,, uint256 minAmountOut,,) = subject().prepareSwap(address(PT), address(SY), deltaY, block.timestamp, index);
        deal(address(SY), address(subject()), minAmountOut);
        deal(address(PT), address(this), deltaY);
        PT.approve(address(subject()), deltaY);
        CallbackProvider provider = new CallbackProvider();
        vm.prank(address(provider));
        (uint256 amountOut,) = subject().swapY(deltaY, minAmountOut, address(this), "0x1");
        assertTrue(amountOut >= minAmountOut, "Amount out is not greater than or equal to min amount out.");
        assertTrue(SY.balanceOf(address(this)) >= amountOut, "Token X balance is not greater than 0.");
    }
}

contract CallbackProvider is Test {
    function callback(address token, uint256 amountNativeToPay, bytes calldata data) public returns (bool) {
        data;
        deal(token, msg.sender, MockERC20(token).balanceOf(msg.sender) + amountNativeToPay);
        return true;
    }
}