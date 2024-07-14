// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

type Currency is address;

interface IHooks {
    function getHooksRegistrationBitmap() external view returns (uint16);
}

interface IPoolManager {
    /// @notice Thrown when trying to interact with a non-initialized pool
    error PoolNotInitialized();

    /// @notice PoolKey must have currencies where address(currency0) < address(currency1)
    error CurrenciesInitializedOutOfOrder();

    /// @notice Thrown when a call to updateDynamicLPFee is made by an address that is not the hook,
    /// or on a pool is not a dynamic fee pool.
    error UnauthorizedDynamicLPFeeUpdate();

    /// @notice Emitted when lp fee is updated
    /// @dev The event is emitted even if the updated fee value is the same as previous one
    event DynamicLPFeeUpdated(PoolId indexed id, uint24 dynamicLPFee);

    /// @notice Updates lp fee for a dyanmic fee pool
    /// @dev Some of the use case could be:
    ///   1) when hook#beforeSwap() is called and hook call this function to update the lp fee
    ///   2) For BinPool only, when hook#beforeMint() is called and hook call this function to update the lp fee
    ///   3) other use case where the hook might want to on an ad-hoc basis increase/reduce lp fee
    function updateDynamicLPFee(PoolKey memory key, uint24 newDynamicLPFee) external;
}

type PoolId is bytes32;

/// @notice Library for computing the ID of a pool
library PoolIdLibrary {
    function toId(PoolKey memory poolKey) internal pure returns (PoolId poolId) {
        assembly ("memory-safe") {
            poolId := keccak256(poolKey, mul(32, 6))
        }
    }
}

/// @notice Returns the key for identifying a pool
struct PoolKey {
    /// @notice The lower currency of the pool, sorted numerically
    Currency currency0;
    /// @notice The higher currency of the pool, sorted numerically
    Currency currency1;
    /// @notice The hooks of the pool, won't have a general interface because hooks interface vary on pool type
    IHooks hooks;
    /// @notice The pool manager of the pool
    IPoolManager poolManager;
    /// @notice The pool lp fee, capped at 1_000_000. If the pool has a dynamic fee then it must be exactly equal to 0x800000
    uint24 fee;
    /// @notice Hooks callback and pool specific parameters, i.e. tickSpacing for CL, binStep for bin
    bytes32 parameters;
}
