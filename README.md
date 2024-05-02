## rmm specifciation

State variables include:
- reserve x and y
- liquidity
- parameters
- last "interaction" timestamp. interaction could be only swaps, or include more actions.
- curator
- weth

Constructor
- WETH
- Deploys ERC-20 token, maybe from proxy?

Init
- Sets the initial parameter state of the pool
- burns the initial liquidity
- Does it require tokens to be sent in?

Adjust
- Allows arbitrary adjustments, validates against trading function
- flash swaps to allow optimistic payments

Helpers:
- helper functions to handle specific actions
- helper functions for math


## on adjustments

Adjustments can be made to X, Y, or L. Adjustments can be negative or positive. Here's a rough guide for them:

- Allocate: +, +, +
- Deallocate: -, -, -
- Swap: +/-, -/+, +λ
- Single allocate: +/0, 0/+ +
- Single deallocate: -/0, 0/-, -λ

λ is fees that are applied via liquidity.


## notes

computing with math is wrong. need to bisect over the trading function to find the optimal amounts, in all cases.

for example we want to swap x in. we take a small amount out of x (the fee), reducing its purchasing power. we bisect over the trading function until we find a y that satisfies it, keeping L static. Then, we take the fee amount in X, apply that given the new Y, until we find an L that satisfies it. The L delta is the amount we need to inflate to compensate for fees. This leverages the invariant to determine the optimal amounts instead of the price derivations or formulas. finally (and i think this it how it works), we change the invariant validation to be >= prev invariant. This would make the invariant result a "checkpoint" system for the fees, so that all the optimal amounts are computed while considering the existing inflation that was already added to the pool.