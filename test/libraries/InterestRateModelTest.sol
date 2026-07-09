// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {InterestRateModel} from "../../src/libraries/InterestRateModel.sol";
import {Math} from "../../src/libraries/Math.sol";
import {DataTypes} from "../../src/types/DataTypes.sol";

contract InterestRateModelTest is Test {
    using InterestRateModel for uint256;
    using Math for uint256;

    DataTypes.InterestRateParams params;
    uint16 reserveFactor = 1_000;

    uint256 constant OPTIAML_USAGE_RATIO = 80e25;
    uint256 constant BASE_BORROW_RATE = 0;
    uint256 constant VARIABLE_RATE_SLOPE_1 = 4e25;
    uint256 constant VARIABLE_RATE_SLOPE_2 = 60e25;

    function setUp() public {
        params = DataTypes.InterestRateParams(
            OPTIAML_USAGE_RATIO, BASE_BORROW_RATE, VARIABLE_RATE_SLOPE_1, VARIABLE_RATE_SLOPE_2
        );
    }

    //////////////////////////////////////
    // Calculate Utilization Tests      //
    //////////////////////////////////////
    function testCalculateUtilizationReturnZeroLiqPlusDebtIsZero() public pure {
        assertEq(0, InterestRateModel.calculateUtilization(0, 1e27));
    }

    function testCalculateUtilization(uint256 totalLiquidityPlusDebt, uint256 totalDebt) public pure {
        totalLiquidityPlusDebt = bound(totalLiquidityPlusDebt, 1e8, type(uint96).max);
        totalDebt = bound(totalDebt, 0, totalLiquidityPlusDebt);

        uint256 utilization = totalLiquidityPlusDebt.calculateUtilization(totalDebt);
        uint256 expectedUtilization = totalDebt.rayDiv(totalLiquidityPlusDebt);

        assertEq(utilization, expectedUtilization);
    }

    ////////////////////////////
    // Borrow Rate Tests      //
    ////////////////////////////
    function testBorrowRate(uint256 totalLiquidityPlusDebt, uint256 totalDebt) public view {
        totalLiquidityPlusDebt = bound(totalLiquidityPlusDebt, 1e8, type(uint96).max);
        totalDebt = bound(totalDebt, 0, totalLiquidityPlusDebt);

        uint256 utilization = totalLiquidityPlusDebt.calculateUtilization(totalDebt);
        uint256 borrowRate = utilization._borrowRate(params);

        uint256 expectedBorrowRate;
        if (utilization < params.optimalUsageRatio) {
            expectedBorrowRate =
                params.baseBorrowRate + utilization.rayMul(params.variableRateSlope1).rayDiv(params.optimalUsageRatio);
        } else {
            uint256 excessRatio = (utilization - params.optimalUsageRatio).rayDiv(Math.RAY - params.optimalUsageRatio);

            expectedBorrowRate =
                params.baseBorrowRate + params.variableRateSlope1 + excessRatio.rayMul(params.variableRateSlope2);
        }

        assertEq(borrowRate, expectedBorrowRate);
    }

    function testCalculateBorrowRate(uint256 totalLiquidityPlusDebt, uint256 totalDebt) public view {
        totalLiquidityPlusDebt = bound(totalLiquidityPlusDebt, 1e8, type(uint96).max);
        totalDebt = bound(totalDebt, 0, totalLiquidityPlusDebt);

        uint256 calculateBorrowRate = totalLiquidityPlusDebt.calculateBorrowRate(totalDebt, params);
        uint256 utilization = totalLiquidityPlusDebt.calculateUtilization(totalDebt);

        uint256 expectedCalculateBorrowRate = utilization._borrowRate(params);

        assertEq(calculateBorrowRate, expectedCalculateBorrowRate);
    }

    ///////////////////////////////
    // Liquidity Rate Tests      //
    ///////////////////////////////
    function testLiquidityRate(uint256 totalLiquidityPlusDebt, uint256 totalDebt) public view {
        totalLiquidityPlusDebt = bound(totalLiquidityPlusDebt, 1e8, type(uint96).max);
        totalDebt = bound(totalDebt, 0, totalLiquidityPlusDebt);

        uint256 utilization = totalLiquidityPlusDebt.calculateUtilization(totalDebt);
        uint256 borrowRate = utilization._borrowRate(params);

        uint256 liquidityRate = utilization._liquidityRate(borrowRate, reserveFactor);

        uint256 expectedLiquidityRate =
            borrowRate.rayMul(utilization).percentageMul(Math.PERCENTAGE_FACTOR - reserveFactor);

        assertEq(liquidityRate, expectedLiquidityRate);
    }

    function testCalculateLiquidityRate(uint256 totalLiquidityPlusDebt, uint256 totalDebt) public view {
        totalLiquidityPlusDebt = bound(totalLiquidityPlusDebt, 1e8, type(uint96).max);
        totalDebt = bound(totalDebt, 0, totalLiquidityPlusDebt);

        uint256 calculateLiquidityRate = totalLiquidityPlusDebt.calculateLiquidityRate(totalDebt, reserveFactor, params);

        uint256 utilization = totalLiquidityPlusDebt.calculateUtilization(totalDebt);
        uint256 borrowRate = utilization._borrowRate(params);
        uint256 expectedCalculateLiquidityRate = utilization._liquidityRate(borrowRate, reserveFactor);

        assertEq(calculateLiquidityRate, expectedCalculateLiquidityRate);
    }

    ///////////////////////////////
    // Interest Rates Tests      //
    ///////////////////////////////
    function testCalculateInterestRates(uint256 totalLiquidityPlusDebt, uint256 totalDebt) public view {
        totalLiquidityPlusDebt = bound(totalLiquidityPlusDebt, 1e8, type(uint96).max);
        totalDebt = bound(totalDebt, 0, totalLiquidityPlusDebt);

        (uint256 borrowRate, uint256 liquidityRate) =
            totalLiquidityPlusDebt.calculateInterestRates(totalDebt, reserveFactor, params);

        uint256 expectedBorrowRate = totalLiquidityPlusDebt.calculateBorrowRate(totalDebt, params);
        uint256 expectedLiquidityRate = totalLiquidityPlusDebt.calculateLiquidityRate(totalDebt, reserveFactor, params);

        assertEq(borrowRate, expectedBorrowRate);
        assertEq(liquidityRate, expectedLiquidityRate);
    }
}
