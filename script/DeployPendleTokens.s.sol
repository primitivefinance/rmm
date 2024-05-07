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

contract DeployPendleTokens is Script {
    function setUp() public {}

    string public constant ENV_PRIVATE_KEY = "PRIVATE_KEY";

    function run() public {
        uint256 pk = vm.envUint(ENV_PRIVATE_KEY);
        vm.startBroadcast(pk);
        address sender = vm.addr(pk);
        uint32 _expiry = 1_717_214_400;

        address wstETH = address(new MockERC20("Wrapped stETH", "wstETH", 18));

        // Mint some tokens to the deployer
        MockERC20(wstETH).mint(sender, 2_000_000 ether);

        // Deploy ERC20 Standard Yield on wstETH
        SYBase SY = new PendleERC20SY("Standard Yield wstETH", "SYwstETH", wstETH);

        // Deposit 50% of tokens into SYwstETH
        MockERC20(wstETH).approve(address(SY), type(uint256).max);
        SY.deposit(sender, wstETH, 1_000_000 ether, 1);
        console2.log("Deposit Confirmed: ", SY.totalSupply());

        // Deploy YieldContractFactory
        (address ytCodeContractA, uint256 ytCodeSizeA, address ytCodeContractB, uint256 ytCodeSizeB) =
            BaseSplitCodeFactory.setCreationCode(type(PendleYieldTokenV2).creationCode);
        PendleYieldContractFactoryV2 YCF = new PendleYieldContractFactoryV2({
            _ytCreationCodeContractA: ytCodeContractA,
            _ytCreationCodeSizeA: ytCodeSizeA,
            _ytCreationCodeContractB: ytCodeContractB,
            _ytCreationCodeSizeB: ytCodeSizeB
        });

        // Initalize YieldContractFactory
        YCF.initialize(1, 2e17, 0, sender);

        // Create YieldContract via Factory
        YCF.createYieldContract(address(SY), 1_717_214_400, true);

        // Store YT/PT addresses in config
        address wstETH_YT = YCF.getYT(address(SY), _expiry);
        address wstETH_PT = YCF.getPT(address(SY), _expiry);
        console2.log("SY Address: ", address(SY));
        console2.log("YT Token Deployed at: ", wstETH_YT);
        console2.log("PT Token Deployed at: ", wstETH_PT);
        console2.log("Yield Contract Created with SY: ", address(SY));

        // Mint PT/YT with deposited tokens 
        SY.transfer(wstETH_YT, 1_000_000 ether);
        console2.log("YieldToken SY Balance: ", PendleYieldTokenV2(wstETH_YT).balanceOf(address(SY)));
        uint256 ptOut = PendleYieldTokenV2(wstETH_YT).mintPY(sender, sender); 
        console2.log("Number of PT + YT Minted: ", ptOut);

        // Deposit the remaing wstETH into SY
        SY.deposit(sender, wstETH, 1_000_000 ether, 1);

        vm.stopBroadcast();
    }
}
