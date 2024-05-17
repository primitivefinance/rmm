// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {RMM} from "./../src/RMM.sol";

contract MockRMM is RMM {
    constructor(address weth_, string memory name_, string memory symbol_) RMM(weth_, name_, symbol_) {
        WETH = weth_;
    }

    function debit(address token, uint256 amountWad, bytes memory data) internal returns (uint256 paymentNative) {
        return _debit(token, amountWad, data);
    }

    function credit(address token, address to, uint256 amount) internal returns (uint256 paymentNative) {
        return _credit(token, to, amount);
    }
}