// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {DataTypes} from "../types/DataTypes.sol";
import {ILiquidityToken} from "../interfaces/ILiquidityToken.sol";
import {IDebtToken} from "../interfaces/IDebtToken.sol";
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
    error ValidationLogic__AlreadyBorrowingIs(bool borrowing);
    error ValidationLogic__UnderlyingBalanceIsZero();
    error ValidationLogic__NotUsingAsCollateral();
    error ValidationLogic__TransferFailed();
    error ValidationLogic__NoDebtOfSelectedType();

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
     * @notice Validates whether a borrow operation can be executed.
     * @param reserveCache Cached reserve data required for validation.
     * @param userConfig The user's configuration.
     * @param asset The address of the asset being borrowed.
     * @param amount The amount of the asset to borrow.
     * @param scaledAmount The scaled amount of the asset to borrow.
     * @param healthFactorAfter The user's health factor after the action.
     */
    function validateBorrow(
        DataTypes.ReserveCache memory reserveCache,
        DataTypes.UserConfiguration storage userConfig,
        address asset,
        uint256 amount,
        uint256 scaledAmount,
        uint256 healthFactorAfter
    ) internal view {
        validateReserveActive(reserveCache);
        validateAmount(scaledAmount);
        if (!userConfig.hasCollateral()) revert ValidationLogic__NotUsingAsCollateral();
        validateUserHealthFactorAfterAction(healthFactorAfter);
        validatePoolLiquidity(asset, amount);
    }

    /**
     * @notice Validates whether a repay operation can be executed.
     * @param reserveCache Cached reserve data required for validation.
     * @param scaledDebt scaledDebt user want to repay.
     */
    function validateRepay(DataTypes.ReserveCache memory reserveCache, uint256 scaledDebt) internal pure {
        validateReserveActive(reserveCache);
        validateAmount(scaledDebt);
    }

    /**
     * @notice Validates whether a liquidation operation can be executed.
     * @param collateralCache The cache for the collateral asset.
     * @param debtCache The cache for the debt asset.
     * @param userConfig The user's configuration.
     * @param user The address of the user being liquidated.
     * @param collateralReserveId The ID of the collateral reserve.
     * @param healthFactorAfter The user's health factor after the action.
     */
    function validateLiquidation(
        DataTypes.ReserveCache memory collateralCache,
        DataTypes.ReserveCache memory debtCache,
        DataTypes.UserConfiguration storage userConfig,
        address user,
        uint256 collateralReserveId,
        uint256 healthFactorAfter
    ) internal view {
        validateReserveActive(collateralCache);
        validateReserveActive(debtCache);
        validateUserHealthFactorAfterAction(healthFactorAfter);
        if (!userConfig.isCollateral(collateralReserveId)) revert ValidationLogic__NotUsingAsCollateral();
        if (IDebtToken(debtCache.debtTokenAddress).balanceOf(user) == 0) {
            revert ValidationLogic__NoDebtOfSelectedType();
        }
    }

    /**
     * @notice Validates the setting of a reserve as collateral.
     * @param reserve The reserve data.
     * @param useAsCollateral The flag indicating if the reserve should be used as collateral.
     */
    function validateSetUseAsCollateral(DataTypes.ReserveData storage reserve, bool useAsCollateral) internal view {
        if (!reserve.isActive) revert ValidationLogic__ReserveInactive();
        if (ILiquidityToken(reserve.liquidityTokenAddress).scaledBalanceOf(msg.sender) == 0 && useAsCollateral) {
            revert ValidationLogic__UnderlyingBalanceIsZero();
        }
    }

    /**
     * @notice Validates the transfer of liquidity tokens.
     * @param reserveCache Cached reserve data required for validation.
     * @param from The address tokens are transferred from.
     * @param scaledDebt The scaled debt of the user.
     * @param healthFactorAfter The user's health factor after the action.
     */
    function validateTransferLiquidityToken(
        DataTypes.ReserveCache memory reserveCache,
        address from,
        uint256 scaledDebt,
        uint256 healthFactorAfter
    ) internal view {
        validateReserveActive(reserveCache);
        validateUserHealthFactorAfterAction(healthFactorAfter);
        validateTransferLiquidityTokenInternal(scaledDebt, reserveCache.liquidityTokenAddress, from);
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
    function validateSetUseAsCollateralInternal(
        uint256 reserveId,
        DataTypes.UserConfiguration storage userConfig,
        bool useAsCollateral
    ) internal view {
        if (useAsCollateral == userConfig.isCollateral(reserveId)) {
            revert ValidationLogic__AlreadyUsingAsCollateralIs(useAsCollateral);
        }
    }

    /**
     * @notice Validates the setting of a reserve as borrowing.
     * @param reserveId The ID of the reserve.
     * @param userConfig The user's configuration.
     * @param borrowing The flag indicating if the reserve should be set as borrowing.
     */
    function validateSetAsBorrowing(uint256 reserveId, DataTypes.UserConfiguration storage userConfig, bool borrowing)
        internal
        view
    {
        if (borrowing == userConfig.isBorrowing(reserveId)) {
            revert ValidationLogic__AlreadyBorrowingIs(borrowing);
        }
    }

    /**
     * @notice Validates the internal transfer of liquidity tokens.
     * @param scaledDebt The scaled debt of the user.
     * @param liquidityTokenAddress The address of the liquidity token.
     * @param from The address of the user transferring the tokens.
     */
    function validateTransferLiquidityTokenInternal(uint256 scaledDebt, address liquidityTokenAddress, address from)
        internal
        view
    {
        validateAmount(scaledDebt);
        validateUserHaveEnoughBalance(ILiquidityToken(liquidityTokenAddress).scaledBalanceOf(from), scaledDebt);
    }

    /**
     * @notice Validates the successful transfer of liquidity tokens.
     * @param success The success status of the transfer.
     */
    function validateTransferLiquidityTokenSuccessful(bool success) internal pure {
        if (!success) revert ValidationLogic__TransferFailed();
    }
}
