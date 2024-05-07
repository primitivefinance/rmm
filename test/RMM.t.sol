// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {RMM, toInt, toUint, upscale, downscaleDown, scalar, sum, abs} from "../src/RMM.sol";
import {FeeOnTransferToken} from "../src/test/FeeOnTransferToken.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ReturnsTooLittleToken} from "solmate/test/utils/weird-tokens/ReturnsTooLittleToken.sol";
import {ReturnsTooMuchToken} from "solmate/test/utils/weird-tokens/ReturnsTooMuchToken.sol";
import {MissingReturnToken} from "solmate/test/utils/weird-tokens/MissingReturnToken.sol";
import {ReturnsFalseToken} from "solmate/test/utils/weird-tokens/ReturnsFalseToken.sol";

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

contract RMMTest is Test {
    RMM public __subject__;
    MockERC20 public tokenX;
    MockERC20 public tokenY;

    function setUp() public tokens {
        __subject__ = new RMM(address(0), "LPToken", "LPT");
        vm.label(address(__subject__), "RMM");
        vm.warp(0);
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

    modifier tokens() {
        _;
        tokenX = new MockERC20("Token X", "X", 18);
        tokenY = new MockERC20("Token Y", "Y", 18);
        vm.label(address(tokenX), "Token X");
        vm.label(address(tokenY), "Token Y");
    }

    /// @dev Uses the "basic" set of parameters produced from DFMM LogNormal solvers.
    modifier basic_override() {
        vm.store(address(subject()), bytes32(TOKEN_X_SLOT), bytes32(uint256(uint160(address(tokenX)))));
        vm.store(address(subject()), bytes32(TOKEN_Y_SLOT), bytes32(uint256(uint160(address(tokenY)))));
        vm.store(address(subject()), bytes32(RESERVE_X_SLOT), bytes32(uint256(1000000000000000000)));
        vm.store(address(subject()), bytes32(RESERVE_Y_SLOT), bytes32(uint256(999999999999999997)));
        vm.store(address(subject()), bytes32(TOTAL_LIQUIDITY_SLOT), bytes32(uint256(3241096933647192684)));
        vm.store(address(subject()), bytes32(STRIKE_SLOT), bytes32(uint256(1 ether)));
        vm.store(address(subject()), bytes32(SIGMA_SLOT), bytes32(uint256(1 ether)));
        vm.store(address(subject()), bytes32(MATURITY_SLOT), bytes32(uint256(block.timestamp + 365 days)));
        _;
    }

    modifier basic() {
        deal(address(tokenX), address(this), 100 ether);
        deal(address(tokenY), address(this), 100 ether);
        tokenX.approve(address(subject()), 100 ether);
        tokenY.approve(address(subject()), 100 ether);
        subject().init({
            tokenX_: address(tokenX),
            tokenY_: address(tokenY),
            priceX: 1 ether,
            amountX: 1 ether,
            strike_: 1 ether,
            sigma_: 1 ether,
            fee_: 0,
            maturity_: 365 days,
            curator_: address(0x55)
        });

        _;
    }

    function test_basic_trading_function_result() public basic {
        int256 result = subject().tradingFunction();
        assertTrue(result >= 0 && result <= 30, "Trading function result is not within init epsilon.");
    }

    // todo: whats the error?
    function test_basic_price() public basic {
        subject().tradingFunction();
        uint256 price = subject().approxSpotPrice();
        assertApproxEqAbs(price, 1 ether, 10000, "Price is not approximately 1 ether.");
    }

    // todo: whats the error?
    function test_basic_value() public basic {
        subject().tradingFunction();
        uint256 value = subject().totalValue();
        console2.logUint(value);
        assertApproxEqAbs(value, 2 ether, 10000, "Value is not approximately 2 ether.");
    }

    // no fee btw
    function test_basic_adjust_invalid_allocate() public basic {
        uint256 deltaX = 1 ether;
        uint256 approximatedDeltaY = 0.685040862443611931 ether;

        deal(subject().tokenX(), address(this), deltaX);
        deal(subject().tokenY(), address(this), approximatedDeltaY);
        tokenX.approve(address(subject()), deltaX);
        tokenY.approve(address(subject()), approximatedDeltaY);

        vm.expectRevert();
        subject().adjust(toInt(deltaX), -toInt(approximatedDeltaY - 3), toInt(1 ether));
    }

    function test_basic_adjust_single_allocate_x_increases() public basic {
        uint256 deltaX = 1;

        deal(subject().tokenX(), address(this), deltaX);
        tokenX.approve(address(subject()), deltaX);

        subject().adjust(toInt(deltaX), toInt(0), toInt(0));
        int256 post = subject().tradingFunction();

        assertTrue(abs(post) < 10, "Trading function invalid.");
    }

    function test_basic_adjust_single_allocate_y_increases() public basic {
        uint256 deltaY = 4;

        deal(subject().tokenY(), address(this), deltaY);
        tokenY.approve(address(subject()), deltaY);

        subject().adjust(toInt(0), toInt(deltaY), toInt(0));
        int256 post = subject().tradingFunction();

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
        uint256 deltaX = 1 ether;
        (,, uint256 approximatedDeltaY,) = subject().prepareSwap(address(tokenX), address(tokenY), deltaX);

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
        uint256 deltaX = 1 ether;
        uint256 minAmountOut = 0.685040862443611931 ether;
        deal(subject().tokenY(), address(subject()), minAmountOut * 110 / 100);
        deal(subject().tokenX(), address(this), deltaX);
        tokenX.approve(address(subject()), deltaX);

        int256 initial = subject().tradingFunction();
        console2.log("loss", uint256(685040862443611928) - uint256(685001492551417433));
        console2.log("loss %", uint256(39369892194495) * 1 ether / uint256(685001492551417433));
        (uint256 amountOut, int256 deltaLiquidity) = subject().swapX(deltaX, minAmountOut - 3, address(this), "");
        int256 terminal = subject().tradingFunction();
        console2.logInt(initial);
        console2.logInt(terminal);
        console2.logUint(amountOut);
        console2.logInt(deltaLiquidity);
    }

    function test_swapX_callback() public basic {
        uint256 deltaX = 1 ether;
        (,, uint256 minAmountOut,) = subject().prepareSwap(address(tokenX), address(tokenY), deltaX);
        deal(subject().tokenY(), address(subject()), minAmountOut);
        CallbackProvider provider = new CallbackProvider();
        vm.prank(address(provider));
        (uint256 amountOut,) = subject().swapX(deltaX, minAmountOut, address(this), "0x1");
        assertTrue(amountOut >= minAmountOut, "Amount out is not greater than min amount out.");
        assertTrue(tokenY.balanceOf(address(this)) >= amountOut, "Token Y balance is not greater than 0.");
    }

    function test_swapX_over_time() public basic {
        uint256 deltaX = 1 ether;
        (,, uint256 minAmountOut,) = subject().prepareSwap(address(tokenX), address(tokenY), deltaX);
        deal(subject().tokenY(), address(subject()), 1 ether);
        deal(subject().tokenX(), address(this), deltaX);
        tokenX.approve(address(subject()), deltaX);

        int256 initial = subject().tradingFunction();
        vm.warp(365 days / 2);

        uint256 expectedL = 2763676832322849396;
        console2.log("expectedL", expectedL);
        (uint256 amountOut, int256 deltaLiquidity) = subject().swapX(deltaX, minAmountOut, address(this), "");
        int256 terminal = subject().tradingFunction();

        console2.log("initialInvariant", initial);
        console2.log("terminalInvariant", terminal);
        console2.log("amountOut", amountOut);
        console2.log("deltaLiquidity", deltaLiquidity);
        assertTrue(abs(terminal) < 10, "Trading function invalid.");
    }

    function test_price_increase_over_time() public basic {
        uint256 timeDelta = 10 days;

        uint256 initial = subject().approxSpotPrice();
        vm.warp(timeDelta);
        vm.store(address(subject()), bytes32(LAST_TIMESTAMP_SLOT), bytes32(uint256(block.timestamp)));
        uint256 terminal = subject().approxSpotPrice();

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
        sigma: 1 ether,
        fee: 0,
        maturity: 365 days,
        curator: address(0x55)
    });

    // init

    function test_init_event() public {
        (uint256 totalLiquidity, uint256 amountY) = subject().prepareInit({
            priceX: basicParams.priceX,
            amountX: basicParams.amountX,
            strike_: basicParams.strike,
            sigma_: basicParams.sigma,
            maturity_: basicParams.maturity
        });
        deal(address(tokenX), address(this), basicParams.amountX);
        deal(address(tokenY), address(this), amountY);
        tokenX.approve(address(subject()), basicParams.amountX);
        tokenY.approve(address(subject()), amountY);

        vm.expectEmit();
        emit RMM.Init(
            address(this),
            address(tokenX),
            address(tokenY),
            basicParams.amountX,
            amountY,
            totalLiquidity,
            basicParams.strike,
            basicParams.sigma,
            basicParams.fee,
            basicParams.maturity,
            basicParams.curator
        );

        subject().init(
            address(tokenX),
            address(tokenY),
            basicParams.priceX,
            basicParams.amountX,
            basicParams.strike,
            basicParams.sigma,
            basicParams.fee,
            basicParams.maturity,
            basicParams.curator
        );
    }

    function test_init_reverts_with_InvalidDecimals_greater() public {
        (uint256 totalLiquidity, uint256 amountY) = subject().prepareInit({
            priceX: 1 ether,
            amountX: basicParams.amountX,
            strike_: basicParams.strike,
            sigma_: basicParams.sigma,
            maturity_: basicParams.maturity
        });
        MockERC20 token = new MockERC20("Token", "T", 20);
        vm.expectRevert(abi.encodeWithSelector(RMM.InvalidDecimals.selector, address(token), 20));
        subject().init(
            address(token),
            address(tokenY),
            basicParams.priceX,
            basicParams.amountX,
            basicParams.strike,
            basicParams.sigma,
            basicParams.fee,
            basicParams.maturity,
            address(0)
        );
    }

    function test_init_reverts_with_InvalidDecimals_lesser() public {
        MockERC20 token = new MockERC20("Token", "T", 3);
        vm.expectRevert(abi.encodeWithSelector(RMM.InvalidDecimals.selector, address(token), 3));
        subject().init(
            address(token),
            address(tokenY),
            basicParams.priceX,
            basicParams.amountX,
            basicParams.strike,
            basicParams.sigma,
            basicParams.fee,
            basicParams.maturity,
            address(0)
        );
    }

    function test_init_debits_x() public {
        (uint256 totalLiquidity, uint256 amountY) = subject().prepareInit({
            priceX: 1 ether,
            amountX: basicParams.amountX,
            strike_: basicParams.strike,
            sigma_: basicParams.sigma,
            maturity_: basicParams.maturity
        });
        deal(address(tokenX), address(this), basicParams.amountX);
        deal(address(tokenY), address(this), amountY);
        tokenX.approve(address(subject()), basicParams.amountX);
        tokenY.approve(address(subject()), amountY);

        uint256 balance = tokenX.balanceOf(address(this));
        subject().init(
            address(tokenX),
            address(tokenY),
            basicParams.priceX,
            basicParams.amountX,
            basicParams.strike,
            basicParams.sigma,
            basicParams.fee,
            basicParams.maturity,
            basicParams.curator
        );
        uint256 newBalance = tokenX.balanceOf(address(this));
        assertEq(balance - newBalance, basicParams.amountX, "Token X balance did not decrease by reserve amount.");
    }

    function test_init_debits_y() public {
        (uint256 totalLiquidity, uint256 amountY) = subject().prepareInit({
            priceX: 1 ether,
            amountX: basicParams.amountX,
            strike_: basicParams.strike,
            sigma_: basicParams.sigma,
            maturity_: basicParams.maturity
        });
        deal(address(tokenX), address(this), basicParams.amountX);
        deal(address(tokenY), address(this), amountY);
        tokenX.approve(address(subject()), basicParams.amountX);
        tokenY.approve(address(subject()), amountY);

        uint256 balance = tokenY.balanceOf(address(this));
        subject().init(
            address(tokenX),
            address(tokenY),
            basicParams.priceX,
            basicParams.amountX,
            basicParams.strike,
            basicParams.sigma,
            basicParams.fee,
            basicParams.maturity,
            basicParams.curator
        );
        uint256 newBalance = tokenY.balanceOf(address(this));
        assertEq(balance - newBalance, amountY, "Token Y balance did not decrease by reserve amount.");
    }

    function test_init_pool() public {
        deal(address(tokenX), address(this), 100e18);
        deal(address(tokenY), address(this), 100e18);
        tokenX.approve(address(subject()), 100e18);
        tokenY.approve(address(subject()), 100e18);

        (uint256 totalLiquidity, uint256 amountY) = subject().prepareInit({
            priceX: 1 ether,
            amountX: basicParams.amountX,
            strike_: basicParams.strike,
            sigma_: basicParams.sigma,
            maturity_: basicParams.maturity
        });

        console2.log("amountY", amountY);

        subject().init(
            address(tokenX),
            address(tokenY),
            basicParams.priceX,
            basicParams.amountX,
            basicParams.strike,
            basicParams.sigma,
            basicParams.fee,
            basicParams.maturity,
            basicParams.curator
        );

        assertEq(subject().tokenX(), address(tokenX), "Token X address is not correct.");
        assertEq(subject().tokenY(), address(tokenY), "Token Y address is not correct.");
        assertEq(subject().reserveX(), basicParams.amountX, "Reserve X is not correct.");
        assertEq(subject().reserveY(), amountY, "Reserve Y is not correct.");
        assertEq(subject().totalLiquidity(), totalLiquidity, "Total liquidity is not correct.");
        assertEq(subject().strike(), basicParams.strike, "Strike is not correct.");
        assertEq(subject().sigma(), basicParams.sigma, "Sigma is not correct.");
        assertEq(subject().fee(), basicParams.fee, "Fee is not correct.");
        assertEq(subject().maturity(), basicParams.maturity, "Maturity is not correct.");
        assertEq(subject().initTimestamp(), block.timestamp, "Init timestamp is not correct.");
        assertEq(subject().lastTimestamp(), block.timestamp, "Last timestamp is not correct.");
        assertEq(subject().curator(), basicParams.curator, "Curator is not correct.");
    }

    function test_init_reverts_InsufficientPayment_fee_on_transfer_token() public {
        (uint256 totalLiquidity, uint256 amountY) = subject().prepareInit({
            priceX: 1 ether,
            amountX: basicParams.amountX,
            strike_: basicParams.strike,
            sigma_: basicParams.sigma,
            maturity_: basicParams.maturity
        });

        FeeOnTransferToken token = new FeeOnTransferToken();
        FeeOnTransferToken token2 = new FeeOnTransferToken();
        deal(address(token), address(this), 1 ether);
        deal(address(token2), address(this), 1 ether);
        token.approve(address(subject()), 1 ether);
        token2.approve(address(subject()), 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                RMM.InsufficientPayment.selector,
                address(token),
                basicParams.amountX * (1 ether - token.transferFee()) / 1 ether,
                1 ether
            )
        );
        subject().init(
            address(token),
            address(token2),
            basicParams.priceX,
            basicParams.amountX,
            basicParams.strike,
            basicParams.sigma,
            basicParams.fee,
            basicParams.maturity,
            address(0)
        );
    }

    function test_swapX() public basic {
        uint256 deltaX = 1 ether;
        (,, uint256 minAmountOut,) = subject().prepareSwap(address(tokenX), address(tokenY), deltaX);
        deal(address(tokenY), address(subject()), minAmountOut);
        deal(address(tokenX), address(this), deltaX);
        tokenX.approve(address(subject()), deltaX);

        uint256 prevBalanceX = balanceWad(address(tokenX), address(this));
        uint256 prevBalanceY = balanceWad(address(tokenY), address(this));
        uint256 prevReserveY = subject().reserveY();
        uint256 prevPrice = subject().approxSpotPrice();
        uint256 prevLiquidity = subject().totalLiquidity();
        (uint256 amountOut, int256 deltaLiquidity) = subject().swapX(deltaX, minAmountOut - 3, address(this), "");

        assertTrue(amountOut >= minAmountOut, "Amount out is not greater than or equal to min amount out.");
        assertTrue(abs(subject().tradingFunction()) < 10, "Invalid trading function state.");
        assertEq(subject().reserveX(), basicParams.amountX + deltaX, "Reserve X did not increase by delta X.");
        assertEq(subject().reserveY(), prevReserveY - amountOut, "Reserve Y did not decrease by amount out.");
        assertEq(
            subject().totalLiquidity(),
            sum(prevLiquidity, deltaLiquidity),
            "Total liquidity did not increase by delta liquidity."
        );

        assertEq(
            balanceWad(address(tokenX), address(this)), prevBalanceX - deltaX, "Balance X did not decrease by delta X."
        );
        assertEq(
            balanceWad(address(tokenY), address(this)),
            prevBalanceY + amountOut,
            "Balance Y did not increase by amount out."
        );
        assertTrue(subject().approxSpotPrice() < prevPrice, "Price did not decrease after selling X.");
    }

    function test_swapX_reverts_InsufficientOutput() public basic {
        uint256 deltaX = 1 ether;
        (,, uint256 minAmountOut,) = subject().prepareSwap(address(tokenX), address(tokenY), deltaX);
        deal(address(tokenY), address(subject()), minAmountOut);
        deal(address(tokenX), address(this), deltaX);
        tokenX.approve(address(subject()), deltaX);

        vm.expectRevert(
            abi.encodeWithSelector(
                RMM.InsufficientOutput.selector,
                upscale(deltaX, scalar(address(tokenX))),
                minAmountOut + 10,
                minAmountOut
            )
        );
        subject().swapX(deltaX, minAmountOut + 10, address(this), "");
    }

    function test_swapX_event() public basic {
        uint256 deltaX = 1 ether;
        (,, uint256 minAmountOut, int256 delLiq) = subject().prepareSwap(address(tokenX), address(tokenY), deltaX);
        deal(address(tokenY), address(subject()), minAmountOut);
        deal(address(tokenX), address(this), deltaX);
        tokenX.approve(address(subject()), deltaX);

        vm.expectEmit();
        emit RMM.Swap(address(this), address(this), address(tokenX), address(tokenY), deltaX, minAmountOut, delLiq);
        subject().swapX(deltaX, minAmountOut, address(this), "");
    }

    function test_swapY() public basic {
        uint256 deltaY = 1 ether;
        (,, uint256 minAmountOut,) = subject().prepareSwap(address(tokenY), address(tokenX), deltaY);
        deal(address(tokenX), address(subject()), minAmountOut);
        deal(address(tokenY), address(this), deltaY);
        tokenY.approve(address(subject()), deltaY);

        uint256 prevBalanceX = balanceWad(address(tokenX), address(this));
        uint256 prevBalanceY = balanceWad(address(tokenY), address(this));
        uint256 prevPrice = subject().approxSpotPrice();
        uint256 prevReserveY = subject().reserveY();
        uint256 prevLiquidity = subject().totalLiquidity();
        (uint256 amountOut, int256 deltaLiquidity) = subject().swapY(deltaY, minAmountOut, address(this), "");

        assertTrue(amountOut >= minAmountOut, "Amount out is not greater than or equal to min amount out.");
        assertTrue(abs(subject().tradingFunction()) < 10, "Trading function invalid");
        assertEq(subject().reserveX(), basicParams.amountX - amountOut, "Reserve X did not decrease by amount in.");
        assertEq(subject().reserveY(), prevReserveY + deltaY, "Reserve Y did not increase by delta Y.");
        assertEq(
            subject().totalLiquidity(),
            sum(prevLiquidity, deltaLiquidity),
            "Total liquidity did not increase by delta liquidity."
        );

        assertEq(
            balanceWad(address(tokenX), address(this)),
            prevBalanceX + amountOut,
            "Balance X did not increase by amount in."
        );
        assertEq(
            balanceWad(address(tokenY), address(this)), prevBalanceY - deltaY, "Balance Y did not decrease by delta Y."
        );
        assertTrue(subject().approxSpotPrice() > prevPrice, "Price did not increase after buying Y.");
    }

    function test_swapY_reverts_InsufficientOutput() public basic {
        uint256 deltaY = 1 ether;
        (,, uint256 minAmountOut,) = subject().prepareSwap(address(tokenY), address(tokenX), deltaY);
        deal(address(tokenX), address(subject()), minAmountOut);
        deal(address(tokenY), address(this), deltaY);
        tokenY.approve(address(subject()), deltaY);

        vm.expectRevert(
            abi.encodeWithSelector(
                RMM.InsufficientOutput.selector,
                upscale(deltaY, scalar(address(tokenY))),
                minAmountOut + 10,
                minAmountOut
            )
        );
        subject().swapY(deltaY, minAmountOut + 10, address(this), "");
    }

    function test_swapY_event() public basic {
        uint256 deltaY = 1 ether;
        (,, uint256 minAmountOut, int256 delLiq) = subject().prepareSwap(address(tokenY), address(tokenX), deltaY);
        deal(address(tokenX), address(subject()), minAmountOut);
        deal(address(tokenY), address(this), deltaY);
        tokenY.approve(address(subject()), deltaY);

        vm.expectEmit();
        emit RMM.Swap(address(this), address(this), address(tokenY), address(tokenX), deltaY, minAmountOut, delLiq);
        subject().swapY(deltaY, minAmountOut, address(this), "");
    }

    function test_swapY_callback() public basic {
        uint256 deltaY = 1 ether;
        (,, uint256 minAmountOut,) = subject().prepareSwap(address(tokenY), address(tokenX), deltaY);
        deal(address(tokenX), address(subject()), minAmountOut);
        deal(address(tokenY), address(this), deltaY);
        tokenY.approve(address(subject()), deltaY);
        CallbackProvider provider = new CallbackProvider();
        vm.prank(address(provider));
        (uint256 amountOut,) = subject().swapY(deltaY, minAmountOut, address(this), "0x1");
        assertTrue(amountOut >= minAmountOut, "Amount out is not greater than or equal to min amount out.");
        assertTrue(tokenX.balanceOf(address(this)) >= amountOut, "Token X balance is not greater than 0.");
    }

    function test_allocate() public basic {
        uint256 deltaX = 1 ether;
        uint256 deltaY = 1 ether;
        deal(address(tokenX), address(this), deltaX);
        deal(address(tokenY), address(this), deltaY);
        tokenX.approve(address(subject()), deltaX);
        tokenY.approve(address(subject()), deltaY);

        uint256 prevReserveY = subject().reserveY();
        uint256 prevLiquidity = subject().totalLiquidity();
        uint256 deltaLiquidity = subject().allocate(deltaX, deltaY, 1, address(this));
        assertTrue(deltaLiquidity >= 1, "Delta liquidity is not at least minDeltaLiquidity");
        assertEq(subject().reserveX(), basicParams.amountX + deltaX, "Reserve X did not increase by delta X.");
        assertEq(subject().reserveY(), prevReserveY + deltaY, "Reserve Y did not increase by delta Y.");
        assertEq(
            subject().totalLiquidity(),
            prevLiquidity + deltaLiquidity,
            "Total liquidity did not increase by delta liquidity."
        );
    }

    function test_deallocate() public basic {
        uint256 amount = 1 ether;
        deal(address(tokenX), address(this), amount);
        tokenX.approve(address(subject()), amount);
        deal(address(tokenY), address(this), amount);
        tokenY.approve(address(subject()), amount);

        uint256 deltaLiquidity = subject().allocate(amount, amount, 1, address(this));

        uint256 prevBalanceX = balanceWad(address(tokenX), address(this));
        uint256 prevBalanceY = balanceWad(address(tokenY), address(this));
        (uint256 deltaX, uint256 deltaY) = subject().deallocate(deltaLiquidity, 1, 1, address(this));

        assertEq(
            balanceWad(address(tokenX), address(this)), prevBalanceX + deltaX, "Balance X did not increase by delta X."
        );
        assertEq(
            balanceWad(address(tokenY), address(this)), prevBalanceY + deltaY, "Balance Y did not increase by delta Y."
        );
    }
}

contract CallbackProvider is Test {
    function callback(address token, uint256 amountNativeToPay, bytes calldata data) public returns (bool) {
        data;
        deal(token, msg.sender, MockERC20(token).balanceOf(msg.sender) + amountNativeToPay);
        return true;
    }
}
