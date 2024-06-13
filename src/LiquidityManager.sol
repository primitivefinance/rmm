// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import { RMM, IPYieldToken } from "./RMM.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IStandardizedYield} from "pendle/interfaces/IStandardizedYield.sol";
import {PYIndexLib, PYIndex} from "pendle/core/StandardizedYield/PYIndex.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import "forge-std/console2.sol";

import "./lib/RmmErrors.sol";

interface IRMM {
    function SY() external view returns (address);
    function PT() external view returns (address);
    function YT() external view returns (address);
    function reserveX() external view returns (uint256);
    function reserveY() external view returns (uint256);
    function prepareAllocate(uint256 deltaX, uint256 deltaY, PYIndex index) external view returns (uint256 deltaXWad, uint256 deltaYWad, uint256 deltaLiquidity, uint256 lptMinted);
    function swapExactPtForSy(uint256 amountIn, uint256 minAmountOut, address to)
        external
        payable
        returns (uint256 amountOut, int256 deltaLiquidity);
    function swapExactSyForPt(uint256 amountIn, uint256 minAmountOut, address to)
        external
        returns (uint256 amountOut, int256 deltaLiquidity);
    function allocate(uint256 deltaX, uint256 deltaY, uint256 minLiquidityOut, address to)
        external
        returns (uint256 deltaLiquidity);
    function prepareSwapSyIn(uint256 amountIn, uint256 timestamp, PYIndex index)
        external
        view
        returns (uint256 amountInWad, uint256 amountOutWad, uint256 amountOut, int256 deltaLiquidity, uint256 strike_);
}

contract LiquidityManager {
    using PYIndexLib for PYIndex;
    using PYIndexLib for IPYieldToken;
    using FixedPointMathLib for uint256;

    function mintSY(address SY, address receiver, address tokenIn, uint256 amountTokenToDeposit, uint256 minSharesOut)
        public
        payable
        returns (uint256 amountOut)
    {
        return _mintSYFromNativeAndToken(SY, receiver, tokenIn, amountTokenToDeposit, minSharesOut);
    }

    function _mintSYFromNativeAndToken(address SY, address receiver, address tokenIn, uint256 amountTokenIn, uint256 minSyMinted)
        internal
        returns (uint256 amountSyOut)
    {
        IStandardizedYield sy = IStandardizedYield(SY);
        if (!sy.isValidTokenIn(tokenIn)) revert InvalidTokenIn(tokenIn);

        if (msg.value > 0 && sy.isValidTokenIn(address(0))) {
            // SY minted check is done in this function instead of relying on the SY contract's deposit().
            amountSyOut += sy.deposit{value: msg.value}(address(this), address(0), msg.value, 0);
        }

        if (tokenIn != address(0)) {
            ERC20(tokenIn).transferFrom(msg.sender, address(this), amountTokenIn);
            amountSyOut += sy.deposit(receiver, tokenIn, amountTokenIn, 0);
        }

        if (amountSyOut < minSyMinted) {
            revert InsufficientSYMinted(amountSyOut, minSyMinted);
        }
    }

    function allocateFromSy(IRMM rmm, uint256 amountSy, uint256 minPtOut, uint256 minLiquidityDelta, uint256 initialGuess, uint256 epsilon) external returns (uint256 liquidity) {
        ERC20 sy = ERC20(address(rmm.SY()));
        ERC20 pt = ERC20(address(rmm.PT()));

        PYIndex index = IPYieldToken(rmm.YT()).newIndex();
        uint256 rX = rmm.reserveX();
        uint256 rY = rmm.reserveY();

        // validate swap approximation
        (uint256 syToSwap,) = computeSyToPtToAddLiquidity(rmm, rX, rY, index, amountSy, block.timestamp, initialGuess, epsilon);

        // transfer all sy in
        sy.transferFrom(msg.sender, address(this), amountSy);
        sy.approve(address(rmm), type(uint256).max);

        // swap syToSwap for pt
        rmm.swapExactSyForPt(syToSwap, minPtOut, address(this));
        uint256 syBal = sy.balanceOf(address(this));
        uint256 ptBal = pt.balanceOf(address(this));
        console2.log("syBal", syBal);
        console2.log("ptBal", ptBal);

        pt.approve(address(rmm), ptBal);
        liquidity = rmm.allocate(syBal, ptBal, minLiquidityDelta, msg.sender);
    }

    function allocateFromPt(RMM rmm, uint256 amountPt, uint256 minSyOut, uint256 minLiquidityDelta, uint256 initialGuess, uint256 epsilon) external returns (uint256 liquidity) {
        ERC20 sy = ERC20(address(rmm.SY()));
        ERC20 pt = ERC20(address(rmm.PT()));

        PYIndex index = rmm.YT().newIndex();
        uint256 rX = rmm.reserveX();
        uint256 rY = rmm.reserveY();

        // validate swap approximation
        (uint256 ptToSwap,) = computePtToSyToAddLiquidity(rmm, rX, rY, index, amountPt, block.timestamp, initialGuess, epsilon);

        // transfer all pt in
        pt.transferFrom(msg.sender, address(this), amountPt);
        pt.approve(address(rmm), amountPt);

        // swap ptToSwap for sy
        rmm.swapExactPtForSy(ptToSwap, minSyOut, address(this));
        uint256 syBal = sy.balanceOf(address(this));
        uint256 ptBal = pt.balanceOf(address(this));

        sy.approve(address(rmm), syBal);
        liquidity = rmm.allocate(syBal, ptBal, minLiquidityDelta, msg.sender);
    }

    function computePtToSyToAddLiquidity(
        RMM rmm,
        uint256 rX,
        uint256 rY,
        PYIndex index,
        uint256 maxPt,
        uint256 blockTime,
        uint256 initialGuess,
        uint256 epsilon
    ) public view returns (uint256, uint256) {
        uint256 min = 0;
        uint256 max = maxPt - 1;
        for (uint256 iter = 0; iter < 256; ++iter) {
            uint256 guess = initialGuess > 0 && iter == 0 ? initialGuess : (min + max) / 2;
            (,, uint256 syOut,,) = rmm.prepareSwapPtIn(guess, blockTime, index);


            uint256 syNumerator = syOut * (rX + syOut);
            uint256 ptNumerator = (maxPt - guess) * (rY - guess);

            if (isAApproxB(syNumerator, ptNumerator, epsilon)) {
                return (guess, syOut);
            }

            if (syNumerator <= ptNumerator) {
                min = guess + 1;
            } else {
                max = guess - 1;
            }
        }
    }

    function computeSyToPtToAddLiquidity(
        IRMM rmm,
        uint256 rX,
        uint256 rY,
        PYIndex index,
        uint256 maxSy,
        uint256 blockTime,
        uint256 initialGuess,
        uint256 epsilon
    ) public view returns (uint256 guess, uint256 ptOut) {
        uint256 min = 0;
        uint256 max = maxSy - 1;
        for (uint256 iter = 0; iter < 256; ++iter) {
            guess = initialGuess > 0 && iter == 0 ? initialGuess : (min + max) / 2;
            (,, ptOut,,) = rmm.prepareSwapSyIn(guess, blockTime, index);

            uint256 syNumerator = (maxSy - guess) * (rX + guess);
            uint256 ptNumerator = ptOut * (rY - ptOut);

            if (isAApproxB(syNumerator, ptNumerator, epsilon)) {
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
}

