/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SetUp} from "../SetUp.sol";

contract CreditTest is SetUp {
    function test_credit_TransfersTokens() public {
        deal(address(weth), address(rmm), 1 ether);

        uint256 preBalanceRMM = weth.balanceOf(address(rmm));
        uint256 preBalanceAccount = weth.balanceOf(address(this));

        rmm.credit(address(weth), address(this), 1 ether);

        assertEq(weth.balanceOf(address(rmm)), preBalanceRMM - 1 ether);
        assertEq(weth.balanceOf(address(this)), preBalanceAccount + 1 ether);
    }
}
