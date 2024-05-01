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