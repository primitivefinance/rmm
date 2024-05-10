// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {RMM} from "../src/RMM.sol";
import {Factory} from "../src/Factory.sol";

address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

contract DeployFactory is Script {
    function setUp() public {}

    string public constant ENV_PRIVATE_KEY = "PRIVATE_KEY";

    function run() public {
        uint256 pk = vm.envUint(ENV_PRIVATE_KEY);
        vm.startBroadcast(pk);
        require(WETH_ADDRESS != address(0), "WETH_ADDRESS not set");

        address sender = vm.addr(pk);
        console2.log("Deploying RMM from", sender);
        Factory factory = new Factory(WETH_ADDRESS);
        console2.log("Factory deployed at", address(factory));

        vm.stopBroadcast();
    }
}
