// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Math} from "./Math.sol";
import {InterestRateModel} from "./InterestRateModel.sol";
import {DataTypes} from "../types/DataTypes.sol";
import {DebtToken} from "../protocol/DebtToken.sol";
import {LiquidityToken} from "../protocol/LiquidityToken.sol";
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
            return Math.calculateCompoundedInterest(reserve.currentBorrowRate, timestamp).rayMul(reserve.borrowIndex);
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

    /**
     * @notice Updates the reserve indexes and last update timestamp.
     * @dev Accrues interest since the last reserve update and updates the liquidity and borrow indexes.
     *      If the reserve was already updated in the current block, no changes are applied.
     * @param reserve The reserve data storage object to update.
     * @param reserveCache The cached reserve data used during the update process.
     */
    function updateState(DataTypes.ReserveData storage reserve, DataTypes.ReserveCache memory reserveCache) internal {
        uint40 timestamp = block.timestamp.toUint40();
        if (reserveCache.lastUpdate == timestamp) {
            return;
        }

        _updateIndexes(reserve, reserveCache);

        reserve.lastUpdate = timestamp;
        reserveCache.lastUpdate = timestamp;
    }

    /**
     * @notice Recalculates and updates the reserve's liquidity and borrow interest rates.
     * @dev Computes the next utilization ratio using the current scaled liquidity and debt, adjusted for
     *      liquidity added to or removed from the reserve. The updated utilization is passed to the
     *      interest rate model to derive the new liquidity and borrow rates, which are then stored in the reserve.
     * @param reserve The reserve data storage object to update.
     * @param reserveCache A cached copy of the reserve state
     * @param liquidityAdded The amount of underlying liquidity added to the reserve.
     * @param liquidityTaken The amount of underlying liquidity removed from the reserve.
     * @param interestRateParams The parameters required by the interest rate model to compute the
     *        next liquidity and borrow rates.
     */
    function updateInterestRates(
        DataTypes.ReserveData storage reserve,
        DataTypes.ReserveCache memory reserveCache,
        uint256 liquidityAdded,
        uint256 liquidityTaken,
        DataTypes.InterestRateParams memory interestRateParams
    ) internal {
        uint256 scaledDebtToken = DebtToken(reserveCache.debtTokenAddress).scaledTotalSupply();
        uint256 scaledLiquidityToken = LiquidityToken(reserveCache.liquidityTokenAddress).scaledTotalSupply();

        uint256 nextTotalLiquidity =
            scaledLiquidityToken.rayDiv(reserveCache.liquidityIndex) + liquidityAdded - liquidityTaken;

        uint256 nextTotalDebt = scaledDebtToken.rayDiv(reserveCache.borrowIndex);
        uint256 nextTotalLiquidityPlusDebt = nextTotalLiquidity + nextTotalDebt;

        (uint256 nextLiquidityRate, uint256 nextBorrowRate) = nextTotalLiquidityPlusDebt.calculateInterestRates(
            nextTotalDebt, reserveCache.reserveFactor.toUint16(), interestRateParams
        );

        reserve.currentLiquidityRate = nextLiquidityRate.toUint128();
        reserve.currentBorrowRate = nextBorrowRate.toUint128();
    }

    /**
     * @notice Updates the reserve liquidity and borrow indexes by applying accrued interest.
     * @dev Calculates linear interest from the last reserve update timestamp and updates the stored indexes.
     *      If the reserve was already updated in the current block, no update is performed.
     * @param reserve The reserve data storage object containing the current indexes and rates.
     * @param reserveCache The cached reserve data used to store the next calculated indexes.
     */
    function _updateIndexes(DataTypes.ReserveData storage reserve, DataTypes.ReserveCache memory reserveCache)
        internal
    {
        uint40 timestamp = reserve.lastUpdate;

        // forge-lint: disable-next-line(block-timestamp)
        if (timestamp == block.timestamp) {
            return;
        } else {
            reserveCache.nextLiquidityIndex =
                Math.calculateLinearInterest(reserve.currentLiquidityRate, timestamp).rayMul(reserve.liquidityIndex);
            reserve.liquidityIndex = reserveCache.nextLiquidityIndex.toUint128();

            reserveCache.nextBorrowIndex =
                Math.calculateCompoundedInterest(reserve.currentBorrowRate, timestamp).rayMul(reserve.borrowIndex);
            reserve.borrowIndex = reserveCache.nextBorrowIndex.toUint128();
        }
    }

    /**
     * @notice Creates a cached copy of the reserve data.
     * @dev Copies frequently accessed reserve parameters into memory.
     * @param reserve The reserve data storage object to cache.
     * @return reserveCache A memory copy containing reserve indexes, rates, token addresses, risk parameters,
     *         activation status, and last update timestamp.
     */
    function cache(DataTypes.ReserveData storage reserve) internal view returns (DataTypes.ReserveCache memory) {
        DataTypes.ReserveCache memory reserveCache;

        reserveCache.liquidityIndex = reserveCache.nextLiquidityIndex = reserve.liquidityIndex;
        reserveCache.borrowIndex = reserveCache.nextBorrowIndex = reserve.borrowIndex;

        reserveCache.currentLiquidityRate = reserve.currentLiquidityRate;
        reserveCache.currentBorrowRate = reserve.currentBorrowRate;

        reserveCache.liquidityTokenAddress = reserve.liquidityTokenAddress;
        reserveCache.debtTokenAddress = reserve.debtTokenAddress;

        reserveCache.reserveFactor = reserve.reserveFactor;
        reserveCache.liquidationBonus = reserve.liquidationBonus;

        reserveCache.isActive = reserve.isActive;
        reserveCache.lastUpdate = reserve.lastUpdate;

        return reserveCache;
    }
}
