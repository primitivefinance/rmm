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

interface SolverLike {
    function simulateSwap(
        uint256 poolId,
        bool swapXIn,
        uint256 amountIn
    )
        external
        view
        returns (
            bool valid,
            uint256 estimatedOut,
            uint256 estimatedPrice,
            bytes memory payload
        );
    function internalPrice(uint256 poolId) external view returns (uint256);
    function getReservesAndLiquidity(uint256 poolId)
        external
        view
        returns (uint256, uint256, uint256);
    function strategy() external view returns (address);
}

int256 constant I_ONE = int256(1 ether);
int256 constant I_TWO = int256(2 ether);
int256 constant I_HALF = int256(0.5 ether);

contract RmmArbitrage {
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;

    using PYIndexLib for IPYieldToken;
    using PYIndexLib for PYIndex;

    function fetchPoolParams(address rmm_) public returns (RmmParams memory) {
        RMM rmm = RMM(payable(rmm_));
        IPYieldToken YT = rmm.YT();
        PYIndex index = YT.newIndex();
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
        uint256 v
    ) public returns (int256) {
        RmmParams memory params = fetchPoolParams(rmm);
        return diffLower(int256(S), int256(params.rX), int256(params.L), int256(v), params);
    }

    function calculateDiffRaise(
        address rmm,
        uint256 S,
        uint256 v
    ) public returns (int256) {
        RmmParams memory params = fetchPoolParams(rmm);
        return diffRaise(int256(S), int256(params.rY), int256(params.L), int256(v), params);
    }

    function computeOptimalArbLowerPrice(
        address rmm,
        uint256 S,
        uint256 vUpper
    ) public returns (uint256) {
        RmmParams memory params = fetchPoolParams(rmm);
        return computeOptimalLower(
            int256(S), int256(params.rX), int256(params.L), vUpper, params
        );
    }

    function computeOptimalArbRaisePrice(
        address rmm,
        uint256 S,
        uint256 vUpper
    ) public returns (uint256) {
        RmmParams memory params = fetchPoolParams(rmm);
        return computeOptimalRaise(
            int256(S), int256(params.rY), int256(params.L), vUpper, params
        );
    }

    function getDyGivenS(
        address rmm,
        uint256 S
    ) public returns (int256) {
        RmmParams memory params = fetchPoolParams(rmm);
        int256 dy = computeDy(int256(S), int256(params.rY), int256(params.L), params);
        return dy;
    }

    function getDxGivenS(
        address rmm,
        uint256 S
    ) public returns (int256) {
        RmmParams memory params = fetchPoolParams(rmm);
        return computeDx(int256(S), int256(params.rX), int256(params.L), params);
    }

    function findRootLower(
        bytes memory data,
        uint256 v
    ) internal pure returns (int256) {
        (uint256 S, uint256 rX, uint256 L, RmmParams memory params) =
            abi.decode(data, (uint256, uint256, uint256, RmmParams));
        return diffLower({
            S: int256(S),
            rX: int256(rX),
            L: int256(L),
            v: int256(v),
            params: params
        });
    }

    function findRootRaise(
        bytes memory data,
        uint256 v
    ) internal pure returns (int256) {
        (uint256 S, uint256 rY, uint256 L, RmmParams memory params) =
            abi.decode(data, (uint256, uint256, uint256, RmmParams));
        return diffRaise({
            S: int256(S),
            rY: int256(rY),
            L: int256(L),
            v: int256(v),
            params: params
        });
    }

    struct DiffLowerStruct {
        int256 ierfcResult;
        int256 mean;
        int256 width;
        int256 gamma;
        int256 rX;
        int256 L;
        int256 v;
        int256 S;
        int256 sqrtTwo;
    }

    function createDiffLowerStruct(
        int256 S,
        int256 rx,
        int256 L,
        int256 gamma,
        int256 v,
        RmmParams memory params
    ) internal pure returns (DiffLowerStruct memory) {
        int256 a = I_TWO.wadMul(v + rx);
        int256 b = L + v - v.wadMul(gamma);
        int256 ierfcRes = Gaussian.ierfc(a.wadDiv(b));

        int256 sqrtTwo = int256(FixedPointMathLib.sqrt(2 ether) * 1e9);

        DiffLowerStruct memory ints = DiffLowerStruct({
            ierfcResult: ierfcRes,
            mean: int256(params.K),
            width: int256(params.sigma),
            gamma: gamma,
            rX: rx,
            L: L,
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
        int256 firstExp = -(params.width.wadMul(params.width).wadDiv(I_TWO));
        int256 secondExp =
            params.sqrtTwo.wadMul(params.width).wadMul(params.ierfcResult);

        int256 first = FixedPointMathLib.expWad(firstExp + secondExp);
        int256 second = params.mean.wadMul(
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
        int256 a = I_HALF.wadMul(params.mean).wadMul(-I_ONE + params.gamma);
        int256 b = params.width.wadDiv(params.sqrtTwo);
        return a.wadMul(Gaussian.erfc(b - params.ierfcResult));
    }

    function diffLower(
        int256 S,
        int256 rX,
        int256 L,
        int256 v,
        RmmParams memory params
    ) internal pure returns (int256) {
        int256 gamma = I_ONE - int256(params.fee);
        DiffLowerStruct memory ints =
            createDiffLowerStruct(S, rX, L, gamma, v, params);
        int256 a = computeLowerA(ints);
        int256 b = computeLowerB(ints);

        return -ints.S + a + b;
    }

    struct DiffRaiseStruct {
        int256 ierfcResult;
        int256 mean;
        int256 width;
        int256 gamma;
        int256 rY;
        int256 L;
        int256 v;
        int256 S;
        int256 sqrtTwo;
    }

    function createDiffRaiseStruct(
        int256 S,
        int256 ry,
        int256 L,
        int256 gamma,
        int256 v,
        RmmParams memory params
    ) internal pure returns (DiffRaiseStruct memory) {
        int256 a = I_TWO.wadMul(v + ry);
        int256 b = int256(params.K).wadMul(L) + v - v.wadMul(gamma);
        int256 ierfcRes = Gaussian.ierfc(a.wadDiv(b));

        int256 sqrtTwo = int256(FixedPointMathLib.sqrt(2 ether) * 1e9);

        DiffRaiseStruct memory ints = DiffRaiseStruct({
            ierfcResult: ierfcRes,
            mean: int256(params.K),
            width: int256(params.sigma),
            gamma: gamma,
            rY: ry,
            L: L,
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
        int256 firstExp = -(params.width.wadMul(params.width).wadDiv(I_TWO));
        int256 secondExp =
            params.sqrtTwo.wadMul(params.width).wadMul(params.ierfcResult);
        int256 first = FixedPointMathLib.expWad(firstExp + secondExp);
        int256 second = params.S.wadMul(
            params.mean.wadMul(params.L)
                + params.rY.wadMul(-I_ONE + params.gamma)
        );

        int256 num = first.wadMul(second);
        int256 den = params.mean.wadMul(
            params.mean.wadMul(params.L) + params.v
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
        int256 erfcFirst = params.width.wadDiv(params.sqrtTwo);
        int256 num = first.wadMul(Gaussian.erfc(erfcFirst - params.ierfcResult));
        int256 den = I_TWO.wadMul(params.mean);
        return num.wadDiv(den);
    }

    function diffRaise(
        int256 S,
        int256 rY,
        int256 L,
        int256 v,
        RmmParams memory params
    ) internal pure returns (int256) {
        int256 gamma = I_ONE - int256(params.fee);
        DiffRaiseStruct memory ints =
            createDiffRaiseStruct(S, rY, L, gamma, v, params);
        int256 a = computeRaiseA(ints);
        int256 b = computeRaiseB(ints);

        return -I_ONE + a + b;
    }

    function computeDy(
        int256 S,
        int256 rY,
        int256 L,
        RmmParams memory params
    ) internal pure returns (int256 dy) {
        int256 gamma = I_ONE - int256(params.fee);
        int256 mean = int256(params.K);
        int256 width = int256(params.sigma);

        int256 lnSDivMean = computeLnSDivK(uint256(S), params.K);
        int256 a = lnSDivMean.wadDiv(width) - width.wadDiv(I_TWO);
        int256 cdfA = Gaussian.cdf(a);

        int256 delta = L.wadMul(mean).wadMul(cdfA);
        dy = delta - rY;
    }

    function computeDx(
        int256 S,
        int256 rX,
        int256 L,
        RmmParams memory params
    ) internal pure returns (int256 dx) {
        int256 gamma = I_ONE - int256(params.fee);
        int256 width = int256(params.sigma);

        int256 lnSDivMean = computeLnSDivK(uint256(S), params.K);
        int256 a = Gaussian.cdf(lnSDivMean.wadDiv(width) + width.wadDiv(I_TWO));

        int256 delta = L.wadMul(I_ONE - a);
        dx = delta - rX;
    }

    function computeOptimalLower(
        int256 S,
        int256 rX,
        int256 L,
        uint256 vUpper,
        RmmParams memory params
    ) internal pure returns (uint256 v) {
        uint256 upper = vUpper;
        uint256 lower = 1;
        int256 lowerBoundOutput = diffLower(S, rX, L, int256(lower), params);
        if (lowerBoundOutput < 0) {
            return 0;
        }
        (v,,) = bisection(
            abi.encode(S, rX, L, params),
            lower,
            upper,
            uint256(1),
            256,
            findRootLower
        );
    }

    function computeOptimalRaise(
        int256 S,
        int256 rY,
        int256 L,
        uint256 vUpper,
        RmmParams memory params
    ) internal pure returns (uint256 v) {
        uint256 upper = vUpper;
        uint256 lower = 1;
        int256 lowerBoundOutput = diffRaise(S, rY, L, int256(lower), params);
        if (lowerBoundOutput < 0) {
            return 0;
        }
        (v,,) = bisection(
            abi.encode(S, rY, L, params),
            lower,
            upper,
            uint256(1),
            256,
            findRootRaise
        );
    }
}