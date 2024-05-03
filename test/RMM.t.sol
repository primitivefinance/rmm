// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {RMM, toInt, toUint} from "../src/RMM.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

// slot numbers. double check these if changes are made.
uint256 constant TOKEN_X_SLOT = 0;
uint256 constant TOKEN_Y_SLOT = 1;
uint256 constant RESERVE_X_SLOT = 2;
uint256 constant RESERVE_Y_SLOT = 3;
uint256 constant TOTAL_LIQUIDITY_SLOT = 4;
uint256 constant MEAN_SLOT = 5;
uint256 constant WIDTH_SLOT = 6;
uint256 constant FEE_SLOT = 7;
uint256 constant MATURITY_SLOT = 8;
uint256 constant INIT_TIMESTAMP_SLOT = 9;
uint256 constant LAST_TIMESTAMP_SLOT = 10;
uint256 constant CURATOR_SLOT = 11;
uint256 constant LOCK_SLOT = 12;

contract RMMTest is Test {
    RMM public __subject__;
    MockERC20 public tokenX;
    MockERC20 public tokenY;

    function setUp() public tokens {
        __subject__ = new RMM(address(0));
    }

    function subject() public view returns (RMM) {
        return __subject__;
    }

    modifier tokens() {
        _;
        tokenX = new MockERC20("Token X", "X", 18);
        tokenY = new MockERC20("Token Y", "Y", 18);
        vm.label(address(tokenX), "Token X");
        vm.label(address(tokenY), "Token Y");
    }

    /// @dev Uses the "basic" set of parameters produced from DFMM LogNormal solvers.
    modifier basic() {
        vm.warp(0);
        vm.store(address(subject()), bytes32(TOKEN_X_SLOT), bytes32(uint256(uint160(address(tokenX)))));
        vm.store(address(subject()), bytes32(TOKEN_Y_SLOT), bytes32(uint256(uint160(address(tokenY)))));
        vm.store(address(subject()), bytes32(RESERVE_X_SLOT), bytes32(uint256(1000000000000000000)));
        vm.store(address(subject()), bytes32(RESERVE_Y_SLOT), bytes32(uint256(999999999999999997)));
        vm.store(address(subject()), bytes32(TOTAL_LIQUIDITY_SLOT), bytes32(uint256(3241096933647192684)));
        vm.store(address(subject()), bytes32(MEAN_SLOT), bytes32(uint256(1 ether)));
        vm.store(address(subject()), bytes32(WIDTH_SLOT), bytes32(uint256(1 ether)));
        vm.store(address(subject()), bytes32(MATURITY_SLOT), bytes32(uint256(block.timestamp + 365 days)));
        _;
    }

    function test_basic_trading_function_result() public basic {
        int256 result = subject().tradingFunction();
        assertTrue(result >= 0 && result <= 30, "Trading function result is not within init epsilon.");
    }

    function test_basic_price() public basic {
        subject().tradingFunction();
        uint256 price = subject().approxSpotPrice();
        assertApproxEqAbs(price, 1 ether, 2, "Price is not approximately 1 ether.");
    }

    function test_basic_value() public basic {
        subject().tradingFunction();
        uint256 value = subject().totalValue();
        console2.logUint(value);
        assertApproxEqAbs(value, 2 ether, 5, "Value is not approximately 2 ether.");
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

        int256 prev = subject().tradingFunction();
        subject().adjust(toInt(deltaX), toInt(0), toInt(0));
        int256 post = subject().tradingFunction();

        console2.logInt(prev);
        console2.logInt(post);

        assertTrue(post > prev, "Trading function did not increase after adjustment.");
    }

    function test_basic_adjust_single_allocate_y_increases() public basic {
        uint256 deltaY = 4;

        deal(subject().tokenY(), address(this), deltaY);
        tokenY.approve(address(subject()), deltaY);

        int256 prev = subject().tradingFunction();
        subject().adjust(toInt(0), toInt(deltaY), toInt(0));
        int256 post = subject().tradingFunction();

        console2.logInt(prev);
        console2.logInt(post);

        assertTrue(post > prev, "Trading function did not increase after adjustment.");
    }

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
            subject().tradingFunction(),
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

    function test_basic_solve_x() public basic {
        uint256 deltaX = 1 ether;
        uint256 approximatedDeltaY = 0.685040862443611931 ether;

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
            subject().tradingFunction(),
            subject().strike(),
            subject().sigma(),
            subject().lastTau()
        );
        uint256 actualDeltaX = nextReserveX - subject().reserveX();
        console2.log("nextReserveX", nextReserveX);
        console2.log("actualDeltaX", actualDeltaX);

        uint256 approxLGivenProportionalAllocate = subject().solveL(
            subject().totalLiquidity(),
            nextReserveX,
            subject().reserveY() + approximatedDeltaY,
            subject().tradingFunction(),
            subject().strike(),
            subject().sigma(),
            subject().lastTau(),
            subject().lastTau()
        );
        uint256 deltaLGivenProportionalAllocate = approxLGivenProportionalAllocate - subject().totalLiquidity();
        console2.log("deltaLGivenProportionalAllocate", deltaLGivenProportionalAllocate);

        uint256 approxLGivenSingleALlocate = subject().solveL(
            subject().totalLiquidity(),
            subject().reserveX() + deltaX,
            subject().reserveY(),
            subject().tradingFunction(),
            subject().strike(),
            subject().sigma(),
            subject().lastTau(),
            subject().lastTau()
        );
        uint256 deltaLGivenSingleAllocate = approxLGivenSingleALlocate - subject().totalLiquidity();
        console2.log("deltaLGivenSingleAllocate", deltaLGivenSingleAllocate);

        console2.log(
            "proportional allocate / single allocate",
            deltaLGivenProportionalAllocate * 1e18 / deltaLGivenSingleAllocate
        );

        uint256 approxLGivenSwap = subject().solveL(
            subject().totalLiquidity(),
            nextReserveX,
            subject().reserveY() - approximatedDeltaY,
            subject().tradingFunction(),
            subject().strike(),
            subject().sigma(),
            subject().lastTau(),
            subject().lastTau()
        );
        console2.log("approxLGivenSwap", approxLGivenSwap);
        uint256 deltaLGivenSwap = approxLGivenSwap > subject().totalLiquidity()
            ? approxLGivenSwap - subject().totalLiquidity()
            : subject().totalLiquidity() - approxLGivenSwap;
        bool isNegative = approxLGivenSwap < subject().totalLiquidity();
        console2.log("deltaLGivenSwap", deltaLGivenSwap);
        console2.log("isNegative", isNegative);

        /* uint256 approxLGivenXDecrease = subject().solveL(
            subject().totalLiquidity(),
            subject().reserveX() - deltaX,
            subject().reserveY(),
            subject().tradingFunction(),
            subject().strike(),
            subject().sigma(),
            subject().lastTau()
        );
        uint256 liq = subject().totalLiquidity();
        uint256 deltaLGivenXDecrease =
            approxLGivenXDecrease > liq ? approxLGivenXDecrease - liq : liq - approxLGivenXDecrease;
        console2.log("deltaLGivenXDecrease", deltaLGivenXDecrease);
        console2.log("isNegative", approxLGivenXDecrease < liq); */

        /* uint256 approxLGivenYDecrease = subject().solveL(
            subject().totalLiquidity(),
            subject().reserveX(),
            subject().reserveY() - approximatedDeltaY,
            subject().tradingFunction(),
            subject().strike(),
            subject().sigma(),
            subject().lastTau()
        );
        uint256 deltaLGivenYDecrease = approxLGivenYDecrease - subject().totalLiquidity();
        console2.log("deltaLGivenYDecrease", deltaLGivenYDecrease); */
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

    function test_swap_x_callback() public basic {
        uint256 deltaX = 1 ether;
        uint256 minAmountOut = 0.685040862443611931 ether;
        deal(subject().tokenY(), address(subject()), minAmountOut * 101 / 100);
        CallbackProvider provider = new CallbackProvider();
        vm.prank(address(provider));
        (uint256 amountOut, int256 deltaLiquidity) = subject().swapX(deltaX, minAmountOut - 3, address(this), "0x1");
        assertTrue(amountOut > minAmountOut, "Amount out is not greater than min amount out.");
        assertTrue(tokenY.balanceOf(address(this)) == amountOut, "Token Y balance is not greater than 0.");
    }

    function test_swap_x_over_time() public basic {
        uint256 deltaX = 1 ether;
        uint256 minAmountOut = 1000; //0.685040862443611931 ether;
        deal(subject().tokenY(), address(subject()), 1 ether);
        deal(subject().tokenX(), address(this), deltaX);
        tokenX.approve(address(subject()), deltaX);

        int256 initial = subject().tradingFunction();
        vm.warp(12 days);
        /*
        uint256 computedL = subject().computeL(
            subject().reserveX(),
            subject().totalLiquidity(),
            subject().strike(),
            subject().sigma(),
            subject().tau(),
            subject().computeTauWadYears(subject().maturity() - block.timestamp)
        );
        uint256 expectedL = 2763676832322849396;
        console2.log("expectedL", expectedL);
        */
        /* console2.log("computedL", computedL);
        console2.log(
            "diff", computedL > expectedL ? computedL - expectedL : expectedL - computedL, computedL > expectedL
        ); */
        (uint256 amountOut, int256 deltaLiquidity) = subject().swapX(deltaX, minAmountOut, address(this), "");
        int256 terminal = subject().tradingFunction();

        console2.log("initialInvariant", initial);
        console2.log("terminalInvariant", terminal);
        console2.log("amountOut", amountOut);
        console2.log("deltaLiquidity", deltaLiquidity);
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

    struct InitParams {
        address tokenX;
        address tokenY;
        uint256 reserveX;
        uint256 reserveY;
        uint256 totalLiquidity;
        uint256 strike;
        uint256 sigma;
        uint256 fee;
        uint256 maturity;
        address curator;
    }

    // event testing
    function test_init_event() public {
        vm.warp(0);
        address curator = address(0x55);
        InitParams memory params = InitParams({
            tokenX: address(tokenX),
            tokenY: address(tokenY),
            reserveX: 1 ether,
            reserveY: 1 ether,
            totalLiquidity: 1 ether,
            strike: 1 ether,
            sigma: 1 ether,
            fee: 1,
            maturity: 7 days,
            curator: curator
        });

        uint256 tau = subject().computeTauWadYears(params.maturity);
        uint256 totalLiquidity =
            subject().solveL(0, params.reserveX, params.reserveY, toInt(0), params.strike, params.sigma, tau, tau);

        deal(address(tokenX), address(this), params.reserveX);
        deal(address(tokenY), address(this), params.reserveY);
        tokenX.approve(address(subject()), params.reserveX);
        tokenY.approve(address(subject()), params.reserveY);

        vm.expectEmit();
        emit RMM.Init(
            address(this),
            address(tokenX),
            address(tokenY),
            params.reserveX,
            params.reserveY,
            totalLiquidity,
            params.strike,
            params.sigma,
            params.fee,
            params.maturity,
            curator
        );

        subject().init(
            address(tokenX),
            address(tokenY),
            params.reserveX,
            params.reserveY,
            totalLiquidity,
            params.strike,
            params.sigma,
            params.fee,
            params.maturity,
            curator
        );
    }
}

contract CallbackProvider is Test {
    function callback(address token, uint256 amountNativeToPay, bytes calldata data) public returns (bool) {
        data;
        deal(token, msg.sender, amountNativeToPay);
        return true;
    }
}
