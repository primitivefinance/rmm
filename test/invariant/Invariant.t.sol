// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/RMM.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {IPMarket} from "pendle/interfaces/IPMarket.sol";
import "pendle/core/Market/MarketMathCore.sol";
import "pendle/interfaces/IPAllActionV3.sol";
import {IPPrincipalToken} from "pendle/interfaces/IPPrincipalToken.sol";
import {IStandardizedYield} from "pendle/interfaces/IStandardizedYield.sol";
import {IPYieldToken} from "pendle/interfaces/IPYieldToken.sol";

import {PendleERC20SY} from "pendle/core/StandardizedYield/implementations/PendleERC20SY.sol";
import {SYBase} from "pendle/core/StandardizedYield/SYBase.sol";
import {PendleYieldContractFactoryV2} from "pendle/core/YieldContractsV2/PendleYieldContractFactoryV2.sol";
import {PendleYieldTokenV2} from "pendle/core/YieldContractsV2/PendleYieldTokenV2.sol";
import {BaseSplitCodeFactory} from "pendle/core/libraries/BaseSplitCodeFactory.sol";

import {AlreadyInitialized} from "../../src/lib/RmmErrors.sol";

struct Calls {
    uint256 success;
    uint256 reverts;
    uint256 total;
}

contract InvariantHandler is Test {
    using MarketMathCore for MarketState;
    using MarketMathCore for int256;
    using MarketMathCore for uint256;
    using FixedPointMathLib for uint256;
    using PYIndexLib for IPYieldToken;
    using PYIndexLib for PYIndex;

    RMM public rmm;
    address public wstETH;
    IStandardizedYield public SY;
    IPPrincipalToken public PT;
    IPYieldToken public YT;

    Calls public initCalls;

    struct Scenario {
        uint256 price;
        uint256 strike;
        uint256 sigma;
        uint256 fee;
        uint256 maturity;
    }

    mapping(uint256 => Scenario) scenarios;

    Scenario ghostScenario;

    constructor() {
        scenarios[0] = Scenario({price: 1 ether, strike: 1 ether, sigma: 1 ether, fee: 0, maturity: 365 days});
        scenarios[1] = Scenario({price: 1 ether, strike: 1 ether, sigma: 1 ether, fee: 0, maturity: 1 days});
        scenarios[2] = Scenario({price: 1 ether, strike: 1 ether, sigma: 1, fee: 0, maturity: 365 days});
        scenarios[3] = Scenario({price: 1 ether, strike: 1 ether, sigma: 2 ether, fee: 0, maturity: 365 days});
        /*scenarios[4] = Scenario({price: 1 ether, strike: 1 ether, sigma: 1 ether, fee: 0, maturity: 730 days});
        scenarios[5] = Scenario({price: 1 ether, strike: 1 ether, sigma: 1 ether, fee: 0.001 ether, maturity: 365 days});
        scenarios[6] = Scenario({price: 1 ether, strike: 1 ether, sigma: 1 ether, fee: 0.1 ether, maturity: 365 days});
        scenarios[7] = Scenario({price: 1 ether, strike: 1 ether, sigma: 1 ether, fee: 0, maturity: 7 days});
        scenarios[8] = Scenario({price: 1 ether, strike: 1 ether, sigma: 1 ether, fee: 0, maturity: 30 days});
        scenarios[9] = Scenario({price: 1 ether, strike: 1 ether, sigma: 1 ether, fee: 0, maturity: 90 days});
        scenarios[10] = Scenario({price: 1 ether, strike: 2 ether, sigma: 1 ether, fee: 0, maturity: 365 days});
        scenarios[11] = Scenario({price: 1 ether, strike: 1.5 ether, sigma: 1 ether, fee: 0, maturity: 365 days});
        scenarios[12] = Scenario({price: 1 ether, strike: 0.5 ether, sigma: 1 ether, fee: 0, maturity: 365 days});
        scenarios[13] = Scenario({price: 1 ether, strike: 1.1 ether, sigma: 1 ether, fee: 0, maturity: 365 days});
        scenarios[14] = Scenario({price: 1 ether, strike: 0.9 ether, sigma: 1 ether, fee: 0, maturity: 365 days}); */
        console2.log("Setup InvariantHandler");
    }

    function handle_sanity() public {
        initCalls.total++;
        initCalls.total++;
        initCalls.success++;
        initCalls.reverts++;
    }

    function reset() public {
        rmm = new RMM(address(0), "RMM", "RMM");
        uint32 _expiry = 1_717_214_400;

        address wstETH = address(new MockERC20("Wrapped stETH", "wstETH", 18));
        SYBase SY_ = new PendleERC20SY("Standard Yield wstETH", "SYwstETH", wstETH);
        SY = IStandardizedYield(SY_);
        (address ytCodeContractA, uint256 ytCodeSizeA, address ytCodeContractB, uint256 ytCodeSizeB) =
            BaseSplitCodeFactory.setCreationCode(type(PendleYieldTokenV2).creationCode);
        PendleYieldContractFactoryV2 YCF = new PendleYieldContractFactoryV2({
            _ytCreationCodeContractA: ytCodeContractA,
            _ytCreationCodeSizeA: ytCodeSizeA,
            _ytCreationCodeContractB: ytCodeContractB,
            _ytCreationCodeSizeB: ytCodeSizeB
        });

        YCF.initialize(1, 2e17, 0, address(this));
        YCF.createYieldContract(address(SY), _expiry, true);
        YT = IPYieldToken(YCF.getYT(address(SY), _expiry));
        PT = IPPrincipalToken(YCF.getPT(address(SY), _expiry));
    }

    function mintSY(uint256 amount) public {
        IERC20(wstETH).approve(address(SY), type(uint256).max);
        SY.deposit(address(this), address(wstETH), amount, 1);
    }

    function mintPtYt(uint256 amount) public {
        SY.transfer(address(YT), amount);
        YT.mintPY(address(this), address(this));
    }

    function handle_init(uint256 rand) public {
        reset();

        initCalls.total++;
        uint256 index = rand % 4;
        ghostScenario = scenarios[index];
        (uint256 liquidity, uint256 amountY) = rmm.prepareInit({
            priceX: ghostScenario.price,
            totalAsset: ghostScenario.price,
            strike_: ghostScenario.strike,
            sigma_: ghostScenario.sigma,
            maturity_: ghostScenario.maturity
        });

        mintSY(ghostScenario.price);
        mintPtYt(amountY);

        SY.approve(address(rmm), ghostScenario.price);
        PT.approve(address(rmm), amountY);

        try rmm.init({
            PT_: address(PT),
            priceX: ghostScenario.price,
            amountX: ghostScenario.price,
            strike_: ghostScenario.strike,
            sigma_: ghostScenario.sigma,
            fee_: ghostScenario.fee,
            curator_: address(0)
        }) {
            initCalls.success++;
        } catch (bytes memory err) {
            if (bytes4(err) == bytes4(abi.encodeWithSelector(AlreadyInitialized.selector))) {
                initCalls.success++;
            } else {
                initCalls.reverts++;
                revert("Init call failed");
            }
        }
    }

    Calls public adjustCalls;

    // function handle_adjust(int256 deltaX, int256 deltaY, int256 delLiquidity) public {
    //     adjustCalls.total++;
    //     try rmm.adjust(deltaX, deltaY, delLiquidity) {
    //         adjustCalls.success++;
    //     } catch (bytes memory err) {
    //         adjustCalls.reverts++;
    //         revert("Adjust call failed");
    //     }
    // }

    Calls public allocateCalls;

    function handle_allocate(uint256 deltaX, uint256 deltaY) public {
        mintSY(deltaX);
        mintPtYt(deltaY);
        SY.approve(address(rmm), deltaX);
        PT.approve(address(rmm), deltaY);

        PYIndex index = YT.newIndex();

        (,, uint256 deltaLiquidity,) = rmm.prepareAllocate(deltaX, deltaY, index);

        allocateCalls.total++;
        try rmm.allocate(deltaX, deltaY, deltaLiquidity, address(this)) {
            allocateCalls.success++;
        } catch (bytes memory err) {
            allocateCalls.reverts++;
            revert("Allocate call failed");
        }
    }
}

contract InvariantTest is Test {
    using PYIndexLib for IPYieldToken;

    InvariantHandler handler;
    RMM rmm;

    function setUp() public {
        vm.warp(0);
        handler = new InvariantHandler();
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = handler.handle_sanity.selector;
        selectors[1] = handler.handle_init.selector;
        // selectors[2] = handler.handle_adjust.selector;
        selectors[3] = handler.handle_allocate.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        rmm = handler.rmm();
        handler.reset(); // Sets a pool up.
        console2.log("Setup complete. Handler: %", address(handler));
    }

    function invariant_tradingFunction() public {
        IPYieldToken YT = handler.YT();
        PYIndex index = YT.newIndex();
        rmm = handler.rmm();

        // Checks if RMM was deployed.
        if (address(rmm) == address(0)) {
            return;
        }

        // Checks if a pool was created.
        if (rmm.totalSupply() == 0) {
            return;
        }

        assertTrue(abs(handler.rmm().tradingFunction(index)) <= 100, "Invariant out of valid range");
    }

    /// Invariant tests can "pass" even though all the calls revert, so we track the amount fo times
    // we successfully make a call and make sure it's not zero.
    function invariant_init_calls() public {
        (uint256 a, uint256 b, uint256 c) = handler.initCalls();
        _check_calls(Calls(a, b, c));
    }

    function invariant_adjust_calls() public {
        (uint256 a, uint256 b, uint256 c) = handler.adjustCalls();
        _check_calls(Calls(a, b, c));
    }

    function invariant_allocate_calls() public {
        (uint256 a, uint256 b, uint256 c) = handler.allocateCalls();
        _check_calls(Calls(a, b, c));
    }

    function _check_calls(Calls memory calls) internal {
        assertTrue(calls.total == 0 || (calls.success != 0 || calls.reverts != 0), "No successful or reverts.");
        assertTrue(calls.total == 0 || calls.success > 0, "No successful.");
        assertTrue(calls.total == (calls.success + calls.reverts), "Not all accounted for.");
    }
}
