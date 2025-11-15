// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IHooks} from "uniswap-v4-core/interfaces/IHooks.sol";
import {PoolKey} from "uniswap-v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "uniswap-v4-core/types/PoolId.sol";
import {BalanceDelta} from "uniswap-v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "uniswap-v4-core/types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "uniswap-v4-core/types/PoolOperation.sol";

/// @title SimpleLoggingHook
/// @notice A simple hook that logs all pool operations and tracks call counts
contract SimpleLoggingHook is IHooks {
    using PoolIdLibrary for PoolKey;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;

    // Track call counts for each pool
    mapping(PoolId => uint256) public beforeInitializeCount;
    mapping(PoolId => uint256) public afterInitializeCount;
    mapping(PoolId => uint256) public beforeSwapCount;
    mapping(PoolId => uint256) public afterSwapCount;
    mapping(PoolId => uint256) public beforeAddLiquidityCount;
    mapping(PoolId => uint256) public afterAddLiquidityCount;
    mapping(PoolId => uint256) public beforeRemoveLiquidityCount;
    mapping(PoolId => uint256) public afterRemoveLiquidityCount;

    // Events for logging
    event BeforeInitialize(address indexed sender, PoolId indexed poolId, uint160 sqrtPriceX96);
    event AfterInitialize(address indexed sender, PoolId indexed poolId, uint160 sqrtPriceX96, int24 tick);
    event BeforeSwap(address indexed sender, PoolId indexed poolId, bool zeroForOne, int256 amountSpecified);
    event AfterSwap(address indexed sender, PoolId indexed poolId, bool zeroForOne, int256 amountSpecified);
    event BeforeAddLiquidity(
        address indexed sender, PoolId indexed poolId, int24 tickLower, int24 tickUpper, int256 liquidityDelta
    );
    event AfterAddLiquidity(
        address indexed sender, PoolId indexed poolId, int24 tickLower, int24 tickUpper, int256 liquidityDelta
    );
    event BeforeRemoveLiquidity(
        address indexed sender, PoolId indexed poolId, int24 tickLower, int24 tickUpper, int256 liquidityDelta
    );
    event AfterRemoveLiquidity(
        address indexed sender, PoolId indexed poolId, int24 tickLower, int24 tickUpper, int256 liquidityDelta
    );

    // ============ IHooks Implementation ============

    function beforeInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96)
        external
        override
        returns (bytes4)
    {
        PoolId poolId = key.toId();
        beforeInitializeCount[poolId]++;
        emit BeforeInitialize(sender, poolId, sqrtPriceX96);
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96, int24 tick)
        external
        override
        returns (bytes4)
    {
        PoolId poolId = key.toId();
        afterInitializeCount[poolId]++;
        emit AfterInitialize(sender, poolId, sqrtPriceX96, tick);
        return IHooks.afterInitialize.selector;
    }

    function beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = key.toId();
        beforeSwapCount[poolId]++;
        emit BeforeSwap(sender, poolId, params.zeroForOne, params.amountSpecified);
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(address sender, PoolKey calldata key, SwapParams calldata params, BalanceDelta, bytes calldata)
        external
        override
        returns (bytes4, int128)
    {
        PoolId poolId = key.toId();
        afterSwapCount[poolId]++;
        emit AfterSwap(sender, poolId, params.zeroForOne, params.amountSpecified);
        return (IHooks.afterSwap.selector, 0);
    }

    function beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata
    ) external override returns (bytes4) {
        PoolId poolId = key.toId();
        beforeAddLiquidityCount[poolId]++;
        emit BeforeAddLiquidity(sender, poolId, params.tickLower, params.tickUpper, params.liquidityDelta);
        return IHooks.beforeAddLiquidity.selector;
    }

    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();
        afterAddLiquidityCount[poolId]++;
        emit AfterAddLiquidity(sender, poolId, params.tickLower, params.tickUpper, params.liquidityDelta);
        return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata
    ) external override returns (bytes4) {
        PoolId poolId = key.toId();
        beforeRemoveLiquidityCount[poolId]++;
        emit BeforeRemoveLiquidity(sender, poolId, params.tickLower, params.tickUpper, params.liquidityDelta);
        return IHooks.beforeRemoveLiquidity.selector;
    }

    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();
        afterRemoveLiquidityCount[poolId]++;
        emit AfterRemoveLiquidity(sender, poolId, params.tickLower, params.tickUpper, params.liquidityDelta);
        return (IHooks.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert("Donate not implemented");
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert("Donate not implemented");
    }
}
