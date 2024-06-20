// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "../src/lib/RmmLib.sol";
import "./BisectionLib.sol";

import { RMM, IPYieldToken, PYIndex, PYIndexLib, PoolPreCompute } from "../src/RMM.sol";
import { SignedWadMathLib } from "./SignedWadMathLib.sol";

using SignedWadMathLib for int256;

struct RmmParams {
    uint256 sigma;
    uint256 tau;
    uint256 K;
    uint256 rX;
    uint256 rY;
    uint256 L;
    uint256 fee;
}

int256 constant I_ONE = int256(1 ether);
int256 constant I_TWO = int256(2 ether);
int256 constant I_HALF = int256(0.5 ether);

contract RmmArbitrage {
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;

    using PYIndexLib for IPYieldToken;
    using PYIndexLib for PYIndex;

    function fetchPoolParams(address rmm_, PYIndex index) public view returns (RmmParams memory) {
        RMM rmm = RMM(payable(rmm_));
        PoolPreCompute memory comp = rmm.preparePoolPreCompute(index, block.timestamp);

        return RmmParams({
            fee: rmm.fee(),
            sigma: rmm.sigma(),
            tau: comp.tau_,
            K: comp.strike_,
            rX: comp.reserveInAsset,
            rY: rmm.reserveY(),
            L: rmm.totalLiquidity()
        });
    }

    function calculateDiffLower(
        address rmm,
        uint256 S,
        uint256 v,
        PYIndex index
    ) public view returns (int256) {
        RmmParams memory params = fetchPoolParams(rmm, index);
        return diffLower(int256(S), int256(v), params);
    }

    function calculateDiffRaise(
        address rmm,
        uint256 S,
        uint256 v,
        PYIndex index
    ) public view returns (int256) {
        RmmParams memory params = fetchPoolParams(rmm, index);
        return diffRaise(int256(S), int256(v), params);
    }

    function computeOptimalArbLowerPrice(
        address rmm,
        uint256 S,
        uint256 vUpper,
        PYIndex index
    ) public view returns (uint256) {
        RmmParams memory params = fetchPoolParams(rmm, index);
        return computeOptimalLower(
            int256(S), vUpper, params
        );
    }

    function computeOptimalArbRaisePrice(
        address rmm,
        uint256 S,
        uint256 vUpper,
        PYIndex index
    ) public view returns (uint256) {
        RmmParams memory params = fetchPoolParams(rmm, index);
        return computeOptimalRaise(
            int256(S), vUpper, params
        );
    }

    function getDyGivenS(
        address rmm,
        uint256 S,
        PYIndex index
    ) public view returns (int256) {
        RmmParams memory params = fetchPoolParams(rmm, index);
        int256 dy = computeDy(int256(S), params);
        return dy;
    }

    function getDxGivenS(
        address rmm,
        uint256 S,
        PYIndex index
    ) public view returns (int256) {
        RmmParams memory params = fetchPoolParams(rmm, index);
        return computeDx(int256(S), params);
    }

    function findRootLower(
        bytes memory data,
        uint256 v
    ) internal pure returns (int256) {
        (uint256 S, RmmParams memory params) =
            abi.decode(data, (uint256, RmmParams));
        return diffLower({
            S: int256(S),
            v: int256(v),
            params: params
        });
    }

    function findRootRaise(
        bytes memory data,
        uint256 v
    ) internal pure returns (int256) {
        (uint256 S, RmmParams memory params) =
            abi.decode(data, (uint256, RmmParams));
        return diffRaise({
            S: int256(S),
            v: int256(v),
            params: params
        });
    }

    struct DiffLowerStruct {
        int256 ierfcResult;
        int256 K;
        int256 sigma;
        int256 tau;
        int256 gamma;
        int256 rX;
        int256 L;
        int256 v;
        int256 S;
        int256 sqrtTwo;
    }

    function createDiffLowerStruct(
        int256 S,
        int256 gamma,
        int256 v,
        RmmParams memory params
    ) internal pure returns (DiffLowerStruct memory) {
        int256 a = I_TWO.wadMul(v + int256(params.rX));
        int256 b = int256(params.L) + v - v.wadMul(gamma);
        int256 ierfcRes = Gaussian.ierfc(a.wadDiv(b));

        int256 sqrtTwo = int256(FixedPointMathLib.sqrt(2 ether) * 1e9);

        DiffLowerStruct memory ints = DiffLowerStruct({
            ierfcResult: ierfcRes,
            K: int256(params.K),
            sigma: int256(params.sigma),
            tau: int256(params.tau),
            gamma: gamma,
            rX: int256(params.rX),
            L: int256(params.L),
            v: v,
            S: S,
            sqrtTwo: sqrtTwo
        });

        return ints;
    }

    function computeLowerA(DiffLowerStruct memory params)
        internal
        pure
        returns (int256)
    {
        int256 firstExp = -(params.sigma.wadMul(params.sigma).wadMul(params.tau).wadDiv(I_TWO));
        int256 secondExp =
            params.sqrtTwo.wadMul(params.sigma).wadMul(int256(FixedPointMathLib.sqrt(uint256(params.tau)))).wadMul(params.ierfcResult);

        int256 first = FixedPointMathLib.expWad(firstExp + secondExp);
        int256 second = params.K.wadMul(
            params.L + params.rX.wadMul(-I_ONE + params.gamma)
        );

        int256 firstNum = first.wadMul(second);
        int256 firstDen = params.L + params.v - params.v.wadMul(params.gamma);
        return firstNum.wadDiv(firstDen);
    }

    function computeLowerB(DiffLowerStruct memory params)
        internal
        pure
        returns (int256)
    {
        int256 a = I_HALF.wadMul(params.K).wadMul(-I_ONE + params.gamma);
        int256 b = params.sigma.wadMul(int256(FixedPointMathLib.sqrt(uint256(params.tau)))).wadDiv(params.sqrtTwo);
        return a.wadMul(Gaussian.erfc(b - params.ierfcResult));
    }

    function diffLower(
        int256 S,
        int256 v,
        RmmParams memory params
    ) internal pure returns (int256) {
        int256 gamma = I_ONE - int256(params.fee);
        DiffLowerStruct memory ints =
            createDiffLowerStruct(S, gamma, v, params);
        int256 a = computeLowerA(ints);
        int256 b = computeLowerB(ints);

        return -ints.S + a + b;
    }

    struct DiffRaiseStruct {
        int256 ierfcResult;
        int256 K;
        int256 sigma;
        int256 tau;
        int256 gamma;
        int256 rY;
        int256 L;
        int256 v;
        int256 S;
        int256 sqrtTwo;
    }

    function createDiffRaiseStruct(
        int256 S,
        int256 gamma,
        int256 v,
        RmmParams memory params
    ) internal pure returns (DiffRaiseStruct memory) {
        int256 a = I_TWO.wadMul(v + int256(params.rY));
        int256 b = int256(params.L) + v - v.wadMul(gamma);
        int256 ierfcRes = Gaussian.ierfc(a.wadDiv(b));

        int256 sqrtTwo = int256(FixedPointMathLib.sqrt(2 ether) * 1e9);

        DiffRaiseStruct memory ints = DiffRaiseStruct({
            ierfcResult: ierfcRes,
            K: int256(params.K),
            sigma: int256(params.sigma),
            tau: int256(params.tau),
            gamma: gamma,
            rY: int256(params.rY),
            L: int256(params.L),
            S: S,
            v: v,
            sqrtTwo: sqrtTwo
        });

        return ints;
    }

    function computeRaiseA(DiffRaiseStruct memory params)
        internal
        pure
        returns (int256)
    {
        int256 firstExp = -(params.sigma.wadMul(params.sigma).wadMul(params.tau).wadDiv(I_TWO));
        int256 secondExp =
            params.sqrtTwo.wadMul(params.sigma).wadMul(int256(FixedPointMathLib.sqrt(uint256(params.tau)) * 1e9)).wadMul(params.ierfcResult);
        int256 first = FixedPointMathLib.expWad(firstExp + secondExp);
        int256 second = params.S.wadMul(
            params.K.wadMul(params.L)
                + params.rY.wadMul(-I_ONE + params.gamma)
        );

        int256 num = first.wadMul(second);
        int256 den = params.K.wadMul(
            params.K.wadMul(params.L) + params.v
                - params.v.wadMul(params.gamma)
        );
        return num.wadDiv(den);
    }

    function computeRaiseB(DiffRaiseStruct memory params)
        internal
        pure
        returns (int256)
    {
        int256 first = params.S.wadMul(-I_ONE + params.gamma);
        int256 erfcFirst = params.sigma.wadDiv(params.sqrtTwo);
        int256 num = first.wadMul(Gaussian.erfc(erfcFirst - params.ierfcResult));
        int256 den = I_TWO.wadMul(params.K);
        return num.wadDiv(den);
    }

    function diffRaise(
        int256 S,
        int256 v,
        RmmParams memory params
    ) internal pure returns (int256) {
        int256 gamma = I_ONE - int256(params.fee);
        DiffRaiseStruct memory ints =
            createDiffRaiseStruct(S, gamma, v, params);
        int256 a = computeRaiseA(ints);
        int256 b = computeRaiseB(ints);

        return -I_ONE + a + b;
    }

    function computeDy(
        int256 S,
        RmmParams memory params
    ) internal pure returns (int256 dy) {
        int256 gamma = I_ONE - int256(params.fee);
        int256 mean = int256(params.K);
        int256 width = int256(params.sigma);

        int256 lnSDivMean = computeLnSDivK(uint256(S), params.K);
        int256 a = lnSDivMean.wadDiv(width) - width.wadDiv(I_TWO);
        int256 cdfA = Gaussian.cdf(a);

        int256 delta = int256(params.L).wadMul(mean).wadMul(cdfA);
        dy = delta - int256(params.rY);
    }

    function computeDx(
        int256 S,
        RmmParams memory params
    ) internal pure returns (int256 dx) {
        int256 gamma = I_ONE - int256(params.fee);
        int256 width = int256(params.sigma);

        int256 lnSDivMean = computeLnSDivK(uint256(S), params.K);
        int256 a = Gaussian.cdf(lnSDivMean.wadDiv(width) + width.wadDiv(I_TWO));

        int256 delta = int256(params.L).wadMul(I_ONE - a);
        dx = delta - int256(params.rX);
    }

    function computeOptimalLower(
        int256 S,
        uint256 vUpper,
        RmmParams memory params
    ) internal pure returns (uint256 v) {
        uint256 upper = vUpper;
        uint256 lower = 1;
        int256 lowerBoundOutput = diffLower(S, int256(lower), params);
        if (lowerBoundOutput < 0) {
            return 0;
        }
        (v,,) = bisection(
            abi.encode(S, params),
            lower,
            upper,
            uint256(1),
            256,
            findRootLower
        );
    }

    function computeOptimalRaise(
        int256 S,
        uint256 vUpper,
        RmmParams memory params
    ) internal pure returns (uint256 v) {
        uint256 upper = vUpper;
        uint256 lower = 1;
        int256 lowerBoundOutput = diffRaise(S, int256(lower), params);
        if (lowerBoundOutput < 0) {
            return 0;
        }
        (v,,) = bisection(
            abi.encode(S, params),
            lower,
            upper,
            uint256(1),
            256,
            findRootRaise
        );
    }
}