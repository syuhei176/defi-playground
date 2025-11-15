// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

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
import {TickMath} from "uniswap-v4-core/libraries/TickMath.sol";
import {ModifyLiquidityParams, SwapParams} from "uniswap-v4-core/types/PoolOperation.sol";
import {CurrencySettler} from "../lib/uniswap-v4-core/test/utils/CurrencySettler.sol";
import {TransientStateLibrary} from "uniswap-v4-core/libraries/TransientStateLibrary.sol";

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

contract UniswapV4PoolTest is Test, IUnlockCallback {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;
    using TransientStateLibrary for IPoolManager;

    // Contracts
    IPoolManager public poolManager;
    MockERC20 public usdc;
    MockERC20 public weth;

    PoolKey public poolKey;
    PoolId public poolId;

    // Constants
    uint160 public constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint24 public constant FEE = 3000; // 0.3%
    int24 public constant TICK_SPACING = 60;

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
        // Deploy PoolManager (no fork needed)
        poolManager = new PoolManager(address(this));

        // Deploy mock tokens (both with 18 decimals for simplicity)
        MockERC20 tokenA = new MockERC20("USD Coin", "USDC", 18);
        MockERC20 tokenB = new MockERC20("Wrapped Ether", "WETH", 18);

        // Sort tokens (currency0 < currency1)
        if (address(tokenA) < address(tokenB)) {
            usdc = tokenA;
            weth = tokenB;
        } else {
            usdc = tokenB;
            weth = tokenA;
        }

        // Mint tokens to this contract
        usdc.mint(address(this), 1000000e18); // 1M USDC
        weth.mint(address(this), 1000000e18); // 1M WETH

        // Approve PoolManager
        usdc.approve(address(poolManager), type(uint256).max);
        weth.approve(address(poolManager), type(uint256).max);

        // Setup currencies
        Currency currency0 = Currency.wrap(address(usdc));
        Currency currency1 = Currency.wrap(address(weth));

        // Create pool key
        poolKey = PoolKey({
            currency0: currency0, currency1: currency1, fee: FEE, tickSpacing: TICK_SPACING, hooks: IHooks(address(0))
        });

        poolId = poolKey.toId();
    }

    function test_SwapOnPool() public {
        // Initialize the pool
        poolManager.initialize(poolKey, SQRT_PRICE_1_1);

        // Add liquidity to the pool
        // Use smaller liquidity to avoid token balance issues
        ModifyLiquidityParams memory liquidityParams = ModifyLiquidityParams({
            tickLower: -600,
            tickUpper: 600,
            liquidityDelta: 10e18, // Smaller liquidity amount
            salt: bytes32(0)
        });

        CallbackData memory addLiquidityData = CallbackData({
            callbackType: CallbackType.ADD_LIQUIDITY,
            key: poolKey,
            modifyLiquidityParams: liquidityParams,
            swapParams: SwapParams({zeroForOne: false, amountSpecified: 0, sqrtPriceLimitX96: 0}),
            hookData: ""
        });

        poolManager.unlock(abi.encode(addLiquidityData));

        console.log("Testing swap on USDC-WETH pool");
        console.log("Pool ID:", uint256(PoolId.unwrap(poolId)));

        // Record balances before swap
        uint256 usdcBefore = usdc.balanceOf(address(this));
        uint256 wethBefore = weth.balanceOf(address(this));

        console.log("USDC balance before:", usdcBefore);
        console.log("WETH balance before:", wethBefore);

        // Swap: sell 10 USDC for WETH (small amount to not impact existing pool)
        bool zeroForOne = address(usdc) < address(weth);
        int256 amountSpecified = zeroForOne ? -int256(10e6) : int256(10e6); // Exact input: 10 USDC

        SwapParams memory swapParams = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
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

        uint256 usdcAfter = usdc.balanceOf(address(this));
        uint256 wethAfter = weth.balanceOf(address(this));

        console.log("Swap executed successfully on existing pool");
        console.log("USDC balance after:", usdcAfter);
        console.log("WETH balance after:", wethAfter);

        if (zeroForOne) {
            console.log("USDC spent:", usdcBefore - usdcAfter);
            console.log("WETH received:", wethAfter - wethBefore);
        } else {
            console.log("WETH spent:", wethBefore - wethAfter);
            console.log("USDC received:", usdcAfter - usdcBefore);
        }
        console.logInt(delta.amount0());
        console.logInt(delta.amount1());

        // Verify we received tokens
        if (zeroForOne) {
            assertGt(wethAfter, wethBefore, "Should receive WETH");
            assertLt(usdcAfter, usdcBefore, "Should spend USDC");
        } else {
            assertGt(usdcAfter, usdcBefore, "Should receive USDC");
            assertLt(wethAfter, wethBefore, "Should spend WETH");
        }
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
