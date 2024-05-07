// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {RMM} from "../src/RMM.sol";

address constant WETH_ADDRESS = 0x74A4A85C611679B73F402B36c0F84A7D2CcdFDa3;

contract Deploy is Script {
    function setUp() public {}

    string public constant ENV_PRIVATE_KEY = "PRIVATE_KEY";

    function run() public {
        uint256 pk = vm.envUint(ENV_PRIVATE_KEY);
        vm.startBroadcast(pk);
        require(WETH_ADDRESS != address(0), "WETH_ADDRESS not set");

        address sender = vm.addr(pk);
        console2.log("Deploying RMM from", sender);
        RMM rmm = new RMM(WETH_ADDRESS, "RMM", "RMM-LPT");
        console2.log("RMM deployed at", address(rmm));

        vm.stopBroadcast();
    }
}
