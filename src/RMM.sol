// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Gaussian} from "solstat/Gaussian.sol";
import {console2} from "forge-std/console2.sol";

interface Token {
    function decimals() external view returns (uint8);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface ICallback {
    function callback(address token, uint256 amountNative, bytes calldata data) external returns (bool);
}

contract RMM {
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;

    /// @dev Thrown when a `balanceOf` call fails or returns unexpected data.
    error BalanceError();
    /// @dev Thrown when a payment to this contract is insufficient.
    error InsufficientPayment(address token, uint256 actual, uint256 expected);
    /// @dev Thrown when a mint does not output enough liquidity.
    error InsufficientLiquidityMinted(uint256 deltaX, uint256 deltaY, uint256 minLiquidity, uint256 liquidity);
    /// @dev Thrown when a swap does not output enough tokens.
    error InsufficientOutput(uint256 amountIn, uint256 minAmountOut, uint256 amountOut);
    /// @dev Thrown on `init` when a token has invalid decimals.
    error InvalidDecimals(address token, uint256 decimals);
    /// @dev Thrown when an input to the trading function is outside the domain for the X reserve.
    error OutOfBoundsX(uint256 value);
    /// @dev Thrown when an input to the trading function is outside the domain for the Y reserve.
    error OutOfBoundsY(uint256 value);
    /// @dev Thrown when the trading function result is less than the previous invariant.
    error OutOfRange(int256 initial, int256 terminal);
    /// @dev Thrown when a payment to or from the user returns false or no data.
    error PaymentFailed(address token, address from, address to, uint256 amount);
    /// @dev Thrown when an external call is made within the same frame as another.
    error Reentrancy();

    /// @dev Emitted on pool creation.
    event Init(
        address caller,
        address indexed tokenX,
        address indexed tokenY,
        uint256 reserveX,
        uint256 reserveY,
        uint256 totalLiquidity,
        uint256 strike,
        uint256 sigma,
        uint256 fee,
        uint256 maturity,
        address indexed curator
    );
    /// @dev Emitted on swaps.
    event Swap(
        address caller,
        address indexed to,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        int256 deltaLiquidity
    );
    /// @dev Emitted on allocatess.
    event Allocate(address indexed caller, uint256 deltaX, uint256 deltaY, uint256 deltaLiquidity);
    /// @dev Emitted on deallocates.
    event Deallocate(address indexed caller, uint256 deltaX, uint256 deltaY, uint256 deltaLiquidity);

    int256 public constant INIT_UPPER_BOUND = 30;
    address public immutable WETH;
    address public tokenX; // slot 0
    address public tokenY; // slot 1
    uint256 public reserveX; // slot 2
    uint256 public reserveY; // slot 3
    uint256 public totalLiquidity; // slot 4
    uint256 public strike; // slot 5
    uint256 public sigma; // slot 6
    uint256 public fee; // slot 7
    uint256 public maturity; // slot 8
    uint256 public initTimestamp; // slot 9
    uint256 public lastTimestamp; // slot 10
    address public curator; // slot 11
    uint256 public lock_ = 1; // slot 12
    // TODO: go back to calling it strike, sigma, tau, strike and sigma is cringe

    modifier lock() {
        if (lock_ != 1) revert Reentrancy();
        lock_ = 0;
        _;
        lock_ = 1;
    }

    /// @dev Applies updates to the trading function and validates the adjustment.
    modifier evolve() {
        console2.log("initial");
        int256 initial = tradingFunction();
        _;
        console2.log("terminal");
        int256 terminal = tradingFunction();

        if (terminal < initial) {
            revert OutOfRange(initial, terminal);
        }
    }

    constructor(address weth_) {
        WETH = weth_;
    }

    receive() external payable {}

    /// @dev Initializes the pool with an implied price via the desired reserves, liquidity, and parameters.
    function init(
        address tokenX_,
        address tokenY_,
        uint256 reserveX_,
        uint256 reserveY_,
        uint256 totalLiquidity_,
        uint256 mean_,
        uint256 width_,
        uint256 fee_,
        uint256 maturity_,
        address curator_
    ) external lock evolve {
        tokenX = tokenX_;
        tokenY = tokenY_;
        reserveX = reserveX_;
        reserveY = reserveY_;
        totalLiquidity = totalLiquidity_;
        strike = mean_;
        sigma = width_;
        fee = fee_;
        maturity = maturity_;
        initTimestamp = block.timestamp;
        lastTimestamp = block.timestamp;
        curator = curator_;

        /* int256 result = tradingFunction();
        if (result > INIT_UPPER_BOUND || result < 0) {
            revert OutOfRange(0, result);
        } */

        uint256 decimals = Token(tokenX).decimals();
        if (decimals > 18 || decimals < 6) revert InvalidDecimals(tokenX, decimals);

        decimals = Token(tokenY).decimals();
        if (decimals > 18 || decimals < 6) revert InvalidDecimals(tokenY, decimals);

        _debit(tokenX, reserveX, "");
        _debit(tokenY, reserveY, "");

        emit Init(
            msg.sender,
            tokenX_,
            tokenY_,
            reserveX_,
            reserveY_,
            totalLiquidity_,
            mean_,
            width_,
            fee_,
            maturity_,
            curator_
        );
    }

    /// @dev Allows an arbitrary adjustment to the reserves and liquidity, if it is valid.
    function adjust(int256 deltaX, int256 deltaY, int256 deltaLiquidity) external lock {
        _adjust(deltaX, deltaY, deltaLiquidity);
        if (deltaX < 0) _credit(tokenX, msg.sender, uint256(-deltaX));
        if (deltaY < 0) _credit(tokenY, msg.sender, uint256(-deltaY));
        if (deltaX > 0) _debit(tokenX, uint256(deltaX), "");
        if (deltaY > 0) _debit(tokenY, uint256(deltaY), "");
    }

    /// @dev Applies an adjustment to the reserves, liquidity, and last timestamp before validating it with the trading function.
    function _adjust(int256 deltaX, int256 deltaY, int256 deltaLiquidity) internal evolve {
        reserveX = sum(reserveX, deltaX);
        reserveY = sum(reserveY, deltaY);
        totalLiquidity = sum(totalLiquidity, deltaLiquidity);
    }

    /// @dev Swaps tokenX to tokenY, sending at least `minAmountOut` tokenY to `to`.
    function swapX(uint256 amountIn, uint256 minAmountOut, address to, bytes calldata data)
        external
        lock
        returns (uint256 amountOut, int256 deltaLiquidity)
    {
        uint256 feeAmount = amountIn.mulWadUp(fee);
        uint256 tau_ = currentTau();
        uint256 nextLiquidity =
            solveL(totalLiquidity, reserveX + feeAmount, reserveY, tradingFunction(), strike, sigma, lastTau(), tau_);
        uint256 nextReserveY =
            solveY(reserveX + amountIn - feeAmount, nextLiquidity, tradingFunction(), strike, sigma, tau_);
        lastTimestamp = block.timestamp;

        amountOut = reserveY - nextReserveY;
        if (amountOut < minAmountOut) {
            revert InsufficientOutput(amountIn, minAmountOut, amountOut);
        }

        deltaLiquidity = toInt(nextLiquidity) - toInt(totalLiquidity);

        _adjust(toInt(amountIn), -toInt(amountOut), deltaLiquidity);
        (uint256 creditNative) = _credit(tokenY, to, amountOut);
        (uint256 debitNative) = _debit(tokenX, amountIn, data);

        emit Swap(msg.sender, to, tokenX, tokenY, debitNative, creditNative, deltaLiquidity);
    }

    function swapY(uint256 amountIn, uint256 minAmountOut, address to, bytes calldata data)
        external
        lock
        returns (uint256 amountOut, int256 deltaLiquidity)
    {
        uint256 feeAmount = amountIn.mulWadUp(fee);
        uint256 nextReserveX = solveX(reserveY + amountIn, totalLiquidity, tradingFunction(), strike, sigma, lastTau());
        uint256 tau_ = currentTau();
        uint256 nextLiquidity =
            solveL(totalLiquidity, reserveY + feeAmount, reserveY, tradingFunction(), strike, sigma, lastTau(), tau_);

        amountOut = reserveX - nextReserveX;
        if (amountOut < minAmountOut) {
            revert InsufficientOutput(amountIn, minAmountOut, amountOut);
        }

        deltaLiquidity = toInt(nextLiquidity) - toInt(totalLiquidity);

        _adjust(-toInt(amountOut), toInt(amountIn), deltaLiquidity);
        (uint256 creditNative) = _credit(tokenX, to, amountOut);
        (uint256 debitNative) = _debit(tokenY, amountIn, data);

        emit Swap(msg.sender, to, tokenY, tokenX, debitNative, creditNative, deltaLiquidity);
    }

    function allocate(uint256 deltaX, uint256 deltaY, uint256 minLiquidityOut)
        external
        lock
        returns (uint256 deltaLiquidity)
    {
        uint256 tau_ = currentTau();
        uint256 nextLiquidity = solveL(
            totalLiquidity, reserveX + deltaX, reserveY + deltaY, tradingFunction(), strike, sigma, lastTau(), tau_
        );
        deltaLiquidity = nextLiquidity - totalLiquidity;
        if (deltaLiquidity < minLiquidityOut) {
            revert InsufficientLiquidityMinted(deltaX, deltaY, minLiquidityOut, deltaLiquidity);
        }
        _adjust(toInt(deltaX), toInt(deltaY), toInt(deltaLiquidity));
        (uint256 debitNativeX) = _debit(tokenX, deltaX, "");
        (uint256 debitNativeY) = _debit(tokenY, deltaY, "");

        emit Allocate(msg.sender, debitNativeX, debitNativeY, deltaLiquidity);
    }

    function deallocate(uint256 deltaLiquidity, uint256 minDeltaXOut, uint256 minDeltaYOut)
        external
        lock
        returns (uint256 deltaX, uint256 deltaY)
    {
        uint256 tau_ = currentTau();
        uint256 nextReserveX = solveX(reserveY, totalLiquidity - deltaLiquidity, tradingFunction(), strike, sigma, tau_);
        uint256 nextReserveY = solveY(reserveX, totalLiquidity - deltaLiquidity, tradingFunction(), strike, sigma, tau_);
        deltaX = reserveX - nextReserveX;
        deltaY = reserveY - nextReserveY;
        if (deltaX < minDeltaXOut || deltaY < minDeltaYOut) {
            revert InsufficientOutput(deltaLiquidity, minDeltaXOut, deltaX);
        }
        _adjust(-toInt(deltaX), -toInt(deltaY), -toInt(deltaLiquidity));
        (uint256 creditNativeX) = _credit(tokenX, msg.sender, deltaX);
        (uint256 creditNativeY) = _credit(tokenY, msg.sender, deltaY);

        emit Deallocate(msg.sender, creditNativeX, creditNativeY, deltaLiquidity);
    }

    // payments

    /// @dev Handles the request of payment for a given token.
    /// @param data Avoid the callback by passing empty data. Trigger the callback and pass the data through otherwise.
    function _debit(address token, uint256 amountWad, bytes memory data) internal returns (uint256 paymentNative) {
        uint256 balanceNative = _balanceNative(token);
        uint256 amountNative = downscaleDown(amountWad, _scalar(token));

        if (data.length > 0) {
            if (!ICallback(msg.sender).callback(token, amountNative, data)) {
                revert PaymentFailed(token, msg.sender, address(this), amountNative);
            }
        } else {
            if (!Token(token).transferFrom(msg.sender, address(this), amountNative)) {
                revert PaymentFailed(token, msg.sender, address(this), amountNative);
            }
        }

        paymentNative = _balanceNative(token) - balanceNative;
        if (paymentNative < amountNative) {
            revert InsufficientPayment(token, paymentNative, amountNative);
        }
    }

    /// @dev Handles sending tokens as payment to the recipient `to`.
    function _credit(address token, address to, uint256 amount) internal returns (uint256 paymentNative) {
        uint256 balanceNative = _balanceNative(token);
        uint256 amountNative = downscaleDown(amount, _scalar(token));

        // Send the tokens to the recipient.
        if (!Token(token).transfer(to, amountNative)) {
            revert PaymentFailed(token, address(this), to, amountNative);
        }

        paymentNative = balanceNative - _balanceNative(token);
        if (paymentNative < amountNative) {
            revert InsufficientPayment(token, paymentNative, amountNative);
        }
    }

    /// @dev Computes the scalar to multiply to convert between WAD and native units.
    function _scalar(address token) internal view returns (uint256) {
        uint256 decimals = Token(token).decimals();
        uint256 difference = 18 - decimals;
        return FixedPointMathLib.WAD * 10 ** difference;
    }

    /// @dev Retrieves the balance of a token in this contract, reverting if the call fails or returns unexpected data.
    function _balanceNative(address token) internal view returns (uint256) {
        (bool success, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(Token.balanceOf.selector, address(this)));
        if (!success || data.length != 32) revert BalanceError();
        return abi.decode(data, (uint256));
    }

    // maths

    /// @dev Computes the time to maturity based on the `lastTimestamp` and converts it to units of WAD years.
    function lastTau() public view returns (uint256) {
        if (maturity < lastTimestamp) {
            return 0;
        }

        return computeTauWadYears(maturity - lastTimestamp);
    }

    /// @dev Computes the time to maturity based on the current `block.timestamp` and converts it to units of WAD years.
    function currentTau() public view returns (uint256) {
        if (maturity < block.timestamp) {
            return 0;
        }

        return computeTauWadYears(maturity - block.timestamp);
    }

    /// @dev Computes the trading function result using the current state.
    function tradingFunction() public view returns (int256) {
        if (totalLiquidity == 0) return 0; // Not initialized.

        return computeTradingFunction(reserveX, reserveY, totalLiquidity, strike, sigma, lastTau());
    }

    /// @dev k = Φ⁻¹(x/L) + Φ⁻¹(y/μL)  + σ√τ
    function computeTradingFunction(
        uint256 reserveX_,
        uint256 reserveY_,
        uint256 liquidity,
        uint256 mean_,
        uint256 width_,
        uint256 tau_
    ) public pure returns (int256) {
        uint256 a_i = reserveX_ * 1e18 / liquidity;
        if (a_i >= 1 ether || a_i == 0) {
            revert OutOfBoundsX(a_i);
        }

        uint256 b_i = reserveY_ * 1e36 / (mean_ * liquidity);
        if (b_i >= 1 ether || b_i == 0) {
            revert OutOfBoundsY(b_i);
        }

        int256 a = Gaussian.ppf(toInt(a_i));
        int256 b = Gaussian.ppf(toInt(b_i));
        int256 c = toInt(computeWidthSqrtTau(width_, tau_));
        return a + b + c;
    }

    /// @notice Uses state and approximate spot price to approximate the total value of the pool in terms of Y token.
    /// @dev Do not rely on this for onchain calculations.
    function totalValue() public view returns (uint256) {
        return approxSpotPrice().mulWadDown(reserveX) + reserveY;
    }

    /// @notice Uses state to approximate the spot price of the X token in terms of the Y token.
    /// @dev Do not rely on this for onchain calculations.
    function approxSpotPrice() public view returns (uint256) {
        return computeSpotPrice(reserveX, totalLiquidity, strike, sigma, lastTau());
    }

    /// @dev price(x) = μe^(Φ^-1(1 - x/L)σ√τ - 1/2σ^2τ)
    /// @notice
    /// * As lim_x->0, price(x) = +infinity for all `τ` > 0 and `σ` > 0.
    /// * As lim_x->1, price(x) = 0 for all `τ` > 0 and `σ` > 0.
    /// * If `τ` or `σ` is zero, price is equal to strike.
    function computeSpotPrice(uint256 reserveX_, uint256 totalLiquidity_, uint256 mean_, uint256 width_, uint256 tau_)
        public
        pure
        returns (uint256)
    {
        if (reserveX_ >= totalLiquidity_) return 0; // Terminal price
        if (reserveX_ <= 0) return type(uint256).max; // Terminal price
        // Φ^-1(1 - x/L)
        int256 a = Gaussian.ppf(int256(1 ether - reserveX_.divWadDown(totalLiquidity_)));
        // σ√τ
        int256 b = toInt(computeWidthSqrtTau(width_, tau_));
        // 1/2σ^2τ
        int256 c = toInt(0.5 ether * width_ * width_ * tau_ / (1e18 ** 3));
        // Φ^-1(1 - x/L)σ√τ - 1/2σ^2τ
        int256 exp = (a * b / 1 ether - c).expWad();
        // μe^(Φ^-1(1 - x/L)σ√τ - 1/2σ^2τ)
        return mean_.mulWadUp(uint256(exp));
    }

    function computeLnSDivK(uint256 S, uint256 mean_) public pure returns (int256) {
        return int256(S.divWadDown(mean_)).lnWad();
    }

    /// @dev Computes σ√τ given `width_` σ and `tau` τ.
    function computeWidthSqrtTau(uint256 width_, uint256 tau_) internal pure returns (uint256) {
        uint256 sqrtTau = FixedPointMathLib.sqrt(tau_) * 1e9; // 1e9 is the precision of the square root function
        return width_.mulWadUp(sqrtTau);
    }

    /// @dev Converts seconds (units of block.timestamp) into years in WAD units.
    function computeTauWadYears(uint256 tauSeconds) public pure returns (uint256) {
        return tauSeconds.mulDivDown(1e18, 365 days);
    }

    /// @dev ~y = LKΦ(Φ⁻¹(1-x/L) - σ√τ)
    function computeY(uint256 reserveX_, uint256 liquidity, uint256 mean_, uint256 width_, uint256 tau_)
        public
        pure
        returns (uint256)
    {
        if (tau_ == 0) liquidity * mean_ * (1 ether - reserveX_ / liquidity) / (1e18 ** 2);

        int256 a = Gaussian.ppf(toInt(1 ether - reserveX_.divWadDown(liquidity)));
        int256 b = toInt(computeWidthSqrtTau(width_, tau_));
        int256 c = Gaussian.cdf(a - b);

        return liquidity * mean_ * toUint(c) / (1e18 ** 2);
    }

    /// @dev ~x = L(1 - Φ(Φ⁻¹(y/(LK)) + σ√τ))
    function computeX(uint256 reserveY_, uint256 liquidity, uint256 mean_, uint256 width_, uint256 tau_)
        public
        pure
        returns (uint256)
    {
        if (tau_ == 0) return liquidity * (1 ether - reserveY_ * 1e18 * 1e18 / (liquidity * mean_));

        int256 a = Gaussian.ppf(toInt(reserveY_ * 1e18 * 1e18 / (liquidity * mean_)));
        int256 b = toInt(computeWidthSqrtTau(width_, tau_));
        int256 c = Gaussian.cdf(a + b);

        return liquidity * (1 ether - toUint(c)) / 1e18;
    }

    /// @dev ~L = x / (1 - Φ(Φ⁻¹(y/(LK)) + σ√τ))
    function computeL(uint256 reserveX_, uint256 liquidity, uint256 width_, uint256 prevTau, uint256 newTau)
        public
        pure
        returns (uint256)
    {
        int256 a = Gaussian.ppf(toInt(reserveX_ * 1 ether / liquidity));
        int256 c = Gaussian.cdf(
            (
                (a * toInt(computeWidthSqrtTau(width_, prevTau)) / 1 ether)
                    + toInt(width_ * width_ * prevTau / (2 ether * 1 ether))
                    + toInt(width_ * width_ * newTau / (2 ether * 1 ether))
            ) * 1 ether / toInt(computeWidthSqrtTau(width_, newTau))
        );

        return reserveX_ * 1 ether / toUint(1 ether - c);
    }

    function computeLGivenX(
        uint256 reserveX_,
        uint256 prevL,
        uint256 mean_,
        uint256 width_,
        uint256 prevTau,
        uint256 newTau
    ) public pure returns (uint256) {
        int256 lnSDivK = computeLnSDivK(computeSpotPrice(reserveX_, prevL, mean_, width_, newTau), mean_);
        uint256 sigmaSqrtTau = computeWidthSqrtTau(width_, newTau);
        uint256 halfSigmaSquaredTau = width_.mulWadDown(width_).mulWadDown(0.5 ether).mulWadDown(newTau);
        int256 d1 = 1 ether * (lnSDivK + int256(halfSigmaSquaredTau)) / int256(sigmaSqrtTau);
        uint256 cdf = uint256(Gaussian.cdf(d1));

        return reserveX_.divWadUp(1 ether - cdf);
    }

    /// @dev x is independent variable, y and L are dependent variables.
    function findX(bytes memory data, uint256 x) internal pure returns (int256) {
        (uint256 reserveY_, uint256 liquidity, uint256 mean_, uint256 width_, uint256 tau_, int256 invariant) =
            abi.decode(data, (uint256, uint256, uint256, uint256, uint256, int256));

        return RMM.computeTradingFunction(x, reserveY_, liquidity, mean_, width_, tau_) - invariant;
    }

    /// @dev y is independent variable, x and L are dependent variables.
    function findY(bytes memory data, uint256 y) internal pure returns (int256) {
        (uint256 reserveX_, uint256 liquidity, uint256 mean_, uint256 width_, uint256 tau_, int256 invariant) =
            abi.decode(data, (uint256, uint256, uint256, uint256, uint256, int256));

        return RMM.computeTradingFunction(reserveX_, y, liquidity, mean_, width_, tau_) - invariant;
    }

    /// @dev L is independent variable, x and y are dependent variables.
    function findL(bytes memory data, uint256 liquidity) internal pure returns (int256) {
        (uint256 reserveX_, uint256 reserveY_, uint256 mean_, uint256 width_, uint256 tau_, int256 invariant) =
            abi.decode(data, (uint256, uint256, uint256, uint256, uint256, int256));

        return RMM.computeTradingFunction(reserveX_, reserveY_, liquidity, mean_, width_, tau_) - invariant;
    }

    /// todo: figure out what happens when result of trading function is negative or positive.
    function solveX(uint256 reserveY_, uint256 liquidity, int256 invariant, uint256 mean_, uint256 width_, uint256 tau_)
        public
        view
        returns (uint256 reserveX_)
    {
        // All the arguments that don't change.
        bytes memory args = abi.encode(reserveY_, liquidity, mean_, width_, tau_, invariant);

        // Establish initial bounds
        uint256 upper = computeX(reserveY_, liquidity, mean_, width_, tau_);
        uint256 lower = upper;
        int256 result = findX(args, upper);
        console2.log("result X", result);
        if (result < 0) {
            upper = upper.mulDivUp(1001, 1000);
            upper = upper > liquidity ? liquidity : upper;
            //result = findX(args, upper);
        } else {
            lower = lower.mulDivDown(999, 1000);
            lower = lower > liquidity ? liquidity : lower;
            //result = findX(args, lower);
        }

        // Run bisection using the bounds to find the root of the function `findX`.
        (uint256 rootInput, uint256 upperInput,) = bisection(args, lower, upper, 1, MAX_ITER, findX);

        // `upperInput` should be positive, so if root is < 0 return upperInput instead
        if (findX(args, rootInput) == 0) {
            reserveX_ = rootInput;
        } else {
            reserveX_ = upperInput;
        }
    }

    function solveY(uint256 reserveX_, uint256 liquidity, int256 invariant, uint256 mean_, uint256 width_, uint256 tau_)
        public
        view
        returns (uint256 reserveY_)
    {
        // All the arguments that don't change.
        bytes memory args = abi.encode(reserveX_, liquidity, mean_, width_, tau_, invariant);

        // Establish initial bounds
        uint256 upper = computeY(reserveX_, liquidity, mean_, width_, tau_);
        uint256 lower = upper;
        int256 result = findY(args, upper);
        console2.log("result Y", result);
        if (result < 0) {
            upper = upper.mulDivUp(1e15 + 1, 1e15);
            //result = findY(args, upper);
        } else {
            lower = lower.mulDivDown(1e15 - 1, 1e15);
            //result = findY(args, lower);
        }
        reserveY_ = upper;
        /*
        // Run bisection using the bounds to find the root of the function `findY`.
        (uint256 rootInput, uint256 upperInput,) = bisection(args, lower, upper, 1, 1, findY);

        // `upperInput` should be positive, so if root is < 0 return upperInput instead
        if (findY(args, rootInput) == 0) {
            reserveY_ = rootInput;
        } else {
            reserveY_ = upperInput;
        }
        */
    }

    function solveL(
        uint256 initialLiquidity,
        uint256 reserveX_,
        uint256 reserveY_,
        int256 invariant,
        uint256 mean_,
        uint256 width_,
        uint256 prevTau,
        uint256 tau_
    ) public view returns (uint256 liquidity_) {
        // All the arguments that don't change.
        bytes memory args = abi.encode(reserveX_, reserveY_, mean_, width_, tau_, invariant);

        // Establish initial bounds
        uint256 upper =
            initialLiquidity == 0 ? reserveX_ + 1 : computeL(reserveX_, initialLiquidity, width_, prevTau, tau_);
        uint256 lower = upper;
        int256 result = findL(args, lower);
        if (result < 0) {
            lower = lower.mulDivDown(1e8 - 1, 1e8);
            uint256 min =
                reserveX_ > reserveY_.divWadDown(mean_) ? reserveX_ + 1000 : reserveY_.divWadDown(mean_) + 1000;
            lower = lower < reserveX_ ? min : lower;
        } else {
            upper = upper.mulDivUp(1e8 + 1, 1e8);
        }
        liquidity_ = lower;

        /*
        // Run bisection using the bounds to find the root of the function `findL`.
        (uint256 rootInput,, uint256 lowerInput) = bisection(args, lower, upper, 1, 1, findL);

        // `upperInput` should be positive, so if root is < 0 return upperInput instead
        if (findL(args, rootInput) == 0) {
            liquidity_ = rootInput;
        } else {
            liquidity_ = lowerInput;
        }
        console2.log("terminal L", liquidity_);
        */
    }
}

// 256 iter:  0.732899032202380204
// 8 iter:    0.732436599229286431
// 3 iter:    0.705792051020313330

uint256 constant MAX_ITER = 10;

/// @dev Thrown when the lower bound is greater than the upper bound.
error BisectionLib_InvalidBounds(uint256 lower, uint256 upper);
/// @dev Thrown when the result of the function `fx` for each input, `upper` and `lower`, is the same sign.
error BisectionLib_RootOutsideBounds(int256 lowerResult, int256 upperResult);

/**
 * @notice
 * The function `fx` must be continuous and monotonic.
 *
 * @dev
 * Bisection is a method of finding the root of a function.
 * The root is the point where the function crosses the x-axis.
 *
 * @param args The arguments to pass to the function `fx`.
 * @param lower The lower bound of the root to find.
 * @param upper The upper bound of the root to find.
 * @param epsilon The maximum distance between the lower and upper results.
 * @param maxIterations The maximum amount of loop iterations to run.
 * @param fx The function to find the root of.
 * @return root The root of the function `fx`.
 */
function bisection(
    bytes memory args,
    uint256 lower,
    uint256 upper,
    uint256 epsilon,
    uint256 maxIterations,
    function (bytes memory,uint256) pure returns (int256) fx
) view returns (uint256 root, uint256 upperInput, uint256 lowerInput) {
    if (lower > upper) revert BisectionLib_InvalidBounds(lower, upper);
    // Passes the lower and upper bounds to the optimized function.
    // Reverts if the optimized function `fx` returns both negative or both positive values.
    // This means that the root is not between the bounds.
    // The root is between the bounds if the product of the two values is negative.
    int256 lowerOutput = fx(args, lower);
    int256 upperOutput = fx(args, upper);
    if (lowerOutput * upperOutput > 0) {
        revert BisectionLib_RootOutsideBounds(lowerOutput, upperOutput);
    }

    // Distance is optimized to equal `epsilon`.
    uint256 distance = upper - lower;
    upperInput = upper;
    lowerInput = lower;

    uint256 iterations; // Bounds the amount of loops to `maxIterations`.
    do {
        // Bisection uses the point between the lower and upper bounds.
        // The `distance` is halved each iteration.
        root = (lowerInput + upperInput) / 2;

        int256 output = fx(args, root);
        console2.log("fx output", output);

        // If the product is negative, the root is between the lower and root.
        // If the product is positive, the root is between the root and upper.
        if (output * lowerOutput <= 0) {
            upperInput = root; // Set the new upper bound to the root because we know its between the lower and root.
        } else {
            lowerInput = root; // Set the new lower bound to the root because we know its between the upper and root.
            lowerOutput = output; // root function value becomes new lower output value
        }

        // Update the distance with the new bounds.
        distance = upper - lower;

        unchecked {
            iterations++; // Increment the iterator.
        }
        console2.log("iterations", iterations);
    } while (distance > epsilon && iterations < maxIterations);
}

// utils

/// @dev Converts a WAD amount to a native DECIMAL amount, rounding down.
function downscaleDown(uint256 amount, uint256 scalar) pure returns (uint256) {
    return FixedPointMathLib.divWadDown(amount, scalar);
}

/// @dev Converts a WAD amount to a native DECIMAL amount, rounding up.
function downscaleUp(uint256 amount, uint256 scalar) pure returns (uint256) {
    return FixedPointMathLib.divWadUp(amount, scalar);
}

/// @dev Casts a positived signed integer to an unsigned integer, reverting if `x` is negative.
function toUint(int256 x) pure returns (uint256) {
    require(x >= 0, "toUint: negative");
    return uint256(x);
}

/// @dev Casts an unsigned integer to a signed integer, reverting if `x` is too large.
function toInt(uint256 x) pure returns (int256) {
    // Safe cast below because `type(int256).max` is positive.
    require(x <= uint256(type(int256).max), "toInt: overflow");
    return int256(x);
}

/// @dev Sums an unsigned integer with a signed integer, reverting if the result overflows.
function sum(uint256 a, int256 b) pure returns (uint256) {
    if (b < 0) {
        require(a >= uint256(-b), "sum: underflow");
        return a - uint256(-b);
    } else {
        require(a + uint256(b) >= a, "sum: overflow");
        return a + uint256(b);
    }
}
