// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Math} from "./Math.sol";
import {InterestRateModel} from "./InterestRateModel.sol";
import {DataTypes} from "../types/DataTypes.sol";

/**
 * @title ReserveLogic
 * @author Rajib Kumar Pradhan
 * @notice Implements the logic to update the reserves state
 */
library ReserveLogic {
    using Math for uint256;
    using InterestRateModel for uint256;

    /**
     * @notice Returns the current normalized liquidity index of the reserve.
     * @dev If the reserve was already updated in the current block, the stored liquidity index is returned.
     *      Otherwise, linear interest accrued since the last update is applied.
     * @param reserve The reserve data.
     * @return The normalized liquidity index, expressed in ray.
     */
    function getReserveNormalizedIncome(DataTypes.ReserveData storage reserve) internal view returns (uint256) {
        uint40 timestamp = reserve.lastUpdate;

        // forge-lint: disable-next-line(block-timestamp)
        if (timestamp == block.timestamp) {
            return reserve.liquidityIndex;
        } else {
            return Math.calculateLinearInterest(reserve.currentLiquidityRate, timestamp).rayMul(reserve.liquidityIndex);
        }
    }

    /**
     * @notice Returns the current normalized borrow index of the reserve.
     * @dev If the reserve was already updated in the current block, the stored borrow index is returned.
     *      Otherwise, linear interest accrued since the last update is applied.
     * @param reserve The reserve data.
     * @return The normalized borrow index, expressed in ray.
     */
    function getReserveNormalizedDebt(DataTypes.ReserveData storage reserve) internal view returns (uint256) {
        uint40 timestamp = reserve.lastUpdate;

        // forge-lint: disable-next-line(block-timestamp)
        if (timestamp == block.timestamp) {
            return reserve.borrowIndex;
        } else {
            return Math.calculateLinearInterest(reserve.currentBorrowRate, timestamp).rayMul(reserve.borrowIndex);
        }
    }
}
