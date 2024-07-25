// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {IStandardizedYield} from "pendle/interfaces/IStandardizedYield.sol";
import {PYIndexLib, PYIndex} from "pendle/core/StandardizedYield/PYIndex.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";
import "forge-std/console2.sol";

import {RMM, IPYieldToken, Gaussian, computeTradingFunction} from "./RMM.sol";
import {InvalidTokenIn, InsufficientSYMinted} from "./lib/RmmErrors.sol";

contract LiquidityManager {
    using PYIndexLib for PYIndex;
    using PYIndexLib for IPYieldToken;
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    function mintSY(address SY, address receiver, address tokenIn, uint256 amountTokenToDeposit, uint256 minSharesOut)
        public
        payable
        returns (uint256 amountOut)
    {
        IStandardizedYield sy = IStandardizedYield(SY);
        if (!sy.isValidTokenIn(tokenIn)) revert InvalidTokenIn(tokenIn);

        if (msg.value > 0 && sy.isValidTokenIn(address(0))) {
            // SY minted check is done in this function instead of relying on the SY contract's deposit().
            amountOut += sy.deposit{value: msg.value}(address(this), address(0), msg.value, 0);
        }

        if (tokenIn != address(0)) {
            ERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountTokenToDeposit);
            amountOut += sy.deposit(receiver, tokenIn, amountTokenToDeposit, 0);
        }

        if (amountOut < minSharesOut) {
            revert InsufficientSYMinted(amountOut, minSharesOut);
        }
    }

    struct AllocateArgs {
        address rmm;
        uint256 amountIn;
        uint256 minOut;
        uint256 minLiquidityDelta;
        uint256 initialGuess;
        uint256 epsilon;
    }

    function allocateFromSy(AllocateArgs calldata args) external returns (uint256 liquidity) {
        RMM rmm = RMM(payable(args.rmm));

        ERC20 sy = ERC20(address(rmm.SY()));
        ERC20 pt = ERC20(address(rmm.PT()));

        PYIndex index = IPYieldToken(rmm.YT()).newIndex();
        uint256 rX = rmm.reserveX();
        uint256 rY = rmm.reserveY();

        // validate swap approximation
        (uint256 syToSwap,) = computeSyToPtToAddLiquidity(
            ComputeArgs({
                rmm: args.rmm,
                rX: rX,
                rY: rY,
                index: index,
                maxIn: args.amountIn,
                blockTime: block.timestamp,
                initialGuess: args.initialGuess,
                epsilon: args.epsilon
            })
        );

        // transfer all sy in
        sy.safeTransferFrom(msg.sender, address(this), args.amountIn);
        sy.approve(address(args.rmm), args.amountIn);

        // swap syToSwap for pt
        (uint256 ptOut,) = rmm.swapExactSyForPt(syToSwap, args.minOut, address(this));

        pt.approve(address(args.rmm), ptOut);
        liquidity = ptOut > sy.balanceOf(address(this)) ? rmm.allocate(true, sy.balanceOf(address(this)), args.minLiquidityDelta, msg.sender) : rmm.allocate(false, ptOut, args.minLiquidityDelta, msg.sender);
    }

    function allocateFromPt(AllocateArgs calldata args) external returns (uint256 liquidity) {
        RMM rmm = RMM(payable(args.rmm));
        ERC20 sy = ERC20(address(rmm.SY()));
        ERC20 pt = ERC20(address(rmm.PT()));

        PYIndex index = IPYieldToken(rmm.YT()).newIndex();
        uint256 rX = rmm.reserveX();
        uint256 rY = rmm.reserveY();

        // validate swap approximation
        (uint256 ptToSwap,) = computePtToSyToAddLiquidity(
            ComputeArgs({
                rmm: args.rmm,
                rX: rX,
                rY: rY,
                index: index,
                maxIn: args.amountIn,
                blockTime: block.timestamp,
                initialGuess: args.initialGuess,
                epsilon: args.epsilon
            })
        );

        // transfer all pt in
        pt.safeTransferFrom(msg.sender, address(this), args.amountIn);
        pt.approve(address(rmm), args.amountIn);

        // swap ptToSwap for sy
        (uint256 syOut,) = rmm.swapExactPtForSy(ptToSwap, args.minOut, address(this));

        sy.approve(address(rmm), syOut);
        liquidity = rmm.allocate(true, syOut, args.minLiquidityDelta, msg.sender);
    }

    struct ComputeArgs {
        address rmm;
        uint256 rX;
        uint256 rY;
        PYIndex index;
        uint256 maxIn;
        uint256 blockTime;
        uint256 initialGuess;
        uint256 epsilon;
    }

    function computePtToSyToAddLiquidity(ComputeArgs memory args) public view returns (uint256 guess, uint256 syOut) {
        uint256 min = 0;
        uint256 max = args.maxIn - 1;
        for (uint256 iter = 0; iter < 256; ++iter) {
            guess = args.initialGuess > 0 && iter == 0 ? args.initialGuess : (min + max) / 2;
            (,, syOut,,) = RMM(payable(args.rmm)).prepareSwapPtIn(guess, args.blockTime, args.index);

            uint256 syNumerator = syOut * (args.rX - syOut);
            uint256 ptNumerator = (args.maxIn - guess) * (args.rY + guess);

            if (isAApproxB(syNumerator, ptNumerator, args.epsilon)) {
                return (guess, syOut);
            }

            if (syNumerator <= ptNumerator) {
                min = guess + 1;
            } else {
                max = guess - 1;
            }
        }
    }

    function computeSyToPtToAddLiquidity(ComputeArgs memory args) public view returns (uint256 guess, uint256 ptOut) {
        RMM rmm = RMM(payable(args.rmm));
        uint256 min = 0;
        uint256 max = args.maxIn - 1;
        for (uint256 iter = 0; iter < 256; ++iter) {
            guess = args.initialGuess > 0 && iter == 0 ? args.initialGuess : (min + max) / 2;
            (,, ptOut,,) = rmm.prepareSwapSyIn(guess, args.blockTime, args.index);

            uint256 syNumerator = (args.maxIn - guess) * (args.rX + guess);
            uint256 ptNumerator = ptOut * (args.rY - ptOut);

            if (isAApproxB(syNumerator, ptNumerator, args.epsilon)) {
                return (guess, ptOut);
            }

            if (ptNumerator <= syNumerator) {
                min = guess + 1;
            } else {
                max = guess - 1;
            }
        }
    }

    function isAApproxB(uint256 a, uint256 b, uint256 eps) internal pure returns (bool) {
        return b.mulWadDown(1 ether - eps) <= a && a <= b.mulWadDown(1 ether + eps);
    }

    function calcMaxPtOut(
        uint256 reserveX_,
        uint256 reserveY_,
        uint256 totalLiquidity_,
        uint256 strike_,
        uint256 sigma_,
        uint256 tau_
    ) internal pure returns (uint256) {
        int256 currentTF = computeTradingFunction(reserveX_, reserveY_, totalLiquidity_, strike_, sigma_, tau_);
        
        uint256 maxProportion = uint256(int256(1e18) - currentTF) * 1e18 / (2 * 1e18);
        
        uint256 maxPtOut = reserveY_ * maxProportion / 1e18;
        
        return (maxPtOut * 999) / 1000;
    }

}
