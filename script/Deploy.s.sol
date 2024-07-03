// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {RMM} from "../src/RMM.sol";
import {Factory} from "../src/Factory.sol";

contract Deploy is Script {
    function setUp() public {}

    Factory FACTORY = Factory(0x519172BB1f45A5420090f03bAFd19A76AC9bC772);

    string public constant ENV_PRIVATE_KEY = "PRIVATE_KEY";

    function run() public {
        uint256 pk = vm.envUint(ENV_PRIVATE_KEY);
        vm.startBroadcast(pk);

        address sender = vm.addr(pk);
        console2.log("Deploying RMM from", sender);
        // RMM rmm = FACTORY.createRMM("RMM", "RMM");

        vm.stopBroadcast();
    }
}
