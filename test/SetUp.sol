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

struct InitParams {
    uint256 priceX;
    uint256 totalAsset;
    uint256 strike;
    uint256 sigma;
    uint256 maturity;
    address PT;
    uint256 amountX;
    uint256 fee;
    address curator;
}

contract SetUp is Test {
    RMM public rmm;
    WETH public weth;

    MockERC20 public wstETH; // Currently not used

    MockERC20 public IB;
    IStandardizedYield public SY;
    IPYieldToken public YT;
    IPPrincipalToken public PT;

    uint32 public DEFAULT_EXPIRY = 1_717_214_400;
    uint256 public DEFAULT_AMOUNT = 1_000 ether;

    function getDefaultParams() internal view returns (InitParams memory) {
        return InitParams({
            priceX: 1 ether,
            totalAsset: 1 ether,
            strike: 1 ether,
            sigma: 0.015 ether,
            maturity: PT.expiry(),
            PT: address(PT),
            amountX: 1 ether,
            fee: 0.00016 ether,
            curator: address(0x55)
        });
    }

    modifier initDefaultPool() {
        InitParams memory params = getDefaultParams();
        rmm.init(params.PT, params.priceX, params.amountX, params.strike, params.sigma, params.fee, params.curator);
        _;
    }

    modifier initSYPool() {
        rmm.init(
            address(PT),
            1007488755655417383,
            1411689788256138069842 - 100 ether,
            1009671560073979390,
            0.025 ether,
            0.0003 ether,
            address(0x55)
        );
        _;
    }

    modifier initPool(InitParams memory params) {
        rmm.init(params.PT, params.priceX, params.amountX, params.strike, params.sigma, params.fee, params.curator);
        _;
    }

    modifier dealSY(address to, uint256 amount) {
        deal(address(SY), to, amount);
        _;
    }

    function setUp() public virtual {
        weth = new WETH();
        rmm = new RMM(address(weth), "RMM-LP-TOKEN", "RMM-LPT");
        IB = new MockERC20("ibToken", "IB", 18);
        SY = IStandardizedYield(new PendleERC20SY("SY", "SY", address(weth)));

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

        deal(address(weth), address(this), 1_000_000 ether);
        weth.approve(address(SY), type(uint256).max);
        SY.deposit(address(this), address(weth), DEFAULT_AMOUNT, 1);

        SY.transfer(address(YT), DEFAULT_AMOUNT - 1 ether);
        YT.mintPY(address(this), address(this));

        weth.approve(address(rmm), type(uint256).max);
        SY.approve(address(rmm), type(uint256).max);
        PT.approve(address(rmm), type(uint256).max);
        YT.approve(address(rmm), type(uint256).max);
    }
}
