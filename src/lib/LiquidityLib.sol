// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

using FixedPointMathLib for uint256;
using FixedPointMathLib for int256;

function computeAllocationGivenX(bool add, uint256 amountX, uint256 rx, uint256 L)
    pure
    returns (uint256 nextRx, uint256 nextL)
{
    uint256 deltaL = amountX.mulDivDown(L, rx);
    nextRx = add ? rx + amountX : rx - amountX;
    nextL = add ? L + deltaL : L - deltaL;
}

function computeAllocationGivenY(bool add, uint256 amountY, uint256 ry, uint256 L)
    pure
    returns (uint256 nextRy, uint256 nextL)
{
    uint256 deltaL = amountY.mulDivDown(L, ry);
    nextRy = add ? ry + amountY : ry - amountY;
    nextL = add ? L + deltaL : L - deltaL;
}

function computeDeltaLGivenDeltaX(uint256 deltaX, uint256 liquidity, uint256 reserveX) pure returns (uint256 deltaL) {
    return liquidity.mulDivDown(deltaX, reserveX);
}

function computeDeltaLGivenDeltaY(uint256 deltaY, uint256 liquidity, uint256 reserveY) pure returns (uint256 deltaL) {
    return liquidity.mulDivDown(deltaY, reserveY);
}

function computeDeltaYGivenDeltaX(uint256 deltaX, uint256 reserveX, uint256 reserveY) pure returns (uint256 deltaY) {
    return reserveY.mulDivUp(deltaX, reserveX);
}

function computeDeltaXGivenDeltaY(uint256 deltaY, uint256 reserveX, uint256 reserveY) pure returns (uint256 deltaX) {
    return reserveX.mulDivUp(deltaY, reserveY);
}

function computeDeltaXGivenDeltaL(uint256 deltaL, uint256 liquidity, uint256 reserveX) pure returns (uint256 deltaX) {
    return reserveX.mulDivUp(deltaL, liquidity);
}

function computeDeltaYGivenDeltaL(uint256 deltaL, uint256 liquidity, uint256 reserveY) pure returns (uint256 deltaX) {
    return reserveY.mulDivUp(deltaL, liquidity);
}

function computeAllocationGivenDeltaX(uint256 deltaX, uint256 reserveX, uint256 reserveY, uint256 liquidity)
    pure
    returns (uint256 deltaY, uint256 deltaL)
{
    deltaY = computeDeltaYGivenDeltaX(deltaX, reserveX, reserveY);
    deltaL = computeDeltaLGivenDeltaX(deltaX, liquidity, reserveX);
}

function computeAllocationGivenDeltaY(uint256 deltaY, uint256 reserveX, uint256 reserveY, uint256 liquidity)
    pure
    returns (uint256 deltaX, uint256 deltaL)
{
    deltaX = computeDeltaXGivenDeltaY(deltaY, reserveX, reserveY);
    deltaL = computeDeltaLGivenDeltaY(deltaY, liquidity, reserveY);
}

function computeAllocationGivenDeltaL(uint256 deltaL, uint256 reserveX, uint256 reserveY, uint256 liquidity)
    pure
    returns (uint256 deltaX, uint256 deltaY)
{
    deltaX = computeDeltaXGivenDeltaL(deltaL, reserveX, liquidity);
    deltaY = computeDeltaYGivenDeltaL(deltaL, reserveY, liquidity);
}