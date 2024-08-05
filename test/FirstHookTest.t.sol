//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {FirstHook} from "src/FirstHook.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {console} from "lib/forge-std/src/console.sol";

contract FisrtHookTest is Test, Deployers {
    using CurrencyLibrary for Currency;

    FirstHook testHook;
    MockERC20 token;
    string name = "New Rug";
    string symbol = "NRG";
    uint8 decimals = 18;
    int24 lowerTick = -60;
    int24 upperTick = 60;
    uint128 liquidity = 1 ether;

    address user1 = makeAddr("user1");
    //ETH always have zero address since it's native
    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;

    function setUp() public {
        //deploying Manager, swapRouter& modifyLiquidityRouter
        deployFreshManagerAndRouters();
        token = new MockERC20("Test Rug", "TRG", decimals);
        tokenCurrency = Currency.wrap((address(token)));
        console.log("tokenCurrency-Address:", address(token));

        token.mint(address(this), 1000 ether);
        token.mint(user1, 1000 ether);

        // setting required bits to 1 by shifting
        uint160 flags = uint160(
            Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG
        );
        console.log("flagsInt:", flags);
        // getting the hook contract address
        deployCodeTo(
            "FirstHook.sol",
            abi.encode(manager, name, symbol),
            address(flags)
        );
        testHook = FirstHook(address(flags));

        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);

        //Initialising a pool
        (key, ) = initPool(
            ethCurrency,
            tokenCurrency,
            testHook,
            3000,
            SQRT_PRICE_1_1,
            ZERO_BYTES
        );
    }

    function test_addingLiquidityAndSwap() public {
        bytes memory hookData = testHook.getHookData(address(0), address(this));

        uint256 rugTokenBalanceOriginal = testHook.balanceOf(address(this));
        console.log("rugTokenBalanceOriginal:", rugTokenBalanceOriginal);

        uint160 priceAtLowerTick = TickMath.getSqrtPriceAtTick(lowerTick);
        uint160 priceAtUpperTick = TickMath.getSqrtPriceAtTick(upperTick);

        uint256 ethToSpend = 0.003 ether;

        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
            priceAtLowerTick,
            priceAtUpperTick,
            ethToSpend
        );

        vm.deal(address(this), 2 ether);
        modifyLiquidityRouter.modifyLiquidity{value: ethToSpend}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: lowerTick,
                tickUpper: upperTick,
                liquidityDelta: int128(liquidityDelta),
                salt: bytes32(0)
            }),
            hookData
        );

        uint256 rugTokenBalanceAfterAddLiquidity = testHook.balanceOf(
            address(this)
        );
        console.log(
            "rugTokenBalanceAfterAddLiquidity",
            rugTokenBalanceAfterAddLiquidity
        );
        uint256 actualrugTokenMinted = rugTokenBalanceAfterAddLiquidity -
            rugTokenBalanceOriginal;
        uint256 expectedRugTokenMinted = 2995354955910434;

        assertApproxEqAbs(
            actualrugTokenMinted,
            expectedRugTokenMinted,
            0.0001 ether
        );

        vm.deal(address(this), 1 ether);
        swapRouter.swap{value: 0.002 ether}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );

        uint256 rugBalanceAfterSwap = testHook.balanceOf(address(this));
        uint256 expectedSwapOutput = 2 * 10 ** 14;
        assertEq(
            rugBalanceAfterSwap - rugTokenBalanceAfterAddLiquidity,
            expectedSwapOutput
        );
    }

    function test_addLiquidityAndSWapWithReferrer() public {
        bytes memory hookData = testHook.getHookData(user1, address(this));

        uint256 testContractBalanceOriginal = testHook.balanceOf(address(this));
        uint256 user1RugTokenalanceBeforeOps = testHook.balanceOf(user1);

        uint160 priceAtLowerTick = TickMath.getSqrtPriceAtTick(lowerTick);
        uint160 priceAtUpperTick = TickMath.getSqrtPriceAtTick(upperTick);

        uint256 ethToAdd = 0.003 ether;

        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
            priceAtLowerTick,
            priceAtUpperTick,
            ethToAdd
        );

        vm.deal(address(this), 2 ether);
        modifyLiquidityRouter.modifyLiquidity{value: ethToAdd}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: lowerTick,
                tickUpper: upperTick,
                liquidityDelta: int128(liquidityDelta),
                salt: bytes32(0)
            }),
            hookData
        );

        uint256 rugTokenBalanceAfterAddingLiquidity = testHook.balanceOf(
            address(this)
        );
        uint256 rugTokenBalanceUser1AfterAddingLiquidity = testHook.balanceOf(
            user1
        );
        assertApproxEqAbs(
            rugTokenBalanceUser1AfterAddingLiquidity -
                user1RugTokenalanceBeforeOps,
            testHook.REFERRAL_POINTS_TOKEN(),
            0.001 ether
        );

        swapRouter.swap{value: 0.002 ether}(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );
    }
}
