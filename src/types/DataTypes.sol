// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/**
 * @title Math
 * @author Rajib Kumar Pradhan
 * @notice Collection data types used throughout the lending protocol.
 */
library DataTypes {
    struct InterestRateParams {
        // The utilization ratio at which the interest rate model changes slope
        uint256 optimalUsageRatio;
        // The minimum borrow rate
        uint256 baseBorrowRate;
        // The rate increase applied below the optimal utilization
        uint256 variableRateSlope1;
        // The rate increase applied above the optimal utilization
        uint256 variableRateSlope2;
    }

    struct ReserveData {
        // the liquidity index. Expressed in ray
        uint128 liquidityIndex;
        // borrow index. Expressed in ray
        uint128 borrowIndex;

        // the current supply rate. Expressed in ray
        uint128 currentLiquidityRate;
        // the current borrow rate. Expressed in ray
        uint128 currentBorrowRate;

        // the liquidation threshold
        uint16 liquidationThreshold;
        // the liquidation bonus
        uint16 liquidationBonus;
        // the reserve factor
        uint16 reserveFactor;
        // timestamp of last update
        uint40 lastUpdate;
        // reserve is active
        bool isActive;

        // liquidityToken address
        address liquidityTokenAddress;
        // debtToken address
        address debtTokenAddress;
    }

    struct ReserveCache {
        uint256 liquidityIndex;
        uint256 borrowIndex;

        // updated liquidity index
        uint256 nextLiquidityIndex;
        // updated borrow index
        uint256 nextBorrowIndex;

        uint256 currentLiquidityRate;
        uint256 currentBorrowRate;

        uint40 lastUpdate;
        bool isActive;

        uint256 reserveFactor;
        uint256 liquidationBonus;

        address liquidityTokenAddress;
        address debtTokenAddress;
    }

    struct FeedData {
        // The Chainlink price feed contract address
        address priceFeedAddress;
        // The number of decimals used by the price feed
        uint8 feedDecimals;
        // The number of decimals used by the underlying token
        uint8 tokenDecimals;
    }

    struct UserConfiguration {
        /**
         * @dev Bitmap of the users collaterals and borrows. It is divided in pairs of bits, one pair per asset.
         * The first bit indicates if an asset is used as collateral by the user, the second whether an
         * asset is borrowed by the user.
         */
        uint256 data;
    }
}
