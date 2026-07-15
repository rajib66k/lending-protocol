// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {DataTypes} from "../types/DataTypes.sol";
import {ILiquidityToken} from "../interfaces/ILiquidityToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UserConfiguration} from "../configuration/UserConfiguration.sol";

/**
 * @title ValidationLogic
 * @author Rajib Kumar Pradhan
 * @notice Library containing validation checks used throughout the lending pool.
 * @dev Provides reusable validation functions for reserve states and user actions.
 */
library ValidationLogic {
    error ValidationLogic__ReserveInactive();
    error ValidationLogic__NeedsMoreThanZero();
    error ValidationLogic__UserHasNotEnoughBalance();
    error ValidationLogic__BreaksHealthFactor();
    error ValidationLogic__PoolHasNotEnoughLiquidity();
    error ValidationLogic__AlreadyUsingAsCollateralIs(bool useAsCollateral);

    using UserConfiguration for DataTypes.UserConfiguration;

    uint256 internal constant MIN_HEALTH_FACTOR = 1e18;

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
     * @notice Validates whether a withdraw operation can be executed.
     * @param reserveCache Cached reserve data required for validation.
     * @param user The address of the user.
     * @param asset The address of the asset.
     * @param amount The amount of assets being withdrawn.
     * @param scaledAmount The scaled amount of assets being withdrawn.
     * @param healthFactorAfter The user's health factor after the action.
     */
    function validateWithdraw(
        DataTypes.ReserveCache memory reserveCache,
        address user,
        address asset,
        uint256 amount,
        uint256 scaledAmount,
        uint256 healthFactorAfter
    ) internal view {
        validateReserveActive(reserveCache);
        validateAmount(scaledAmount);
        validateUserHaveEnoughBalance(
            ILiquidityToken(reserveCache.liquidityTokenAddress).scaledBalanceOf(user), scaledAmount
        );
        validateUserHealthFactorAfterAction(healthFactorAfter);
        validatePoolLiquidity(asset, amount);
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

    /**
     * @notice Validates that a user has enough balance for a transaction.
     * @param userBalance The user's current balance.
     * @param amount The amount to validate.
     */
    function validateUserHaveEnoughBalance(uint256 userBalance, uint256 amount) internal pure {
        if (userBalance < amount) revert ValidationLogic__UserHasNotEnoughBalance();
    }

    /**
     * @notice Validates that a user's health factor is sufficient after an action.
     * @param healthFactorAfter The user's health factor after the action.
     */
    function validateUserHealthFactorAfterAction(uint256 healthFactorAfter) internal pure {
        if (healthFactorAfter < MIN_HEALTH_FACTOR) revert ValidationLogic__BreaksHealthFactor();
    }

    /**
     * @notice Validates the liquidity of the pool for a given asset and amount.
     * @param asset The address of the asset.
     * @param amount The amount to validate.
     */
    function validatePoolLiquidity(address asset, uint256 amount) internal view {
        uint256 poolBalance = IERC20(asset).balanceOf(address(this));
        if (poolBalance < amount) revert ValidationLogic__PoolHasNotEnoughLiquidity();
    }

    /**
     * @notice Validates the setting of a reserve as collateral.
     * @param reserveId The ID of the reserve.
     * @param userConfig The user's configuration.
     * @param useAsCollateral The flag indicating if the reserve should be used as collateral.
     */
    function validateSetUseAsCollateral(
        uint256 reserveId,
        DataTypes.UserConfiguration storage userConfig,
        bool useAsCollateral
    ) internal view {
        if (useAsCollateral == userConfig.isCollateral(reserveId)) {
            revert ValidationLogic__AlreadyUsingAsCollateralIs(useAsCollateral);
        }
    }
}
