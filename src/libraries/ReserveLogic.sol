// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Math} from "./Math.sol";
import {InterestRateModel} from "./InterestRateModel.sol";
import {DataTypes} from "../types/DataTypes.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

/**
 * @title ReserveLogic
 * @author Rajib Kumar Pradhan
 * @notice Implements the logic to update the reserves state
 */
library ReserveLogic {
    error ReserveAlreadyInitialized();

    using Math for uint256;
    using InterestRateModel for uint256;
    using SafeCast for uint256;

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

    /**
     * @notice Initializes a reserve with its associated tokens and risk parameters.
     * @dev Can only be called once for a reserve. Sets the initial liquidity and borrow
     *      indexes to 1 ray and activates the reserve.
     * @param reserve The reserve data storage object to initialize.
     * @param liquidityTokenAddress The address of the token representing supplied liquidity.
     * @param debtTokenAddress The address of the token representing borrower debt.
     * @param liquidationThreshold The maximum collateralization threshold used for liquidation checks.
     * @param liquidationBonus The bonus applied to liquidators when liquidating collateral.
     * @param reserveFactor The portion of interest allocated to the protocol treasury.
     */
    function initReserve(
        DataTypes.ReserveData storage reserve,
        address liquidityTokenAddress,
        address debtTokenAddress,
        uint16 liquidationThreshold,
        uint16 liquidationBonus,
        uint16 reserveFactor
    ) internal {
        if (reserve.liquidityTokenAddress != address(0)) {
            revert ReserveAlreadyInitialized();
        }

        reserve.liquidityIndex = Math.RAY.toUint128();
        reserve.borrowIndex = Math.RAY.toUint128();
        reserve.liquidityTokenAddress = liquidityTokenAddress;
        reserve.debtTokenAddress = debtTokenAddress;

        reserve.liquidationThreshold = liquidationThreshold;
        reserve.liquidationBonus = liquidationBonus;
        reserve.reserveFactor = reserveFactor;

        reserve.isActive = true;
    }
}
