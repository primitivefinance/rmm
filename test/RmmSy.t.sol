// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {RMM, toInt, toUint, upscale, downscaleDown, scalar, sum, abs} from "../src/RMM.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ReturnsTooLittleToken} from "solmate/test/utils/weird-tokens/ReturnsTooLittleToken.sol";
import {ReturnsTooMuchToken} from "solmate/test/utils/weird-tokens/ReturnsTooMuchToken.sol";
import {MissingReturnToken} from "solmate/test/utils/weird-tokens/MissingReturnToken.sol";
import {ReturnsFalseToken} from "solmate/test/utils/weird-tokens/ReturnsFalseToken.sol";

// slot numbers. double check these if changes are made.
uint256 constant offset = 6; // ERC20 inheritance adds 6 storage slots.
uint256 constant TOKEN_X_SLOT = 0 + offset;
uint256 constant TOKEN_Y_SLOT = 1 + offset;
uint256 constant RESERVE_X_SLOT = 2 + offset;
uint256 constant RESERVE_Y_SLOT = 3 + offset;
uint256 constant TOTAL_LIQUIDITY_SLOT = 4 + offset;
uint256 constant STRIKE_SLOT = 5 + offset;
uint256 constant SIGMA_SLOT = 6 + offset;
uint256 constant FEE_SLOT = 7 + offset;
uint256 constant MATURITY_SLOT = 8 + offset;
uint256 constant INIT_TIMESTAMP_SLOT = 9 + offset;
uint256 constant LAST_TIMESTAMP_SLOT = 10 + offset;
uint256 constant CURATOR_SLOT = 11 + offset;
uint256 constant LOCK_SLOT = 12 + offset;

IPAllActionV3 constant router = IPAllActionV3(0x00000000005BBB0EF59571E58418F9a4357b68A0);
//IPMarket public constant market = IPMarket(0xC374f7eC85F8C7DE3207a10bB1978bA104bdA3B2);
//IPMarket public constant market = IPMarket(0xD0354D4e7bCf345fB117cabe41aCaDb724eccCa2);
IPMarket constant market = IPMarket(0x9eC4c502D989F04FfA9312C9D6E3F872EC91A0F9);
address constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0; //real wsteth

contract RMMTest is Test {
    RMM public __subject__;
    MockERC20 public tokenX;
    MockERC20 public tokenY;

    function setUp() public tokens {
        __subject__ = new RMM(address(0), "LPToken", "LPT");
        vm.label(address(__subject__), "RMM");
        vm.warp(0);
    }

    function subject() public view returns (RMM) {
        return __subject__;
    }

    function balanceNative(address token, address account) internal view returns (uint256) {
        if (token == address(0)) {
            return address(this).balance;
        }

        return MockERC20(token).balanceOf(account);
    }

    function balanceWad(address token, address account) internal view returns (uint256) {
        return upscale(balanceNative(token, account), scalar(token));
    }

    modifier tokens() {
        _;
        tokenX = new MockERC20("Token X", "X", 18);
        tokenY = new MockERC20("Token Y", "Y", 18);
        vm.label(address(tokenX), "Token X");
        vm.label(address(tokenY), "Token Y");
    }

    modifier basic() {
        deal(address(tokenX), address(this), 100 ether);
        deal(address(tokenY), address(this), 100 ether);
        tokenX.approve(address(subject()), 100 ether);
        tokenY.approve(address(subject()), 100 ether);
        subject().init({
            tokenX_: address(tokenX),
            tokenY_: address(tokenY),
            priceX: 1 ether,
            amountX: 1 ether,
            strike_: 1 ether,
            sigma_: 1 ether,
            fee_: 0,
            maturity_: 365 days,
            curator_: address(0x55)
        });

        _;
    }
}
