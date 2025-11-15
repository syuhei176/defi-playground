// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPoolManager} from "uniswap-v4-core/interfaces/IPoolManager.sol";
import {PoolManager} from "uniswap-v4-core/PoolManager.sol";
import {IUnlockCallback} from "uniswap-v4-core/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "uniswap-v4-core/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "uniswap-v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "uniswap-v4-core/types/PoolId.sol";
import {BalanceDelta} from "uniswap-v4-core/types/BalanceDelta.sol";
import {IHooks} from "uniswap-v4-core/interfaces/IHooks.sol";
import {Hooks} from "uniswap-v4-core/libraries/Hooks.sol";
import {TickMath} from "uniswap-v4-core/libraries/TickMath.sol";
import {ModifyLiquidityParams, SwapParams} from "uniswap-v4-core/types/PoolOperation.sol";
import {CurrencySettler} from "../lib/uniswap-v4-core/test/utils/CurrencySettler.sol";
import {TransientStateLibrary} from "uniswap-v4-core/libraries/TransientStateLibrary.sol";
import {SimpleLoggingHook} from "../src/SimpleLoggingHook.sol";

// Simple Mock ERC20 for testing
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract UniswapV4PoolWithHookTest is Test, IUnlockCallback {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;
    using TransientStateLibrary for IPoolManager;

    // Contracts
    IPoolManager public poolManager;
    MockERC20 public token0;
    MockERC20 public token1;

    SimpleLoggingHook public hook;
    PoolKey public poolKey;
    PoolId public poolId;

    // Constants
    uint160 public constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint24 public constant FEE = 3000; // 0.3%
    int24 public constant TICK_SPACING = 60;

    // Hook permission flags
    uint160 public constant ALL_HOOK_PERMISSIONS = Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG
        | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG;

    // Callback data types
    enum CallbackType {
        INITIALIZE,
        ADD_LIQUIDITY,
        SWAP
    }

    struct CallbackData {
        CallbackType callbackType;
        PoolKey key;
        ModifyLiquidityParams modifyLiquidityParams;
        SwapParams swapParams;
        bytes hookData;
    }

    function setUp() public {
        // Deploy PoolManager
        poolManager = new PoolManager(address(this));

        // Deploy mock tokens
        MockERC20 tokenA = new MockERC20("Token A", "TKNA", 18);
        MockERC20 tokenB = new MockERC20("Token B", "TKNB", 18);

        // Sort tokens (currency0 < currency1)
        if (address(tokenA) < address(tokenB)) {
            token0 = tokenA;
            token1 = tokenB;
        } else {
            token0 = tokenB;
            token1 = tokenA;
        }

        // Mint tokens to this contract
        token0.mint(address(this), 1000000e18); // 1M tokens
        token1.mint(address(this), 1000000e18); // 1M tokens

        // Approve PoolManager
        token0.approve(address(poolManager), type(uint256).max);
        token1.approve(address(poolManager), type(uint256).max);

        // Deploy hook implementation
        SimpleLoggingHook hookImpl = new SimpleLoggingHook();

        // Calculate target address with correct permission flags
        uint160 targetFlags = ALL_HOOK_PERMISSIONS;

        // Create target address: clear lower 14 bits and set our flags
        address targetHookAddress = address(uint160(uint256(type(uint160).max) & ~uint160(0x3FFF)) | targetFlags);

        // Use vm.etch to place hook bytecode at the target address
        vm.etch(targetHookAddress, address(hookImpl).code);
        hook = SimpleLoggingHook(targetHookAddress);

        // Verify the address has correct permissions
        uint160 addressFlags = uint160(address(hook)) & uint160(0x3FFF);
        require(addressFlags == ALL_HOOK_PERMISSIONS, "Hook address flags mismatch");

        console.log("Hook deployed at:", address(hook));
        console.log("Hook permissions:", addressFlags);

        // Setup currencies
        Currency currency0 = Currency.wrap(address(token0));
        Currency currency1 = Currency.wrap(address(token1));

        // Create pool key with hook
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });

        poolId = poolKey.toId();
    }

    function test_InitializePoolWithHook() public {
        // Verify hook counts are 0 before initialization
        assertEq(hook.beforeInitializeCount(poolId), 0);
        assertEq(hook.afterInitializeCount(poolId), 0);

        // Initialize the pool
        int24 tick = poolManager.initialize(poolKey, SQRT_PRICE_1_1);

        console.log("Pool initialized at tick:", tick);
        console.log("Pool ID:", uint256(PoolId.unwrap(poolId)));

        // Verify hooks were called
        assertEq(hook.beforeInitializeCount(poolId), 1, "beforeInitialize not called");
        assertEq(hook.afterInitializeCount(poolId), 1, "afterInitialize not called");

        console.log("beforeInitialize count:", hook.beforeInitializeCount(poolId));
        console.log("afterInitialize count:", hook.afterInitializeCount(poolId));
    }

    function test_AddLiquidityWithHook() public {
        // Initialize the pool first
        poolManager.initialize(poolKey, SQRT_PRICE_1_1);

        // Reset counts after initialization
        uint256 beforeAddLiquidityBefore = hook.beforeAddLiquidityCount(poolId);
        uint256 afterAddLiquidityBefore = hook.afterAddLiquidityCount(poolId);

        console.log("Token0 balance:", token0.balanceOf(address(this)));
        console.log("Token1 balance:", token1.balanceOf(address(this)));

        // Add liquidity from tick -600 to +600
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -600,
            tickUpper: 600,
            liquidityDelta: 100e18, // Add 100 units of liquidity
            salt: bytes32(0)
        });

        CallbackData memory data = CallbackData({
            callbackType: CallbackType.ADD_LIQUIDITY,
            key: poolKey,
            modifyLiquidityParams: params,
            swapParams: SwapParams({zeroForOne: false, amountSpecified: 0, sqrtPriceLimitX96: 0}),
            hookData: ""
        });

        // Execute via unlock callback
        bytes memory result = poolManager.unlock(abi.encode(data));
        BalanceDelta delta = abi.decode(result, (BalanceDelta));

        // Verify hooks were called
        assertEq(hook.beforeAddLiquidityCount(poolId), beforeAddLiquidityBefore + 1, "beforeAddLiquidity not called");
        assertEq(hook.afterAddLiquidityCount(poolId), afterAddLiquidityBefore + 1, "afterAddLiquidity not called");

        console.log("Liquidity added successfully");
        console.log("beforeAddLiquidity count:", hook.beforeAddLiquidityCount(poolId));
        console.log("afterAddLiquidity count:", hook.afterAddLiquidityCount(poolId));
        console.logInt(delta.amount0());
        console.logInt(delta.amount1());
    }

    function test_SwapWithHook() public {
        // Initialize the pool
        poolManager.initialize(poolKey, SQRT_PRICE_1_1);

        // First add liquidity
        ModifyLiquidityParams memory liquidityParams =
            ModifyLiquidityParams({tickLower: -600, tickUpper: 600, liquidityDelta: 10000e18, salt: bytes32(0)});

        CallbackData memory addLiquidityData = CallbackData({
            callbackType: CallbackType.ADD_LIQUIDITY,
            key: poolKey,
            modifyLiquidityParams: liquidityParams,
            swapParams: SwapParams({zeroForOne: false, amountSpecified: 0, sqrtPriceLimitX96: 0}),
            hookData: ""
        });

        poolManager.unlock(abi.encode(addLiquidityData));

        // Get swap counts before swap
        uint256 beforeSwapBefore = hook.beforeSwapCount(poolId);
        uint256 afterSwapBefore = hook.afterSwapCount(poolId);

        // Swap: sell 100 token0 for token1
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: -100e18, // Exact input
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        CallbackData memory swapData = CallbackData({
            callbackType: CallbackType.SWAP,
            key: poolKey,
            modifyLiquidityParams: ModifyLiquidityParams({
                tickLower: 0, tickUpper: 0, liquidityDelta: 0, salt: bytes32(0)
            }),
            swapParams: swapParams,
            hookData: ""
        });

        bytes memory result = poolManager.unlock(abi.encode(swapData));
        BalanceDelta delta = abi.decode(result, (BalanceDelta));

        // Verify hooks were called
        assertEq(hook.beforeSwapCount(poolId), beforeSwapBefore + 1, "beforeSwap not called");
        assertEq(hook.afterSwapCount(poolId), afterSwapBefore + 1, "afterSwap not called");

        console.log("Swap executed successfully");
        console.log("beforeSwap count:", hook.beforeSwapCount(poolId));
        console.log("afterSwap count:", hook.afterSwapCount(poolId));
        console.logInt(delta.amount0());
        console.logInt(delta.amount1());
    }

    // IUnlockCallback implementation
    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(poolManager), "Unauthorized");

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        if (data.callbackType == CallbackType.ADD_LIQUIDITY) {
            return _handleAddLiquidity(data);
        } else if (data.callbackType == CallbackType.SWAP) {
            return _handleSwap(data);
        }

        revert("Unknown callback type");
    }

    function _handleAddLiquidity(CallbackData memory data) internal returns (bytes memory) {
        // Modify liquidity
        (BalanceDelta delta,) = poolManager.modifyLiquidity(data.key, data.modifyLiquidityParams, data.hookData);

        // Get the actual deltas from the pool manager
        int256 delta0 = poolManager.currencyDelta(address(this), data.key.currency0);
        int256 delta1 = poolManager.currencyDelta(address(this), data.key.currency1);

        // Settle debts and take credits using CurrencySettler
        if (delta0 < 0) {
            data.key.currency0.settle(poolManager, address(this), uint256(-delta0), false);
        }
        if (delta1 < 0) {
            data.key.currency1.settle(poolManager, address(this), uint256(-delta1), false);
        }
        if (delta0 > 0) {
            data.key.currency0.take(poolManager, address(this), uint256(delta0), false);
        }
        if (delta1 > 0) {
            data.key.currency1.take(poolManager, address(this), uint256(delta1), false);
        }

        return abi.encode(delta);
    }

    function _handleSwap(CallbackData memory data) internal returns (bytes memory) {
        // Execute swap
        BalanceDelta delta = poolManager.swap(data.key, data.swapParams, data.hookData);

        // Get the actual deltas from the pool manager
        int256 delta0 = poolManager.currencyDelta(address(this), data.key.currency0);
        int256 delta1 = poolManager.currencyDelta(address(this), data.key.currency1);

        // Settle debts and take credits using CurrencySettler
        if (delta0 < 0) {
            data.key.currency0.settle(poolManager, address(this), uint256(-delta0), false);
        }
        if (delta1 < 0) {
            data.key.currency1.settle(poolManager, address(this), uint256(-delta1), false);
        }
        if (delta0 > 0) {
            data.key.currency0.take(poolManager, address(this), uint256(delta0), false);
        }
        if (delta1 > 0) {
            data.key.currency1.take(poolManager, address(this), uint256(delta1), false);
        }

        return abi.encode(delta);
    }
}
