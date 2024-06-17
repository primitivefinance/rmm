// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {RMM, IPYieldToken} from "./RMM.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IStandardizedYield} from "pendle/interfaces/IStandardizedYield.sol";
import {PYIndexLib, PYIndex} from "pendle/core/StandardizedYield/PYIndex.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import "./lib/RmmErrors.sol";

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

    function _mintSYFromNativeAndToken(
        address SY,
        address receiver,
        address tokenIn,
        uint256 amountTokenIn,
        uint256 minSyMinted
    ) internal returns (uint256 amountSyOut) {
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

    struct AllocateFromSyArgs {
        address rmm;
        uint256 amountSy;
        uint256 minPtOut;
        uint256 minLiquidityDelta;
        uint256 initialGuess;
        uint256 epsilon;
    }

    function allocateFromSy(AllocateFromSyArgs calldata args) external returns (uint256 liquidity) {
        RMM rmm = RMM(payable(args.rmm));

        ERC20 sy = ERC20(address(rmm.SY()));
        ERC20 pt = ERC20(address(rmm.PT()));

        PYIndex index = IPYieldToken(rmm.YT()).newIndex();
        uint256 rX = rmm.reserveX();
        uint256 rY = rmm.reserveY();

        // validate swap approximation
        (uint256 syToSwap,) = computeSyToPtToAddLiquidity(
            SyToPtArgs({
                rmm: args.rmm,
                rX: rX,
                rY: rY,
                index: index,
                maxSy: args.amountSy,
                blockTime: block.timestamp,
                initialGuess: args.initialGuess,
                epsilon: args.epsilon
            })
        );

        // transfer all sy in
        sy.transferFrom(msg.sender, address(this), args.amountSy);
        sy.approve(address(args.rmm), args.amountSy);

        // swap syToSwap for pt
        rmm.swapExactSyForPt(syToSwap, args.minPtOut, address(this));
        uint256 syBal = sy.balanceOf(address(this));
        uint256 ptBal = pt.balanceOf(address(this));

        pt.approve(address(args.rmm), ptBal);
        liquidity = rmm.allocate(syBal, ptBal, args.minLiquidityDelta, msg.sender);
    }

    struct AllocateFromPtArgs {
        address rmm;
        uint256 amountPt;
        uint256 minSyOut;
        uint256 minLiquidityDelta;
        uint256 initialGuess;
        uint256 epsilon;
    }

    function allocateFromPt(AllocateFromPtArgs calldata args) external returns (uint256 liquidity) {
        RMM rmm = RMM(payable(args.rmm));
        ERC20 sy = ERC20(address(rmm.SY()));
        ERC20 pt = ERC20(address(rmm.PT()));

        PYIndex index = IPYieldToken(rmm.YT()).newIndex();
        uint256 rX = rmm.reserveX();
        uint256 rY = rmm.reserveY();

        // validate swap approximation
        (uint256 ptToSwap,) = computePtToSyToAddLiquidity(
            PtToSyArgs(args.rmm, rX, rY, index, args.amountPt, block.timestamp, args.initialGuess, args.epsilon)
        );

        // transfer all pt in
        pt.transferFrom(msg.sender, address(this), args.amountPt);
        pt.approve(address(rmm), args.amountPt);

        // swap ptToSwap for sy
        rmm.swapExactPtForSy(ptToSwap, args.minSyOut, address(this));
        uint256 syBal = sy.balanceOf(address(this));
        uint256 ptBal = pt.balanceOf(address(this));

        sy.approve(address(rmm), syBal);
        liquidity = rmm.allocate(syBal, ptBal, args.minLiquidityDelta, msg.sender);
    }

    struct PtToSyArgs {
        address rmm;
        uint256 rX;
        uint256 rY;
        PYIndex index;
        uint256 maxPt;
        uint256 blockTime;
        uint256 initialGuess;
        uint256 epsilon;
    }

    function computePtToSyToAddLiquidity(PtToSyArgs memory args) public view returns (uint256, uint256) {
        uint256 min = 0;
        uint256 max = args.maxPt - 1;
        for (uint256 iter = 0; iter < 256; ++iter) {
            uint256 guess = args.initialGuess > 0 && iter == 0 ? args.initialGuess : (min + max) / 2;
            (,, uint256 syOut,,) = RMM(payable(args.rmm)).prepareSwapPtIn(guess, args.blockTime, args.index);

            uint256 syNumerator = syOut * (args.rX + syOut);
            uint256 ptNumerator = (args.maxPt - guess) * (args.rY - guess);

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

    struct SyToPtArgs {
        address rmm;
        uint256 rX;
        uint256 rY;
        PYIndex index;
        uint256 maxSy;
        uint256 blockTime;
        uint256 initialGuess;
        uint256 epsilon;
    }

    function computeSyToPtToAddLiquidity(SyToPtArgs memory args) public view returns (uint256 guess, uint256 ptOut) {
        RMM rmm = RMM(payable(args.rmm));
        uint256 min = 0;
        uint256 max = args.maxSy - 1;
        for (uint256 iter = 0; iter < 256; ++iter) {
            guess = args.initialGuess > 0 && iter == 0 ? args.initialGuess : (min + max) / 2;
            (,, ptOut,,) = rmm.prepareSwapSyIn(guess, args.blockTime, args.index);

            uint256 syNumerator = (args.maxSy - guess) * (args.rX + guess);
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
}
