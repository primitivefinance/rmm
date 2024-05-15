/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IStandardizedYield, PendleERC20SY} from "pendle/core/StandardizedYield/implementations/PendleERC20SY.sol";
import {IPPrincipalToken} from "pendle/interfaces/IPPrincipalToken.sol";
import {IPYieldToken} from "pendle/interfaces/IPYieldToken.sol";
import {BaseSplitCodeFactory} from "pendle/core/libraries/BaseSplitCodeFactory.sol";
import {PendleYieldTokenV2} from "pendle/core/YieldContractsV2/PendleYieldTokenV2.sol";
import {PendleYieldContractFactoryV2} from "pendle/core/YieldContractsV2/PendleYieldContractFactoryV2.sol";

import {RMM} from "./../src/RMM.sol";

contract SetUp is Test {
    RMM public rmm;
    WETH public weth;
    MockERC20 public IB;
    IStandardizedYield public SY;
    IPYieldToken public YT;
    IPPrincipalToken public PT;

    uint32 public DEFAULT_EXPIRY = 1_717_214_400;
    uint256 public DEFAULT_AMOUNT = 1_000 ether;

    function setUp() public {
        weth = new WETH();
        rmm = new RMM(address(weth), "RMM-LP-TOKEN", "RMM-LPT");
        IB = new MockERC20("ibToken", "IB", 18);
        SY = IStandardizedYield(new PendleERC20SY("SY", "SY", address(IB)));

        (
            address creationCodeContractA,
            uint256 creationCodeSizeA,
            address creationCodeContractB,
            uint256 creationCodeSizeB
        ) = BaseSplitCodeFactory.setCreationCode(type(PendleYieldTokenV2).creationCode);

        PendleYieldContractFactoryV2 factory = new PendleYieldContractFactoryV2(
            creationCodeContractA, creationCodeSizeA, creationCodeContractB, creationCodeSizeB
        );

        factory.initialize(1, 2e17, 0, address(this));
        factory.createYieldContract(address(SY), DEFAULT_EXPIRY, true);

        YT = IPYieldToken(factory.getYT(address(SY), DEFAULT_EXPIRY));
        PT = IPPrincipalToken(factory.getPT(address(SY), DEFAULT_EXPIRY));

        deal(address(IB), address(this), 1_000 ether);
        IB.approve(address(SY), type(uint256).max);
        SY.deposit(address(this), address(IB), DEFAULT_AMOUNT, 1);

        SY.transfer(address(YT), DEFAULT_AMOUNT);
        YT.mintPY(address(this), address(this));
    }
}
