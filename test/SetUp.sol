/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PYIndex, PYIndexLib} from "pendle/core/StandardizedYield/PYIndex.sol";
import {Test} from "forge-std/Test.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {IPPrincipalToken} from "pendle/interfaces/IPPrincipalToken.sol";
import {IPYieldToken} from "pendle/interfaces/IPYieldToken.sol";
import {BaseSplitCodeFactory} from "pendle/core/libraries/BaseSplitCodeFactory.sol";
import {PendleYieldTokenV2} from "pendle/core/YieldContractsV2/PendleYieldTokenV2.sol";
import {PendleYieldContractFactoryV2} from "pendle/core/YieldContractsV2/PendleYieldContractFactoryV2.sol";
import {PendleWstEthSY} from "pendle/core/StandardizedYield/implementations/PendleWstEthSY.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockWstETH} from "./mocks/MockWstETH.sol";
import {MockStETH} from "./mocks/MockStETH.sol";

import {RMM} from "./../src/RMM.sol";

struct InitParams {
    uint256 priceX;
    uint256 amountX;
    uint256 strike;
    uint256 sigma;
    uint256 maturity;
    address PT;
    uint256 fee;
    address curator;
}

// address constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0; //real wsteth
// address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

contract SetUp is Test {
    using PYIndexLib for IPYieldToken;
    using PYIndexLib for PYIndex;

    // All the contracts that are needed for the tests.
    RMM public rmm;
    WETH public weth;
    PendleWstEthSY public SY;
    IPYieldToken public YT;
    IPPrincipalToken public PT;
    MockWstETH public wstETH;
    MockStETH public stETH;

    // Some default constants.

    uint32 public DEFAULT_EXPIRY = 1_717_214_400;
    uint256 public DEFAULT_AMOUNT = 1_000 ether;

    // Main setup functions.

    function setUpContracts(uint32 expiry) public {
        weth = new WETH();
        stETH = new MockStETH();
        wstETH = new MockWstETH(address(stETH));
        rmm = new RMM(address(weth), "RMM-LP-TOKEN", "RMM-LPT");
        SY = new PendleWstEthSY("wstEthSY", "wstEthSY", address(weth), address(wstETH));

        vm.label(address(SY), "SY");
        vm.label(address(YT), "YT");
        vm.label(address(PT), "PT");
        vm.label(address(wstETH), "wstETH");
        vm.label(address(stETH), "stETH");

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
        factory.createYieldContract(address(SY), expiry, true);

        YT = IPYieldToken(factory.getYT(address(SY), expiry));
        PT = IPPrincipalToken(factory.getPT(address(SY), expiry));

        weth.approve(address(rmm), type(uint256).max);
        SY.approve(address(rmm), type(uint256).max);
        PT.approve(address(rmm), type(uint256).max);
        YT.approve(address(rmm), type(uint256).max);
    }

    function setUp() public virtual {
        setUpContracts(DEFAULT_EXPIRY);
    }

    // Here are some utility functions, you can use them to set specific states inside of a test.

    function mintSY(address to, uint256 amount) public {
        // SY.deposit(address(to), address(wstETH), amount, 0);
        deal(address(SY), address(to), amount);
    }

    function batchMintSY(address[] memory to, uint256[] memory amounts) public {
        require(to.length == amounts.length, "INVALID_LENGTH");
        for (uint256 i; i < to.length; i++) {
            mintSY(to[i], amounts[i]);
        }
    }

    function mintPY(address to, uint256 amount) public {
        SY.transfer(address(YT), amount);
        YT.mintPY(to, to);
    }

    function batchMintPY(address[] memory to, uint256[] memory amounts) public {
        require(to.length == amounts.length, "INVALID_LENGTH");
        for (uint256 i; i < to.length; i++) {
            mintPY(to[i], amounts[i]);
        }
    }

    function getDefaultParams() internal view returns (InitParams memory) {
        return InitParams({
            priceX: 1.15 ether,
            amountX: 100 ether,
            strike: 1.15 ether,
            sigma: 0.02 ether,
            maturity: PT.expiry(),
            PT: address(PT),
            fee: 0.00016 ether,
            curator: address(0x55)
        });
    }

    // Here are some modifiers, you can use them as hooks to set up the environment before running a test.

    modifier useContrats(uint32 expiry) {
        setUpContracts(expiry);
        _;
    }

    modifier useDefaultPool() {
        uint256 amount = 10000 ether;
        mintSY(address(this), amount);
        mintPY(address(this), amount / 2);
        InitParams memory params = getDefaultParams();
        rmm.init(params.PT, params.priceX, params.amountX, params.strike, params.sigma, params.fee, params.curator);
        _;
    }

    modifier useSYPool() {
        uint256 amount = 1_000_000 ether;
        mintSY(address(this), amount);
        mintPY(address(this), amount / 2);
        rmm.init(
            address(PT),
            1007488755655417383,
            1311689788256138069842,
            1009671560073979390,
            0.025 ether,
            0.0003 ether,
            address(0x55)
        );
        _;
    }

    modifier withSY(address to, uint256 amount) {
        // SY.deposit(address(to), address(wstETH), amount, 0);
        deal(address(SY), address(to), amount);
        _;
    }

    modifier withPY(address to, uint256 amount) {
        SY.transfer(address(YT), amount);
        YT.mintPY(to, to);
        _;
    }

    modifier withWETH(address to, uint256 amount) {
        weth.deposit{value: amount}();
        weth.transfer(to, amount);
        _;
    }

    function skip() public {
        vm.skip(true);
    }

    function newIndex() public returns (PYIndex) {
        return YT.newIndex();
    }

    function syToAsset(uint256 amount) public returns (uint256) {
        return newIndex().syToAsset(amount);
    }
}
