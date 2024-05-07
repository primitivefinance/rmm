// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {PendleERC20SY} from "pendle/core/StandardizedYield/implementations/PendleERC20SY.sol";
import {SYBase} from "pendle/core/StandardizedYield/SYBase.sol";
import {IStandardizedYield} from "pendle/interfaces/IStandardizedYield.sol";
import {PendleYieldContractFactoryV2} from "pendle/core/YieldContractsV2/PendleYieldContractFactoryV2.sol";
import {PendleYieldTokenV2} from "pendle/core/YieldContractsV2/PendleYieldTokenV2.sol";
import {BaseSplitCodeFactory} from "pendle/core/libraries/BaseSplitCodeFactory.sol";
import {RMM} from "../src/RMM.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract DeployPool is Script {
    function setUp() public {}

    string public constant ENV_PRIVATE_KEY = "PRIVATE_KEY";
    address payable public constant RMM_ADDRESS = payable(0xc04E06bDb42ce32C87d28C604C908cAf65A662F2);
    address public constant SY_ADDRESS = 0x14AeD33295C3ac9D8195295542914b8BB0977814;
    address public constant PT_ADDRESS = 0xB3aB0e660FcA698606490868fF7D13c7Dfb31694;
    uint256 public constant startPrice = 1 ether;
    uint256 public constant initialDepositX = 1 ether;
    uint256 public constant strike = 1 ether;
    uint256 public constant sigma = 1 ether;
    uint256 public constant tau = 365 days;
    uint256 public constant fee = 0;
    address public constant curator = address(0);

    function run() public {
        uint256 pk = vm.envUint(ENV_PRIVATE_KEY);
        address sender = vm.addr(pk);
        vm.startBroadcast(pk);

        require(RMM_ADDRESS != address(0), "RMM_ADDRESS not set");
        require(SY_ADDRESS != address(0), "SY_ADDRESS not set");
        require(PT_ADDRESS != address(0), "PT_ADDRESS not set");

        uint256 maturity = tau + block.timestamp;

        (uint256 initialLiquidity, uint256 initialDepositY) = RMM(RMM_ADDRESS).prepareInit({
            priceX: startPrice,
            amountX: initialDepositX,
            strike_: strike,
            sigma_: sigma,
            maturity_: maturity
        });

        if (ERC20(SY_ADDRESS).allowance(msg.sender, address(this)) < initialDepositX) {
            ERC20(SY_ADDRESS).approve(RMM_ADDRESS, initialDepositX);
        }

        if (ERC20(PT_ADDRESS).allowance(msg.sender, address(this)) < initialDepositY) {
            ERC20(PT_ADDRESS).approve(RMM_ADDRESS, initialDepositY + 1 ether);
        }

        RMM(RMM_ADDRESS).init({
            tokenX_: SY_ADDRESS,
            tokenY_: PT_ADDRESS,
            priceX: startPrice,
            amountX: initialDepositX,
            strike_: strike,
            sigma_: sigma,
            fee_: fee,
            maturity_: maturity,
            curator_: curator
        });

        uint256 balance = ERC20(RMM_ADDRESS).balanceOf(sender);
        console2.log("RMM LPT balance: ", balance);

        vm.stopBroadcast();
    }
}
