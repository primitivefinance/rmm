// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Gaussian} from "solstat/Gaussian.sol";
import {console2} from "forge-std/console2.sol";
import {PYIndexLib, PYIndex} from "pendle/core/StandardizedYield/PYIndex.sol";
import {IPPrincipalToken} from "pendle/interfaces/IPPrincipalToken.sol";
import {IStandardizedYield} from "pendle/interfaces/IStandardizedYield.sol";
import {IPYieldToken} from "pendle/interfaces/IPYieldToken.sol";

interface Token {
    function decimals() external view returns (uint8);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface ICallback {
    function callback(address token, uint256 amountNative, bytes calldata data) external returns (bool);
}

struct PoolPreCompute {
    uint256 reserveInAsset;
    uint256 strike_;
    uint256 tau_;
}

contract RMM is ERC20 {
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;
    using PYIndexLib for IPYieldToken;
    using PYIndexLib for PYIndex;

    /// @dev Thrown when a `balanceOf` call fails or returns unexpected data.
    error BalanceError();
    /// @dev Thrown when a payment to this contract is insufficient.
    error InsufficientPayment(address token, uint256 actual, uint256 expected);
    /// @dev Thrown when a mint does not output enough liquidity.
    error InsufficientLiquidityOut(uint256 deltaX, uint256 deltaY, uint256 minLiquidity, uint256 liquidity);
    /// @dev Thrown when a swap does not output enough tokens.
    error InsufficientOutput(uint256 amountIn, uint256 minAmountOut, uint256 amountOut);
    /// @dev Thrown when an allocate would reduce the liquidity.
    error InvalidAllocate(uint256 deltaX, uint256 deltaY, uint256 currLiquidity, uint256 nextLiquidity);
    /// @dev Thrown on `init` when a token has invalid decimals.
    error InvalidDecimals(address token, uint256 decimals);
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
    event Allocate(address indexed caller, address indexed to, uint256 deltaX, uint256 deltaY, uint256 deltaLiquidity);
    /// @dev Emitted on deallocates.
    event Deallocate(
        address indexed caller, address indexed to, uint256 deltaX, uint256 deltaY, uint256 deltaLiquidity
    );

    int256 public constant INIT_UPPER_BOUND = 30;
    uint256 public constant BURNT_LIQUIDITY = 1000;
    address public immutable WETH;

    IPPrincipalToken public PT; // slot 6
    IStandardizedYield public SY; // slot 7
    IPYieldToken public YT; // slot 8

    uint256 public reserveX; // slot 9
    uint256 public reserveY; // slot 10
    uint256 public totalLiquidity; // slot 11

    uint256 public strike; // slot 12
    uint256 public sigma; // slot 13
    uint256 public fee; // slot 14
    uint256 public maturity; // slot 15

    uint256 public initTimestamp; // slot 16
    uint256 public lastTimestamp; // slot 17

    address public curator; // slot 18
    uint256 public lock_ = 1; // slot 19

    uint256 public lastImpliedPrice; // slot 20

    modifier lock() {
        if (lock_ != 1) revert Reentrancy();
        lock_ = 0;
        _;
        lock_ = 1;
    }

    /// @dev Applies updates to the trading function and validates the adjustment.
    modifier evolve(PYIndex index) {
        int256 initial = tradingFunction(index);
        _;
        int256 terminal = tradingFunction(index);

        if (abs(terminal) > 10) {
            revert OutOfRange(initial, terminal);
        }
    }

    constructor(address weth_, string memory name_, string memory symbol_) ERC20(name_, symbol_, 18) {
        WETH = weth_;
    }

    receive() external payable {}

    function prepareInit(uint256 priceX, uint256 totalAsset, uint256 strike_, uint256 sigma_, uint256 maturity_)
        public
        view
        returns (uint256 totalLiquidity_, uint256 amountY)
    {
        uint256 tau_ = computeTauWadYears(maturity_ - block.timestamp);
        PoolPreCompute memory comp = PoolPreCompute({reserveInAsset: totalAsset, strike_: strike_, tau_: tau_});
        uint256 initialLiquidity =
            computeLGivenX({reserveX_: totalAsset, S: priceX, strike_: strike_, sigma_: sigma_, tau_: tau_});
        amountY =
            computeY({reserveX_: totalAsset, liquidity: initialLiquidity, strike_: strike_, sigma_: sigma_, tau_: tau_});
        totalLiquidity_ = solveL(comp, initialLiquidity, amountY, sigma_);
    }

    /// @dev Initializes the pool with an initial price, amount of `x` tokens, and parameters.
    function init(
        address PT_,
        uint256 priceX,
        uint256 amountX,
        uint256 strike_,
        uint256 sigma_,
        uint256 fee_,
        address curator_
    ) external lock {
        PT = IPPrincipalToken(PT_);
        SY = IStandardizedYield(PT.SY());
        YT = IPYieldToken(PT.YT());

        PYIndex index = YT.newIndex();
        uint256 totalAsset = index.syToAsset(amountX);

        strike = strike_;
        sigma = sigma_;
        fee = fee_;
        maturity = PT.expiry();
        initTimestamp = block.timestamp;
        curator = curator_;

        (uint256 totalLiquidity_, uint256 amountY) = prepareInit(priceX, totalAsset, strike_, sigma_, maturity);

        _mint(msg.sender, totalLiquidity_ - BURNT_LIQUIDITY);
        _mint(address(0), BURNT_LIQUIDITY);
        _adjust(toInt(amountX), toInt(amountY), toInt(totalLiquidity_), strike_, index);
        _debit(address(SY), reserveX, "");
        _debit(address(PT), reserveY, "");

        emit Init(
            msg.sender,
            address(PT_),
            address(SY),
            amountX,
            amountY,
            totalLiquidity_,
            strike_,
            sigma_,
            fee_,
            maturity,
            curator_
        );
    }

    /// @dev Allows an arbitrary adjustment to the reserves and liquidity, if it is valid.
    function adjust(int256 deltaX, int256 deltaY, int256 deltaLiquidity) external lock {
        uint256 feeAmount;
        PYIndex index = YT.newIndex();

        // Deallocating
        if (deltaLiquidity < 0) {
            if (deltaY > 0 && deltaX <= 0) {
                feeAmount = toUint(deltaY).mulWadUp(fee);
            } else if (deltaX > 0 && deltaY <= 0) {
                feeAmount = toUint(deltaX).mulWadUp(fee);
            }
        }

        _adjust(deltaX, deltaY, deltaLiquidity, strike, index);
        if (deltaX < 0) _credit(address(SY), msg.sender, uint256(-deltaX));
        if (deltaY < 0) _credit(address(PT), msg.sender, uint256(-deltaY));
        if (deltaX > 0) _debit(address(SY), uint256(deltaX), "");
        if (deltaY > 0) _debit(address(PT), uint256(deltaY), "");
    }

    /// @dev Applies an adjustment to the reserves, liquidity, and last timestamp before validating it with the trading function.
    function _adjust(int256 deltaX, int256 deltaY, int256 deltaLiquidity, uint256 strike_, PYIndex index)
        internal
        evolve(index)
    {
        lastTimestamp = block.timestamp;
        reserveX = sum(reserveX, deltaX);
        reserveY = sum(reserveY, deltaY);
        totalLiquidity = sum(totalLiquidity, deltaLiquidity);
        strike = strike_;
        lastImpliedPrice = approxSpotPrice(index.syToAsset(reserveX));
    }

    function prepareSwap(address tokenIn, address tokenOut, uint256 amountIn, uint256 timestamp, PYIndex index)
        public
        view
        returns (uint256 amountInWad, uint256 amountOutWad, uint256 amountOut, int256 deltaLiquidity, uint256 strike_)
    {
        if (tokenIn != address(SY) && tokenIn != address(PT)) revert("Invalid tokenIn");
        if (tokenOut != address(SY) && tokenOut != address(PT)) revert("Invalid tokenOut");

        bool xIn = tokenIn == address(SY);
        amountInWad = xIn ? upscale(amountIn, scalar(address(SY))) : upscale(amountIn, scalar(address(PT)));
        uint256 feeAmount = amountInWad.mulWadUp(fee);
        PoolPreCompute memory comp = preparePoolPreCompute(index, timestamp);
        uint256 nextLiquidity;
        uint256 nextReserve;
        if (xIn) {
            comp.reserveInAsset += index.syToAsset(feeAmount);
            nextLiquidity = solveL(comp, totalLiquidity, reserveY, sigma);
            comp.reserveInAsset -= index.syToAsset(feeAmount);
            console2.log("next L", nextLiquidity);
            nextReserve = solveY(
                comp.reserveInAsset + index.syToAsset(amountInWad), nextLiquidity, comp.strike_, sigma, comp.tau_
            );
            console2.log("next reserve", nextReserve);
            amountOutWad = reserveY - nextReserve;
        } else {
            nextLiquidity = solveL(comp, totalLiquidity, reserveY + feeAmount, sigma);
            nextReserve = solveX(reserveY + amountInWad, nextLiquidity, comp.strike_, sigma, comp.tau_);
            amountOutWad = reserveX - index.assetToSy(nextReserve);
        }
        strike_ = comp.strike_;
        deltaLiquidity = toInt(nextLiquidity) - toInt(totalLiquidity);
        amountOut = downscaleDown(amountOutWad, xIn ? scalar(address(PT)) : scalar(address(SY)));
    }

    /// @dev Swaps tokenX to tokenY, sending at least `minAmountOut` tokenY to `to`.
    function swapX(uint256 amountIn, uint256 minAmountOut, address to, bytes calldata data)
        external
        lock
        returns (uint256 amountOut, int256 deltaLiquidity)
    {
        uint256 amountInWad;
        uint256 amountOutWad;
        uint256 strike_;
        PYIndex index = YT.newIndex();
        (amountInWad, amountOutWad, amountOut, deltaLiquidity, strike_) =
            prepareSwap(address(SY), address(PT), amountIn, block.timestamp, index);

        if (amountOut < minAmountOut) {
            revert InsufficientOutput(amountInWad, minAmountOut, amountOut);
        }

        _adjust(toInt(amountInWad), -toInt(amountOutWad), deltaLiquidity, strike_, index);
        (uint256 creditNative) = _credit(address(PT), to, amountOutWad);
        (uint256 debitNative) = _debit(address(SY), amountInWad, data);

        emit Swap(msg.sender, to, address(SY), address(PT), debitNative, creditNative, deltaLiquidity);
    }

    function swapY(uint256 amountIn, uint256 minAmountOut, address to, bytes calldata data)
        external
        lock
        returns (uint256 amountOut, int256 deltaLiquidity)
    {
        uint256 amountInWad;
        uint256 amountOutWad;
        uint256 strike_;
        PYIndex index = YT.newIndex();
        (amountInWad, amountOutWad, amountOut, deltaLiquidity, strike_) =
            prepareSwap(address(PT), address(SY), amountIn, block.timestamp, index);

        if (amountOut < minAmountOut) {
            revert InsufficientOutput(amountInWad, minAmountOut, amountOut);
        }

        _adjust(-toInt(amountOutWad), toInt(amountInWad), deltaLiquidity, strike_, index);
        (uint256 creditNative) = _credit(address(PT), to, amountOutWad);
        (uint256 debitNative) = _debit(address(SY), amountInWad, data);

        emit Swap(msg.sender, to, address(PT), address(SY), debitNative, creditNative, deltaLiquidity);
    }

    function prepareAllocate(uint256 deltaX, uint256 deltaY, PYIndex index)
        public
        view
        returns (uint256 deltaXWad, uint256 deltaYWad, uint256 deltaLiquidity, uint256 lptMinted)
    {
        deltaXWad = upscale(index.syToAsset(deltaX), scalar(address(SY)));
        deltaYWad = upscale(deltaY, scalar(address(PT)));

        PoolPreCompute memory comp =
            PoolPreCompute({reserveInAsset: index.syToAsset(reserveX + deltaXWad), strike_: strike, tau_: lastTau()});
        uint256 nextLiquidity = solveL(
            comp,
            computeLGivenX(
                comp.reserveInAsset + deltaXWad, approxSpotPrice(comp.reserveInAsset), strike, sigma, lastTau()
            ),
            reserveY + deltaYWad,
            sigma
        );
        if (nextLiquidity < totalLiquidity) {
            revert InvalidAllocate(deltaX, deltaY, totalLiquidity, nextLiquidity);
        }
        deltaLiquidity = nextLiquidity - totalLiquidity;
        lptMinted = deltaLiquidity.mulDivDown(totalSupply, nextLiquidity);
    }

    /// todo: should allocates be executed on the stale curve? I dont think the curve should be updated in allocates.
    function allocate(uint256 deltaX, uint256 deltaY, uint256 minLiquidityOut, address to)
        external
        lock
        returns (uint256 deltaLiquidity)
    {
        uint256 deltaXWad;
        uint256 deltaYWad;
        uint256 lptMinted;
        PYIndex index = YT.newIndex();
        (deltaXWad, deltaYWad, deltaLiquidity, lptMinted) = prepareAllocate(deltaX, deltaY, index);
        if (deltaLiquidity < minLiquidityOut) {
            revert InsufficientLiquidityOut(deltaX, deltaY, minLiquidityOut, deltaLiquidity);
        }

        _mint(to, lptMinted);
        _adjust(toInt(deltaXWad), toInt(deltaYWad), toInt(deltaLiquidity), strike, index);

        (uint256 debitNativeX) = _debit(address(SY), deltaXWad, "");
        (uint256 debitNativeY) = _debit(address(PT), deltaYWad, "");

        emit Allocate(msg.sender, to, debitNativeX, debitNativeY, deltaLiquidity);
    }

    function prepareDeallocate(uint256 deltaLiquidity)
        public
        view
        returns (uint256 deltaXWad, uint256 deltaYWad, uint256 lptBurned)
    {
        uint256 liquidity = totalLiquidity;
        deltaXWad = deltaLiquidity.mulDivDown(reserveX, liquidity);
        deltaYWad = deltaLiquidity.mulDivDown(reserveY, liquidity);
        lptBurned = deltaLiquidity.mulDivUp(totalSupply, liquidity);
    }

    /// @dev Burns `deltaLiquidity` * `totalSupply` / `totalLiquidity` rounded up
    /// and returns `deltaLiquidity` * `reserveX` / `totalLiquidity`
    ///           + `deltaLiquidity` * `reserveY` / `totalLiquidity` of ERC-20 tokens.
    function deallocate(uint256 deltaLiquidity, uint256 minDeltaXOut, uint256 minDeltaYOut, address to)
        external
        lock
        returns (uint256 deltaX, uint256 deltaY)
    {
        (uint256 deltaXWad, uint256 deltaYWad, uint256 lptBurned) = prepareDeallocate(deltaLiquidity);
        (deltaX, deltaY) =
            (downscaleDown(deltaXWad, scalar(address(SY))), downscaleDown(deltaYWad, scalar(address(PT))));

        if (minDeltaXOut > deltaX) {
            revert InsufficientOutput(deltaLiquidity, minDeltaXOut, deltaX);
        }
        if (minDeltaYOut > deltaY) {
            revert InsufficientOutput(deltaLiquidity, minDeltaYOut, deltaY);
        }

        _burn(msg.sender, lptBurned); // uses state totalLiquidity
        _adjust(-toInt(deltaXWad), -toInt(deltaYWad), -toInt(deltaLiquidity), strike, YT.newIndex());

        (uint256 creditNativeX) = _credit(address(SY), to, deltaXWad);
        (uint256 creditNativeY) = _credit(address(PT), to, deltaYWad);

        emit Deallocate(msg.sender, to, creditNativeX, creditNativeY, deltaLiquidity);
    }

    // payments

    /// @dev Handles the request of payment for a given token.
    /// @param data Avoid the callback by passing empty data. Trigger the callback and pass the data through otherwise.
    function _debit(address token, uint256 amountWad, bytes memory data) internal returns (uint256 paymentNative) {
        uint256 balanceNative = _balanceNative(token);
        uint256 amountNative = downscaleDown(amountWad, scalar(token));

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
        uint256 amountNative = downscaleDown(amount, scalar(token));

        // Send the tokens to the recipient.
        if (!Token(token).transfer(to, amountNative)) {
            revert PaymentFailed(token, address(this), to, amountNative);
        }

        paymentNative = balanceNative - _balanceNative(token);
        if (paymentNative < amountNative) {
            revert InsufficientPayment(token, paymentNative, amountNative);
        }
    }

    function preparePoolPreCompute(PYIndex index, uint256 blockTime) internal view returns (PoolPreCompute memory) {
        uint256 tau_ = futureTau(blockTime);
        uint256 totalAsset = index.syToAsset(reserveX);
        uint256 strike_ = computeKGivenLastPrice(totalAsset, totalLiquidity, sigma, tau_);
        return PoolPreCompute(totalAsset, strike_, tau_);
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

    function futureTau(uint256 timestamp) public view returns (uint256) {
        if (maturity < timestamp) {
            return 0;
        }

        return computeTauWadYears(maturity - timestamp);
    }

    /// @dev Computes the trading function result using the current state.
    function tradingFunction(PYIndex index) public view returns (int256) {
        if (totalLiquidity == 0) return 0; // Not initialized.
        uint256 totalAsset = index.syToAsset(reserveX);
        return computeTradingFunction(totalAsset, reserveY, totalLiquidity, strike, sigma, lastTau());
    }

    /// @dev k = Φ⁻¹(x/L) + Φ⁻¹(y/μL)  + σ√τ
    function computeTradingFunction(
        uint256 reserveX_,
        uint256 reserveY_,
        uint256 liquidity,
        uint256 strike_,
        uint256 sigma_,
        uint256 tau_
    ) public pure returns (int256) {
        uint256 a_i = reserveX_ * 1e18 / liquidity;

        uint256 b_i = reserveY_ * 1e36 / (strike_ * liquidity);

        int256 a = Gaussian.ppf(toInt(a_i));
        int256 b = Gaussian.ppf(toInt(b_i));
        int256 c = tau_ != 0 ? toInt(computeSigmaSqrtTau(sigma_, tau_)) : int256(0);
        return a + b + c;
    }

    /// @notice Uses state and approximate spot price to approximate the total value of the pool in terms of Y token.
    /// @dev Do not rely on this for onchain calculations.
    // function totalValue(total) public view returns (uint256) {
    //     return approxSpotPrice().mulWadDown(reserveX) + reserveY;
    // }

    /// @notice Uses state to approximate the spot price of the X token in terms of the Y token.
    /// @dev Do not rely on this for onchain calculations.
    function approxSpotPrice(uint256 totalAsset) public view returns (uint256) {
        return computeSpotPrice(totalAsset, totalLiquidity, strike, sigma, lastTau());
    }

    /// @dev price(x) = μe^(Φ^-1(1 - x/L)σ√τ - 1/2σ^2τ)
    /// @notice
    /// * As lim_x->0, price(x) = +infinity for all `τ` > 0 and `σ` > 0.
    /// * As lim_x->1, price(x) = 0 for all `τ` > 0 and `σ` > 0.
    /// * If `τ` or `σ` is zero, price is equal to strike.
    function computeSpotPrice(uint256 reserveX_, uint256 totalLiquidity_, uint256 strike_, uint256 sigma_, uint256 tau_)
        public
        pure
        returns (uint256)
    {
        // Φ^-1(1 - x/L)
        int256 a = Gaussian.ppf(int256(1 ether - reserveX_.divWadDown(totalLiquidity_)));
        // σ√τ
        int256 b = toInt(computeSigmaSqrtTau(sigma_, tau_));
        // 1/2σ^2τ
        int256 c = toInt(0.5 ether * sigma_ * sigma_ * tau_ / (1e18 ** 3));
        // Φ^-1(1 - x/L)σ√τ - 1/2σ^2τ
        int256 exp = (a * b / 1 ether - c).expWad();
        // μe^(Φ^-1(1 - x/L)σ√τ - 1/2σ^2τ)
        return strike_.mulWadUp(uint256(exp));
    }

    function computeLnSDivK(uint256 S, uint256 strike_) public pure returns (int256) {
        return int256(S.divWadDown(strike_)).lnWad();
    }

    /// @dev Computes σ√τ given `sigma_` σ and `tau` τ.
    function computeSigmaSqrtTau(uint256 sigma_, uint256 tau_) internal pure returns (uint256) {
        uint256 sqrtTau = FixedPointMathLib.sqrt(tau_) * 1e9; // 1e9 is the precision of the square root function
        return sigma_.mulWadUp(sqrtTau);
    }

    /// @dev Converts seconds (units of block.timestamp) into years in WAD units.
    function computeTauWadYears(uint256 tauSeconds) public pure returns (uint256) {
        return tauSeconds.mulDivDown(1e18, 365 days);
    }

    function computeKGivenLastPrice(uint256 reserveX_, uint256 liquidity, uint256 sigma_, uint256 tau_)
        public
        view
        returns (uint256)
    {
        uint256 a = sigma_.mulWadDown(sigma_).mulWadDown(tau_).mulWadDown(0.5 ether);
        // $$\Phi^{-1} (1 - \frac{x}{L})$$
        int256 b = Gaussian.ppf(int256(1 ether - reserveX_.divWadDown(liquidity)));
        int256 exp = (b * (int256(computeSigmaSqrtTau(sigma_, tau_))) / 1e18 - int256(a)).expWad();

        return uint256(int256(lastImpliedPrice).powWad(int256(tau_))).divWadDown(uint256(exp));
    }

    /// @dev ~y = LKΦ(Φ⁻¹(1-x/L) - σ√τ)
    function computeY(uint256 reserveX_, uint256 liquidity, uint256 strike_, uint256 sigma_, uint256 tau_)
        public
        pure
        returns (uint256)
    {
        int256 a = Gaussian.ppf(toInt(1 ether - reserveX_.divWadDown(liquidity)));
        int256 b = tau_ != 0 ? toInt(computeSigmaSqrtTau(sigma_, tau_)) : int256(0);
        int256 c = Gaussian.cdf(a - b);

        return liquidity * strike_ * toUint(c) / (1e18 ** 2);
    }

    /// @dev ~x = L(1 - Φ(Φ⁻¹(y/(LK)) + σ√τ))
    function computeX(uint256 reserveY_, uint256 liquidity, uint256 strike_, uint256 sigma_, uint256 tau_)
        public
        pure
        returns (uint256)
    {
        int256 a = Gaussian.ppf(toInt(reserveY_ * 1e36 / (liquidity * strike_)));
        int256 b = tau_ != 0 ? toInt(computeSigmaSqrtTau(sigma_, tau_)) : int256(0);
        int256 c = Gaussian.cdf(a + b);

        return liquidity * (1 ether - toUint(c)) / 1e18;
    }

    /// @dev ~L = x / (1 - Φ(Φ⁻¹(y/(LK)) + σ√τ))
    function computeL(uint256 reserveX_, uint256 liquidity, uint256 sigma_, uint256 prevTau, uint256 newTau)
        public
        pure
        returns (uint256)
    {
        int256 a = Gaussian.ppf(toInt(reserveX_ * 1 ether / liquidity));
        int256 c = Gaussian.cdf(
            (
                (a * toInt(computeSigmaSqrtTau(sigma_, prevTau)) / 1 ether)
                    + toInt(sigma_ * sigma_ * prevTau / (2 ether * 1 ether))
                    + toInt(sigma_ * sigma_ * newTau / (2 ether * 1 ether))
            ) * 1 ether / toInt(computeSigmaSqrtTau(sigma_, newTau))
        );

        return reserveX_ * 1 ether / toUint(1 ether - c);
    }

    function computeLGivenYK(
        uint256 reserveX_,
        uint256 reserveY_,
        uint256 liquidity,
        uint256 strike_,
        uint256 sigma_,
        uint256 newTau
    ) public pure returns (uint256) {
        int256 a = Gaussian.ppf(toInt(reserveY_ * 1e36 / (liquidity * strike_)));
        int256 b = newTau != 0 ? toInt(computeSigmaSqrtTau(sigma_, newTau)) : int256(0);
        int256 c = Gaussian.cdf(a + b);

        return reserveX_ * 1 ether / toUint(1 ether - c);
    }

    function computeLGivenX(uint256 reserveX_, uint256 S, uint256 strike_, uint256 sigma_, uint256 tau_)
        public
        pure
        returns (uint256)
    {
        int256 lnSDivK = computeLnSDivK(S, strike_);
        uint256 sigmaSqrtTau = computeSigmaSqrtTau(sigma_, tau_);
        uint256 halfSigmaSquaredTau = sigma_.mulWadDown(sigma_).mulWadDown(0.5 ether).mulWadDown(tau_);
        int256 d1 = 1 ether * (lnSDivK + int256(halfSigmaSquaredTau)) / int256(sigmaSqrtTau);
        uint256 cdf = uint256(Gaussian.cdf(d1));

        return reserveX_.divWadUp(1 ether - cdf);
    }

    /// @dev x is independent variable, y and L are dependent variables.
    function findX(bytes memory data, uint256 x) internal pure returns (int256) {
        (uint256 reserveY_, uint256 liquidity, uint256 strike_, uint256 sigma_, uint256 tau_) =
            abi.decode(data, (uint256, uint256, uint256, uint256, uint256));

        return RMM.computeTradingFunction(x, reserveY_, liquidity, strike_, sigma_, tau_);
    }

    /// @dev y is independent variable, x and L are dependent variables.
    function findY(bytes memory data, uint256 y) internal pure returns (int256) {
        (uint256 reserveX_, uint256 liquidity, uint256 strike_, uint256 sigma_, uint256 tau_) =
            abi.decode(data, (uint256, uint256, uint256, uint256, uint256));

        return RMM.computeTradingFunction(reserveX_, y, liquidity, strike_, sigma_, tau_);
    }

    /// @dev L is independent variable, x and y are dependent variables.
    function findL(bytes memory data, uint256 liquidity) internal pure returns (int256) {
        (uint256 reserveX_, uint256 reserveY_, uint256 strike_, uint256 sigma_, uint256 tau_) =
            abi.decode(data, (uint256, uint256, uint256, uint256, uint256));

        return RMM.computeTradingFunction(reserveX_, reserveY_, liquidity, strike_, sigma_, tau_);
    }

    /// todo: figure out what happens when result of trading function is negative or positive.
    function solveX(uint256 reserveY_, uint256 liquidity, uint256 strike_, uint256 sigma_, uint256 tau_)
        public
        pure
        returns (uint256 reserveX_)
    {
        bytes memory args = abi.encode(reserveY_, liquidity, strike_, sigma_, tau_);
        uint256 initialGuess = computeX(reserveY_, liquidity, strike_, sigma_, tau_);
        console2.log("initial x guess", initialGuess);
        // at maturity the `initialGuess` will == L therefore we must reduce it by 1 wei
        reserveX_ = findRootNewX(args, tau_ != 0 ? initialGuess : initialGuess - 1, 20, 10);
    }

    function solveY(uint256 reserveX_, uint256 liquidity, uint256 strike_, uint256 sigma_, uint256 tau_)
        public
        pure
        returns (uint256 reserveY_)
    {
        bytes memory args = abi.encode(reserveX_, liquidity, strike_, sigma_, tau_);
        uint256 initialGuess = computeY(reserveX_, liquidity, strike_, sigma_, tau_);
        // at maturity the `initialGuess` will == LK (K == WAD, K*L == L) therefore we must reduce it by 1 wei
        console2.log("initialGuess y", initialGuess);
        reserveY_ = findRootNewY(args, tau_ != 0 ? initialGuess : initialGuess - 1, 20, 10);
    }

    function solveL(PoolPreCompute memory comp, uint256 initialLiquidity, uint256 reserveY_, uint256 sigma_)
        public
        pure
        returns (uint256 liquidity_)
    {
        console2.log("prev liquidity", initialLiquidity);
        bytes memory args = abi.encode(comp.reserveInAsset, reserveY_, comp.strike_, sigma_, comp.tau_);
        uint256 initialGuess =
            computeLGivenYK(comp.reserveInAsset, reserveY_, initialLiquidity, comp.strike_, sigma_, comp.tau_);
        console2.log("initial guess", initialGuess);
        liquidity_ = findRootNewLiquidity(args, initialGuess, 20, 10);
        console2.log("new liquidity", liquidity_);
    }

    function findRootNewLiquidity(bytes memory args, uint256 initialGuess, uint256 maxIterations, uint256 tolerance)
        public
        pure
        returns (uint256 L)
    {
        L = initialGuess;
        int256 L_next;
        for (uint256 i = 0; i < maxIterations; i++) {
            console2.log("iters L", i);
            int256 dfx = computeTfDL(args, L);
            int256 fx = findL(args, L);

            if (dfx == 0) {
                // Handle division by zero
                break;
            }
            L_next = int256(L) - fx * 1e18 / dfx;

            if (abs(int256(L) - L_next) <= int256(tolerance) || abs(fx) <= int256(tolerance)) {
                L = uint256(L_next);
                console2.log("terminal L", L);
                break;
            }

            L = uint256(L_next);
        }
    }

    function findRootNewX(bytes memory args, uint256 initialGuess, uint256 maxIterations, uint256 tolerance)
        public
        pure
        returns (uint256 reserveX_)
    {
        reserveX_ = initialGuess;
        int256 reserveX_next;
        for (uint256 i = 0; i < maxIterations; i++) {
            console2.log("iters x", i);
            int256 dfx = computeTfDReserveX(args, reserveX_);
            int256 fx = findX(args, reserveX_);

            if (dfx == 0) {
                // Handle division by zero
                break;
            }

            reserveX_next = int256(reserveX_) - fx * 1e18 / dfx;

            if (abs(int256(reserveX_) - reserveX_next) <= int256(tolerance) || abs(fx) <= int256(tolerance)) {
                reserveX_ = uint256(reserveX_next);
                console2.log("terminal reserveX_", reserveX_);
                break;
            }

            reserveX_ = uint256(reserveX_next);
        }
    }

    function findRootNewY(bytes memory args, uint256 initialGuess, uint256 maxIterations, uint256 tolerance)
        public
        pure
        returns (uint256 reserveY_)
    {
        reserveY_ = initialGuess;
        int256 reserveY_next;
        for (uint256 i = 0; i < maxIterations; i++) {
            console2.log("iters y", i);
            int256 fx = findY(args, reserveY_);
            int256 dfx = computeTfDReserveY(args, reserveY_);

            if (dfx == 0) {
                // Handle division by zero
                break;
            }

            reserveY_next = int256(reserveY_) - fx * 1e18 / dfx;

            if (abs(int256(reserveY_) - reserveY_next) <= int256(tolerance) || abs(fx) <= int256(tolerance)) {
                reserveY_ = uint256(reserveY_next);
                console2.log("terminal reserveY_", reserveY_);
                break;
            }

            reserveY_ = uint256(reserveY_next);
        }
    }

    function computeTfDL(bytes memory args, uint256 L) public pure returns (int256) {
        (uint256 rX, uint256 rY, uint256 K,,) = abi.decode(args, (uint256, uint256, uint256, uint256, uint256));
        int256 x = int256(rX);
        int256 y = int256(rY);
        int256 mu = int256(K);
        int256 L_squared = int256(L.mulWadDown(L));

        int256 a = Gaussian.ppf(int256(rX.divWadUp(L)));
        int256 b = Gaussian.ppf(int256(rY.divWadUp(L.mulWadUp(K))));

        int256 pdf_a = Gaussian.pdf(a);
        int256 pdf_b = Gaussian.pdf(b);

        int256 term1 = x * 1 ether / (int256(L_squared) * (pdf_a) / 1 ether);

        int256 term2a = mu * int256(L_squared) / 1 ether;
        int256 term2b = term2a * pdf_b / 1 ether;
        int256 term2 = y * 1 ether / term2b;

        return -term1 - term2;
    }

    function computeTfDReserveX(bytes memory args, uint256 rX) public pure returns (int256) {
        (, uint256 L,,,) = abi.decode(args, (uint256, uint256, uint256, uint256, uint256));
        int256 a = Gaussian.ppf(toInt(rX * 1e18 / L));
        int256 pdf_a = Gaussian.pdf(a);
        int256 result = 1e36 / (int256(L) * pdf_a / 1e18);
        return result;
    }

    function computeTfDReserveY(bytes memory args, uint256 rY) public pure returns (int256) {
        (, uint256 L, uint256 K,,) = abi.decode(args, (uint256, uint256, uint256, uint256, uint256));
        int256 KL = int256(K * L / 1e18);
        int256 a = Gaussian.ppf(int256(rY) * 1e18 / KL);
        int256 pdf_a = Gaussian.pdf(a);
        int256 result = 1e36 / (KL * pdf_a / 1e18);
        return result;
    }
}
// utils

/// @dev Computes the scalar to multiply to convert between WAD and native units.
function scalar(address token) view returns (uint256) {
    uint256 decimals = Token(token).decimals();
    uint256 difference = 18 - decimals;
    return FixedPointMathLib.WAD * 10 ** difference;
}

/// @dev Converts native decimal amount to WAD amount, rounding down.
function upscale(uint256 amount, uint256 scalingFactor) pure returns (uint256) {
    return FixedPointMathLib.mulWadDown(amount, scalingFactor);
}

/// @dev Converts a WAD amount to a native DECIMAL amount, rounding down.
function downscaleDown(uint256 amount, uint256 scalar_) pure returns (uint256) {
    return FixedPointMathLib.divWadDown(amount, scalar_);
}

/// @dev Converts a WAD amount to a native DECIMAL amount, rounding up.
function downscaleUp(uint256 amount, uint256 scalar_) pure returns (uint256) {
    return FixedPointMathLib.divWadUp(amount, scalar_);
}

/// @dev Casts a positived signed integer to an unsigned integer, reverting if `x` is negative.
function toUint(int256 x) pure returns (uint256) {
    require(x >= 0, "toUint: negative");
    return uint256(x);
}

function abs(int256 x) pure returns (int256) {
    if (x < 0) {
        return -x;
    } else {
        return x;
    }
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
