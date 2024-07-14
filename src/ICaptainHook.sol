// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {PoolKey} from "./PancakeV4Structs.sol";

interface ICaptainHook {
    function depositCollateral(PoolKey memory key, uint256 amount) external;
}