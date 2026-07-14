// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Math} from "./Math.sol";
import {DataTypes} from "../types/DataTypes.sol";

/**
 * @title InterestRateModel
 * @author Rajib Kumar Pradhan
 * @notice Calculates borrow and liquidity interest rates based on pool utilization.
 */
library InterestRateModel {
    using Math for uint256;

    /**
     * @notice Calculates the utilization ratio of the lending pool.
     * @param totalLiquidityPlusDebt Total pool liquidity, including borrowed funds.
     * @param totalDebt Total outstanding borrowed amount.
     * @return The utilization ratio in WAD precision.
     */
    function calculateUtilization(uint256 totalLiquidityPlusDebt, uint256 totalDebt) internal pure returns (uint256) {
        if (totalLiquidityPlusDebt == 0) {
            return 0;
        }

        return totalDebt.rayDiv(totalLiquidityPlusDebt);
    }

    /**
     * @notice Calculates the current borrow rate using a two-slope interest rate model.
     * @param totalLiquidityPlusDebt Total pool liquidity, including borrowed funds.
     * @param totalDebt Total outstanding borrowed amount.
     * @param interestRateParams Interest rate model configuration.
     * @return borrowRate The borrow rate in RAY precision.
     */
    function calculateBorrowRate(
        uint256 totalLiquidityPlusDebt,
        uint256 totalDebt,
        DataTypes.InterestRateParams memory interestRateParams
    ) internal pure returns (uint256 borrowRate) {
        uint256 utilization = calculateUtilization(totalLiquidityPlusDebt, totalDebt);

        borrowRate = _borrowRate(utilization, interestRateParams);
    }

    /**
     * @notice Calculates the liquidity rate earned by suppliers.
     * @param totalLiquidityPlusDebt Total pool liquidity, including borrowed funds.
     * @param totalDebt Total outstanding borrowed amount.
     * @param reserveFactor Fraction of interest retained by the protocol, in bps.
     * @param interestRateParams Interest rate model configuration.
     * @return liquidityRate The liquidity rate in RAY precision.
     */
    function calculateLiquidityRate(
        uint256 totalLiquidityPlusDebt,
        uint256 totalDebt,
        uint16 reserveFactor,
        DataTypes.InterestRateParams memory interestRateParams
    ) internal pure returns (uint256 liquidityRate) {
        uint256 utilization = calculateUtilization(totalLiquidityPlusDebt, totalDebt);
        uint256 borrowRate = _borrowRate(utilization, interestRateParams);

        liquidityRate = _liquidityRate(utilization, borrowRate, reserveFactor);
    }

    /**
     * @notice Calculates both the borrow and liquidity rates for the pool.
     * @param totalLiquidityPlusDebt Total pool liquidity, including borrowed funds.
     * @param totalDebt Total outstanding borrowed amount.
     * @param reserveFactor Fraction of interest retained by the protocol, in bps.
     * @param interestRateParams Interest rate model configuration.
     * @return borrowRate The borrow rate in RAY precision.
     * @return liquidityRate The liquidity rate in RAY precision.
     */
    function calculateInterestRates(
        uint256 totalLiquidityPlusDebt,
        uint256 totalDebt,
        uint16 reserveFactor,
        DataTypes.InterestRateParams memory interestRateParams
    ) internal pure returns (uint256 borrowRate, uint256 liquidityRate) {
        uint256 utilization = calculateUtilization(totalLiquidityPlusDebt, totalDebt);

        borrowRate = _borrowRate(utilization, interestRateParams);
        liquidityRate = _liquidityRate(utilization, borrowRate, reserveFactor);
    }

    /**
     * @dev Computes the borrow rate from the utilization ratio.
     */
    function _borrowRate(uint256 utilization, DataTypes.InterestRateParams memory params)
        internal
        pure
        returns (uint256 borrowRate)
    {
        if (utilization < params.optimalUsageRatio) {
            borrowRate =
                params.baseBorrowRate + utilization.rayMul(params.variableRateSlope1).rayDiv(params.optimalUsageRatio);
        } else {
            uint256 excessRatio = (utilization - params.optimalUsageRatio).rayDiv(Math.RAY - params.optimalUsageRatio);

            borrowRate =
                params.baseBorrowRate + params.variableRateSlope1 + excessRatio.rayMul(params.variableRateSlope2);
        }
    }

    /**
     * @dev Computes the liquidity rate from the borrow rate and utilization.
     */
    function _liquidityRate(uint256 utilization, uint256 borrowRate, uint16 reserveFactor)
        internal
        pure
        returns (uint256)
    {
        return borrowRate.rayMul(utilization).percentageMul(Math.PERCENTAGE_FACTOR - reserveFactor);
    }
}
