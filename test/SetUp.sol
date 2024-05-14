/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {RMM} from "./../src/RMM.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {PendleERC20SY} from "pendle/core/StandardizedYield/implementations/PendleERC20SY.sol";

contract SetUp is Test {
    RMM public rmm;
    WETH public weth;
    PendleERC20SY public syToken;
    MockERC20 public yieldToken;

    address public wstETH;

    function setUp() public {
        weth = new WETH();
        rmm = new RMM(address(weth), "Test", "TST");
        yieldToken = new MockERC20("YieldToken", "YLD", 18);
        syToken = new PendleERC20SY("SYToken", "SY", address(yieldToken));
    }
}
