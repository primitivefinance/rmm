// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @dev Thrown if trying to initialize an already initialized pool.
error AlreadyInitialized();
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