// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {DataTypes} from "../types/DataTypes.sol";

/**
 * @title ValidationLogic
 * @author Rajib Kumar Pradhan
 * @notice Library containing validation checks used throughout the lending pool.
 * @dev Provides reusable validation functions for reserve states and user actions.
 */
library ValidationLogic {
    error ValidationLogic__ReserveInactive();
    error ValidationLogic__NeedsMoreThanZero();

    /**
     * @notice Validates whether a supply operation can be executed.
     * @param reserveCache Cached reserve data required for validation.
     * @param amount The amount of assets being supplied.
     */
    function validateSupply(DataTypes.ReserveCache memory reserveCache, uint256 amount) internal pure {
        validateReserveActive(reserveCache);
        validateAmount(amount);
    }

    /**
     * @notice Validates that an amount is greater than zero.
     * @param amount The amount to validate.
     */
    function validateAmount(uint256 amount) internal pure {
        if (amount == 0) revert ValidationLogic__NeedsMoreThanZero();
    }

    /**
     * @notice Validates that a reserve is active.
     * @param reserveCache Cached reserve data required for validation.
     */
    function validateReserveActive(DataTypes.ReserveCache memory reserveCache) internal pure {
        if (!reserveCache.isActive) revert ValidationLogic__ReserveInactive();
    }
}
