// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {DataTypes} from "../types/DataTypes.sol";
import {ReserveLogic} from "../libraries/ReserveLogic.sol";
import {ValidationLogic} from "../libraries/ValidationLogic.sol";
import {Math} from "../libraries/Math.sol";
import {IPool} from "../interfaces/IPool.sol";
import {OracleLib} from "../libraries/OracleLib.sol";
import {ILiquidityToken} from "../interfaces/ILiquidityToken.sol";
import {IDebtToken} from "../interfaces/IDebtToken.sol";
import {UserConfiguration} from "../configuration/UserConfiguration.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title Pool
 * @author Rajib Kumar Pradhan
 * @notice Core lending pool contract responsible for handling user interactions.
 * @dev Currently implements the supply, withdrawals, borrowing, repayment, and liquidation operations.
 */
abstract contract Pool is IPool, ReentrancyGuard, Ownable {
    using ReserveLogic for DataTypes.ReserveData;
    using ValidationLogic for DataTypes.ReserveData;
    using ValidationLogic for DataTypes.ReserveCache;
    using ValidationLogic for uint256;
    using ValidationLogic for bool;
    using OracleLib for AggregatorV3Interface;
    using Math for uint256;
    using SafeERC20 for IERC20;
    using UserConfiguration for DataTypes.UserConfiguration;

    /// @notice Interest rate configuration for each supported reserve.
    mapping(address asset => DataTypes.InterestRateParams) internal sInterestRateParams;

    /// @notice Reserve data for each supported asset.
    mapping(address asset => DataTypes.ReserveData) internal sReserves;

    /// @notice Maps reserve IDs to their underlying asset addresses.
    mapping(uint256 id => address asset) internal sReservesList;

    /// @notice Price feed configuration for supported assets.
    mapping(address asset => DataTypes.FeedData) internal sFeeds;

    /// @notice User collateral and borrowing configuration.
    mapping(address user => DataTypes.UserConfiguration) internal sUserConfig;

    /// @notice Total number of reserves supported by the protocol.
    uint256 internal sReserveCount;

    /// @dev Maximum number of reserves supported by the protocol.
    uint256 internal constant MAX_RESERVE_LENGTH = 128;

    /// @dev Maximum debt coverage allowed during liquidation, expressed in basis points (50%).
    uint256 internal constant CLOSE_FACTOR = 5000;

    /// @notice Emitted when a reserve initialization is completed.
    event ReserveInitialized(
        address indexed asset,
        address indexed liquidityToken,
        address indexed debtToken,
        DataTypes.InterestRateParams params,
        DataTypes.FeedData feed,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 reserveFactor,
        uint256 id
    );

    /// @notice Emitted when a reserve's active status is updated.
    event ReserveStatusUpdated(address indexed asset, bool isActive);

    /// @notice Emitted when a intrest rate params is updated.
    event InterestRateParamsUpdated(address indexed asset, DataTypes.InterestRateParams params);

    /// @notice Emitted when a feed data is updated.
    event FeedDataUpdated(address indexed asset, DataTypes.FeedData feed);

    /// @notice Emitted when a reserve data is updated.
    event ReserveDataUpdated(
        address indexed asset, uint256 liquidationThreshold, uint256 liquidationBonus, uint256 reserveFactor
    );

    /// @notice Emitted when a user supplies assets to the pool.
    event Supply(address indexed asset, address user, address indexed onBehalfOf, uint256 amount);

    /// @notice Emitted when a user withdraws assets from the pool.
    event Withdraw(address indexed asset, address indexed user, address indexed to, uint256 amount);

    /// @notice Emitted when a user borrows assets from the pool.
    event Borrow(address indexed asset, address indexed user, uint256 amount);

    /// @notice Emitted when a user repays borrowed assets to the pool.
    event Repay(
        address indexed reserve, address indexed user, address indexed repayer, uint256 amount, bool useATokens
    );

    /// @notice Emitted when a user is liquidated.
    event LiquidationCall(
        address indexed collateralAsset,
        address indexed debtAsset,
        address indexed user,
        address liquidator,
        uint256 debtRepaid,
        uint256 collateralLiquidated,
        bool receiveATokens
    );

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Initializes a new reserve in the lending pool.
     * @dev Can only be called by the contract owner. Initializes reserve data, interest rate parameters, and price feed configuration.
     * @param asset The address of the underlying asset for the reserve.
     * @param liquidityTokenAddress The address of the liquidity token associated with the reserve.
     * @param debtTokenAddress The address of the debt token associated with the reserve.
     * @param liquidationThreshold The liquidation threshold for the reserve, expressed in basis points.
     * @param liquidationBonus The liquidation bonus for the reserve, expressed in basis points.
     * @param reserveFactor The reserve factor for the reserve, expressed in basis points.
     * @param params The interest rate parameters for the reserve.
     * @param feed The price feed configuration for the reserve.
     * @dev Emits a ReserveInitialized event upon successful initialization.
     * @dev The reserve ID is automatically assigned based on the current reserve count.
     * @dev The reserve is added to the reserves list for easy enumeration.
     * @dev The reserve is marked as active upon initialization.
     */
    function initializeReserve(
        address asset,
        address liquidityTokenAddress,
        address debtTokenAddress,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 reserveFactor,
        DataTypes.InterestRateParams calldata params,
        DataTypes.FeedData calldata feed
    ) external onlyOwner {
        DataTypes.ReserveData storage reserve = sReserves[asset];

        sReserveCount.validateReserveInit(asset, liquidityTokenAddress, debtTokenAddress);

        uint256 id = sReserveCount;

        sInterestRateParams[asset] = params;
        sFeeds[asset] = feed;
        sReservesList[id] = asset;
        reserve.initReserve(
            liquidityTokenAddress, debtTokenAddress, liquidationThreshold, liquidationBonus, reserveFactor, id
        );

        emit ReserveInitialized(
            asset,
            liquidityTokenAddress,
            debtTokenAddress,
            params,
            feed,
            liquidationThreshold,
            liquidationBonus,
            reserveFactor,
            id
        );

        ++sReserveCount;
    }

    /**
     * @notice Updates the active status of a reserve.
     * @dev Can only be called by the contract owner. Validates the status change and emits a ReserveStatusUpdated event.
     * @param asset The address of the reserve asset.
     * @param active The new active status for the reserve.
     * @dev Emits a ReserveStatusUpdated event upon successful status change.
     */
    function updateReserveActive(address asset, bool active) external onlyOwner {
        DataTypes.ReserveData storage reserve = sReserves[asset];

        reserve.validateReserveActiveStatusChange(active);

        sReserves[asset].isActive = active;
        emit ReserveStatusUpdated(asset, active);
    }

    /**
     * @notice Updates the interest rate parameters for a reserve.
     * @dev Can only be called by the contract owner. Updates the interest rate parameters for the specified reserve asset.
     * @param asset The address of the reserve asset.
     * @param params The new interest rate parameters for the reserve.
     * @dev Emits a InterestRateParamsUpdated event upon successful update.
     */
    function updateInterestRateParams(address asset, DataTypes.InterestRateParams calldata params) external onlyOwner {
        DataTypes.ReserveData storage reserve = sReserves[asset];

        reserve.validateReserveExists();

        sInterestRateParams[asset] = params;
        emit InterestRateParamsUpdated(asset, params);
    }

    /**
     * @notice Updates the price feed configuration for a reserve.
     * @dev Can only be called by the contract owner. Updates the price feed configuration for the specified reserve asset.
     * @param asset The address of the reserve asset.
     * @param feed The new price feed configuration for the reserve.
     * @dev Emits a FeedDataUpdated event upon successful update.
     */
    function updateFeedData(address asset, DataTypes.FeedData calldata feed) external onlyOwner {
        DataTypes.ReserveData storage reserve = sReserves[asset];

        reserve.validateReserveExists();

        sFeeds[asset] = feed;
        emit FeedDataUpdated(asset, feed);
    }

    /**
     * @notice Updates the liquidation configuration data for a reserve.
     * @dev Can only be called by the contract owner. Updates the liquidation threshold,
     * liquidation bonus, and reserve factor for the specified reserve asset.
     * @param asset The address of the reserve asset.
     * @param liquidationThreshold The new liquidation threshold for the reserve, expressed in basis points.
     * @param liquidationBonus The new liquidation bonus for the reserve, expressed in basis points.
     * @param reserveFactor The new reserve factor for the reserve, expressed in basis points.
     * @dev Emits a ReserveConfigurationUpdated event upon successful update.
     */
    function updateReserveData(
        address asset,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 reserveFactor
    ) external onlyOwner {
        DataTypes.ReserveData storage reserve = sReserves[asset];

        reserve.validateReserveExists();

        reserve.updateReserve(liquidationThreshold, liquidationBonus, reserveFactor);
        emit ReserveDataUpdated(asset, liquidationThreshold, liquidationBonus, reserveFactor);
    }

    /**
     * @notice Supplies assets to the lending pool.
     * @dev Transfers the underlying asset from the caller, updates reserve state,
     *      recalculates interest rates, and mints liquidity tokens to `onBehalfOf`.
     * @param asset The address of the asset being supplied.
     * @param amount The amount of the asset to supply.
     * @param onBehalfOf The address that will receive the liquidity tokens.
     */
    function supply(address asset, uint256 amount, address onBehalfOf) external override nonReentrant {
        DataTypes.ReserveData storage reserve = sReserves[asset];
        DataTypes.ReserveCache memory reserveCache = reserve.cache();

        reserve.updateState(reserveCache);

        uint256 scaledAmount = amount.rayDivFloor(reserveCache.nextLiquidityIndex);
        reserveCache.validateSupply(scaledAmount);

        reserve.updateInterestRates(reserveCache, amount, 0, sInterestRateParams[asset]);

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        ILiquidityToken(reserveCache.liquidityTokenAddress).mint(onBehalfOf, scaledAmount);
        emit Supply(asset, msg.sender, onBehalfOf, amount);
    }

    /**
     * @notice Withdraws assets from the lending pool.
     * @dev Transfers the underlying asset to the caller, updates reserve state,
     *      recalculates interest rates, and burns liquidity tokens.
     * @param asset The address of the asset being withdrawn.
     * @param amount The amount of the asset to withdraw.
     * @param to The address that will receive the withdrawn assets.
     */
    function withdraw(address asset, uint256 amount, address to) external override nonReentrant {
        DataTypes.ReserveData storage reserve = sReserves[asset];
        DataTypes.ReserveCache memory reserveCache = reserve.cache();

        reserve.updateState(reserveCache);

        uint256 scaledAmount = amount.rayDivCeil(reserveCache.nextLiquidityIndex);
        uint256 healthFactorAfter = _healthFactor(msg.sender, asset, amount, address(0), 0);

        reserveCache.validateWithdraw(msg.sender, asset, amount, scaledAmount, healthFactorAfter);

        reserve.updateInterestRates(reserveCache, 0, amount, sInterestRateParams[asset]);
        bool zeroBalance = ILiquidityToken(reserveCache.liquidityTokenAddress).burn(msg.sender, scaledAmount);
        if (zeroBalance) {
            _setUseAsCollateral(msg.sender, reserve.id, false);
        }
        IERC20(asset).safeTransfer(to, amount);
        emit Withdraw(asset, msg.sender, to, amount);
    }

    /**
     * @notice Borrows assets from the lending pool.
     * @dev Transfers the underlying asset to the caller, updates reserve state,
     *      recalculates interest rates, and mints debt tokens.
     * @param asset The address of the asset being borrowed.
     * @param amount The amount of the asset to borrow.
     */
    function borrow(address asset, uint256 amount) external override nonReentrant {
        DataTypes.ReserveData storage reserve = sReserves[asset];
        DataTypes.ReserveCache memory reserveCache = reserve.cache();
        DataTypes.UserConfiguration storage userConfig = sUserConfig[msg.sender];

        reserve.updateState(reserveCache);

        uint256 scaledAmount = amount.rayDiv(reserveCache.nextBorrowIndex);
        uint256 healthFactorAfter = _healthFactor(msg.sender, address(0), 0, asset, amount);
        reserveCache.validateBorrow(userConfig, asset, amount, scaledAmount, healthFactorAfter);

        reserve.updateInterestRates(reserveCache, 0, amount, sInterestRateParams[asset]);

        IDebtToken(reserveCache.debtTokenAddress).mint(msg.sender, scaledAmount);
        _setAsBorrowing(msg.sender, reserve.id, true);
        IERC20(asset).safeTransfer(msg.sender, amount);
        emit Borrow(asset, msg.sender, amount);
    }

    /**
     * @notice Repays borrowed assets on behalf of a user.
     * @param asset The address of the borrowed asset.
     * @param amount The maximum amount to repay.
     * @param onBehalfOf The account whose debt is repaid.
     */
    function repay(address asset, uint256 amount, address onBehalfOf) external override nonReentrant {
        _repay(asset, amount, onBehalfOf, false);
    }

    /**
     * @notice Repays borrowed assets using the caller's liquidity tokens.
     * @param asset The address of the borrowed asset.
     * @param amount The maximum amount to repay.
     */
    function repayWithLiquidityTokens(address asset, uint256 amount) external override nonReentrant {
        _repay(asset, amount, msg.sender, true);
    }

    /**
     * @notice Initiates a liquidation call for a user's borrowed assets.
     * @dev Transfers the underlying debt asset from the liquidator, updates reserve states,
     *      recalculates interest rates, burns the user's debt tokens, and either transfers
     *      the collateral to the liquidator or transfers liquidity tokens based on `receiveLiquidityToken`.
     * @param collateralAsset The address of the collateral asset.
     * @param debtAsset The address of the debt asset.
     * @param user The address of the user being liquidated.
     * @param debtToCover The amount of debt to cover.
     * @param receiveLiquidityToken Whether to receive liquidity tokens as a result of the liquidation.
     */
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveLiquidityToken
    ) external nonReentrant {
        DataTypes.ReserveData storage reserveCollateral = sReserves[collateralAsset];
        DataTypes.ReserveData storage reserveDebt = sReserves[debtAsset];
        DataTypes.ReserveCache memory collateralCache = reserveCollateral.cache();
        DataTypes.ReserveCache memory debtCache = reserveDebt.cache();

        reserveCollateral.updateState(collateralCache);
        reserveDebt.updateState(debtCache);

        collateralCache.validateLiquidation(
            debtCache, sUserConfig[user], user, reserveCollateral.id, _healthFactor(user, address(0), 0, address(0), 0)
        );

        _executeLiquidation(
            collateralAsset,
            debtAsset,
            user,
            debtToCover,
            reserveCollateral,
            reserveDebt,
            collateralCache,
            debtCache,
            receiveLiquidityToken
        );
    }

    /**
     * @notice Transfers liquidity tokens from the caller to another user.
     * @param asset The address of the liquidity token.
     * @param to The address of the user receiving the tokens.
     * @param amount The amount of tokens to transfer.
     */
    function transferLiquidityToken(address asset, address to, uint256 amount) external override nonReentrant {
        DataTypes.ReserveData storage reserve = sReserves[asset];
        DataTypes.ReserveCache memory reserveCache = reserve.cache();

        reserve.updateState(reserveCache);

        uint256 scaledAmount = amount.rayDiv(reserveCache.nextLiquidityIndex);
        uint256 healthFactorAfter = _healthFactor(msg.sender, asset, amount, address(0), 0);
        reserveCache.validateTransferLiquidityToken(msg.sender, scaledAmount, healthFactorAfter);

        _transferLiquidityToken(reserveCache.liquidityTokenAddress, msg.sender, to, scaledAmount, reserve.id);
    }

    /**
     * @notice Sets whether a reserve can be used as collateral by a user.
     * @param asset The address of the asset.
     * @param useAsCollateral The flag indicating if the reserve should be used as collateral.
     */
    function setUseAsCollateral(address asset, bool useAsCollateral) public {
        DataTypes.ReserveData storage reserve = sReserves[asset];

        reserve.validateSetUseAsCollateral(useAsCollateral);

        _setUseAsCollateral(msg.sender, reserve.id, useAsCollateral);
        uint256 hf = _healthFactor(msg.sender, address(0), 0, address(0), 0);
        hf.validateUserHealthFactorAfterAction();
    }

    /**
     * @notice Returns the current normalized income index of a reserve.
     * @param asset The address of the reserve asset.
     * @return The normalized income index used for liquidity token balance calculations.
     */
    function getReserveNormalizedIncome(address asset) external view override returns (uint256) {
        return sReserves[asset].getReserveNormalizedIncome();
    }

    /**
     * @notice Returns the current normalized variable debt index of a reserve.
     * @param asset The address of the reserve asset.
     * @return The normalized debt index used for debt token balance calculations.
     */
    function getReserveNormalizedDebt(address asset) external view override returns (uint256) {
        return sReserves[asset].getReserveNormalizedDebt();
    }

    /**
     * @notice Calculates a user's current or simulated health factor.
     * @dev If `collateralAsset`, `collateralDecrease`, `debtAsset`, and `debtIncrease` are all zero,
     *      returns the user's current health factor.
     * @param user The account whose health factor is being evaluated.
     * @param collateralAsset The collateral asset to simulate withdrawing from.
     * @param collateralDecrease The amount of collateral to hypothetically remove.
     * @param debtAsset The asset to simulate borrowing.
     * @param debtIncrease The additional debt amount to hypothetically add.
     * @return The simulated health factor, scaled by 1e18.
     */
    function _healthFactor(
        address user,
        address collateralAsset,
        uint256 collateralDecrease,
        address debtAsset,
        uint256 debtIncrease
    ) internal view returns (uint256) {
        DataTypes.UserConfiguration storage userConfig = sUserConfig[user];

        if (!sUserConfig[user].hasBorrow()) return type(uint256).max;

        uint256 weightedLiquidationThreshold;
        uint256 totalCollateralInUsd;
        uint256 totalDebtInUsd;

        for (uint256 i; i < MAX_RESERVE_LENGTH; ++i) {
            address reserveAsset = sReservesList[i];
            if (reserveAsset == address(0)) continue;

            DataTypes.ReserveData storage reserve = sReserves[reserveAsset];
            if (!reserve.isActive) continue;

            if (userConfig.isCollateral(i)) {
                uint256 balance = ILiquidityToken(reserve.liquidityTokenAddress).balanceOf(user);

                if (reserveAsset == collateralAsset) {
                    balance.validateUserHaveEnoughBalance(collateralDecrease);
                    balance -= collateralDecrease;
                }

                if (balance != 0) {
                    uint256 collateralValue = _usdValue(reserveAsset, balance);

                    totalCollateralInUsd += collateralValue;
                    weightedLiquidationThreshold += collateralValue * reserve.liquidationThreshold;
                }
            }

            if (userConfig.isBorrowing(i)) {
                uint256 debt = IDebtToken(reserve.debtTokenAddress).balanceOf(user);

                if (debt != 0) {
                    totalDebtInUsd += _usdValue(reserveAsset, debt);
                }
            }
        }

        if (debtIncrease != 0) {
            totalDebtInUsd += _usdValue(debtAsset, debtIncrease);
        }

        if (totalDebtInUsd == 0) return type(uint256).max;
        if (totalCollateralInUsd == 0) return 0;

        uint256 avgLiquidationThreshold = weightedLiquidationThreshold / totalCollateralInUsd;
        uint256 collateralAdjustedForThreshold = totalCollateralInUsd.percentageMul(avgLiquidationThreshold);

        return collateralAdjustedForThreshold.wadDiv(totalDebtInUsd);
    }

    /**
     * @notice Repays debt for a borrower using underlying assets or liquidity tokens.
     * @dev Transfers the underlying asset to the pool, updates reserve state,
     *      recalculates interest rates, and burns debt tokens.
     * @param asset The address of the borrowed asset.
     * @param amount The maximum amount to repay.
     * @param onBehalfOf The account whose debt is being repaid.
     * @param useLiquidityTokens Whether to repay with liquidity tokens.
     */
    function _repay(address asset, uint256 amount, address onBehalfOf, bool useLiquidityTokens) internal {
        DataTypes.ReserveData storage reserve = sReserves[asset];
        DataTypes.ReserveCache memory reserveCache = reserve.cache();

        reserve.updateState(reserveCache);

        uint256 debtToRepay;
        uint256 userDebt = IDebtToken(reserveCache.debtTokenAddress).balanceOf(onBehalfOf);
        if (userDebt < amount) {
            debtToRepay = userDebt;
        } else {
            debtToRepay = amount;
        }

        uint256 scaledDebt = debtToRepay.rayDivFloor(reserveCache.nextBorrowIndex);
        reserveCache.validateRepay(scaledDebt);

        _burnDebtToken(reserveCache.debtTokenAddress, msg.sender, reserve.id, scaledDebt);
        if (useLiquidityTokens) {
            uint256 scaledLiquidity = debtToRepay.rayDivFloor(reserveCache.nextLiquidityIndex);

            reserve.updateInterestRates(reserveCache, 0, 0, sInterestRateParams[asset]);
            _burnLiquidityToken(reserveCache.liquidityTokenAddress, onBehalfOf, reserve.id, scaledLiquidity);
        } else {
            reserve.updateInterestRates(reserveCache, debtToRepay, 0, sInterestRateParams[asset]);
            IERC20(asset).safeTransferFrom(msg.sender, address(this), debtToRepay);
        }

        emit Repay(asset, onBehalfOf, msg.sender, debtToRepay, useLiquidityTokens);
    }

    /**
     * @notice Executes a liquidation call for a user's borrowed assets.
     * @param collateralAsset The address of the collateral asset.
     * @param debtAsset The address of the debt asset.
     * @param user The address of the user being liquidated.
     * @param debtToCover The amount of debt to cover.
     * @param reserveCollateral The reserve data for the collateral asset.
     * @param reserveDebt The reserve data for the debt asset.
     * @param collateralCache The cache for the collateral asset.
     * @param debtCache The cache for the debt asset.
     * @param receiveLiquidityToken Whether to receive liquidity tokens as a result of the liquidation.
     */
    function _executeLiquidation(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        DataTypes.ReserveData storage reserveCollateral,
        DataTypes.ReserveData storage reserveDebt,
        DataTypes.ReserveCache memory collateralCache,
        DataTypes.ReserveCache memory debtCache,
        bool receiveLiquidityToken
    ) internal {
        (uint256 debtToRepay, uint256 collateralToSeize) = _calculateLiquidationAmounts(
            collateralAsset, debtAsset, user, debtToCover, collateralCache, debtCache
        );
        uint256 scaledCollateral = collateralToSeize.rayDivCeil(collateralCache.nextLiquidityIndex);

        reserveDebt.updateInterestRates(debtCache, debtToRepay, 0, sInterestRateParams[debtAsset]);
        IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), debtToRepay);
        _burnDebtToken(
            debtCache.debtTokenAddress, user, reserveDebt.id, debtToRepay.rayDivFloor(debtCache.nextBorrowIndex)
        );

        if (!receiveLiquidityToken) {
            reserveCollateral.updateInterestRates(
                collateralCache, 0, collateralToSeize, sInterestRateParams[collateralAsset]
            );
            _burnLiquidityToken(collateralCache.liquidityTokenAddress, user, reserveCollateral.id, scaledCollateral);
            IERC20(collateralAsset).safeTransfer(msg.sender, collateralToSeize);
        } else {
            _transferLiquidityToken(
                collateralCache.liquidityTokenAddress, user, msg.sender, scaledCollateral, reserveCollateral.id
            );
        }

        emit LiquidationCall(
            collateralAsset, debtAsset, user, msg.sender, debtToRepay, collateralToSeize, receiveLiquidityToken
        );
    }

    /**
     * @notice Calculates the amounts of debt to repay and collateral to seize during liquidation.
     * @param collateralAsset The address of the collateral asset.
     * @param debtAsset The address of the debt asset.
     * @param user The address of the user being liquidated.
     * @param debtToCover The amount of debt to cover.
     * @param collateralCache The cache for the collateral asset.
     * @param debtCache The cache for the debt asset.
     * @return debtToRepay The amount of debt to repay.
     * @return collateralToSeize The amount of collateral to seize.
     */
    function _calculateLiquidationAmounts(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        DataTypes.ReserveCache memory collateralCache,
        DataTypes.ReserveCache memory debtCache
    ) internal view returns (uint256 debtToRepay, uint256 collateralToSeize) {
        uint256 maxDebtToCover = IDebtToken(debtCache.debtTokenAddress).balanceOf(user).percentageMul(CLOSE_FACTOR);

        debtToRepay = debtToCover > maxDebtToCover ? maxDebtToCover : debtToCover;
        uint256 debtWithBonus = debtToRepay + debtToRepay.percentageMul(collateralCache.liquidationBonus);
        collateralToSeize = _tokenAmountFromUsd(collateralAsset, _usdValue(debtAsset, debtWithBonus));
        uint256 userCollateral = ILiquidityToken(collateralCache.liquidityTokenAddress).balanceOf(user);

        if (collateralToSeize > userCollateral) {
            collateralToSeize = userCollateral;
            uint256 collateralUsd = _usdValue(collateralAsset, userCollateral);
            uint256 debtUsd = collateralUsd.percentageDiv(Math.PERCENTAGE_FACTOR + collateralCache.liquidationBonus);

            debtToRepay = _tokenAmountFromUsd(debtAsset, debtUsd);
        }
    }

    /**
     * @notice Transfers liquidity tokens from one user to another.
     * @param liquidityTokenAddress The address of the liquidity token.
     * @param from The address of the user transferring the tokens.
     * @param to The address of the user receiving the tokens.
     * @param scaledAmount The amount of tokens to transfer.
     * @param reserveId The ID of the reserve.
     */
    function _transferLiquidityToken(
        address liquidityTokenAddress,
        address from,
        address to,
        uint256 scaledAmount,
        uint256 reserveId
    ) internal {
        scaledAmount.validateTransferLiquidityTokenInternal(from, liquidityTokenAddress);

        bool success = ILiquidityToken(liquidityTokenAddress).transferOnBehalf(from, to, scaledAmount);
        if (ILiquidityToken(liquidityTokenAddress).balanceOf(from) == 0) {
            _setUseAsCollateral(from, reserveId, false);
        }
        success.validateTransferLiquidityTokenSuccessful();
    }

    /**
     * @notice Sets whether a reserve can be used as collateral by a user.
     * @param user The address of the user.
     * @param reserveId The ID of the reserve.
     * @param useAsCollateral The flag indicating if the reserve should be used as collateral.
     */
    function _setUseAsCollateral(address user, uint256 reserveId, bool useAsCollateral) internal {
        DataTypes.UserConfiguration storage userConfig = sUserConfig[user];
        reserveId.validateSetUseAsCollateralInternal(userConfig, useAsCollateral);

        userConfig.setCollateral(reserveId, useAsCollateral);
    }

    /**
     * @notice Updates whether a user is borrowing from a specific reserve.
     * @dev Reverts if the requested borrowing status is already set for the reserve.
     * @param user The address of the user.
     * @param reserveId The identifier of the reserve.
     * @param borrowing True to mark the user as borrowing from the reserve, false otherwise.
     */
    function _setAsBorrowing(address user, uint256 reserveId, bool borrowing) internal {
        DataTypes.UserConfiguration storage userConfig = sUserConfig[user];
        reserveId.validateSetAsBorrowing(userConfig, borrowing);

        userConfig.setBorrowing(reserveId, borrowing);
    }

    /**
     * @notice Converts asset token amount into the equivalent USD-denominated amount
     * @param asset The ERC20 token address
     * @param amount The asset amount (18 decimals precision)
     * @return The equivalent amount of USD-denominated amount
     * @dev Uses Chainlink price feeds for token/USD conversion & OracleLib for stale check
     */
    function _usdValue(address asset, uint256 amount) internal view returns (uint256) {
        DataTypes.FeedData memory feed = sFeeds[asset];

        AggregatorV3Interface priceFeed = AggregatorV3Interface(feed.priceFeedAddress);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        if (feed.feedDecimals < 18) {
            // casting to 'uint256' is safe because OracleLib guarantees a non-negative answer
            // forge-lint: disable-next-line(unsafe-typecast)
            return (amount * (uint256(price)) * 10 ** (18 - feed.feedDecimals) / 10 ** feed.tokenDecimals);
        } else {
            // casting to 'uint256' is safe because OracleLib guarantees a non-negative answer
            // forge-lint: disable-next-line(unsafe-typecast)
            return (amount * uint256(price)) / (10 ** feed.tokenDecimals * 10 ** (feed.feedDecimals - 18));
        }
    }

    /**
     * @notice Converts a USD-denominated amount into the equivalent payment token amount
     * @param asset The ERC20 payment token address
     * @param usdAmount The USD amount (18 decimals precision)
     * @return The equivalent amount of payment tokens required
     * @dev Uses Chainlink price feeds for token/USD conversion & OracleLib for stale check
     */
    function _tokenAmountFromUsd(address asset, uint256 usdAmount) internal view returns (uint256) {
        DataTypes.FeedData memory feed = sFeeds[asset];

        AggregatorV3Interface priceFeed = AggregatorV3Interface(feed.priceFeedAddress);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        if (feed.feedDecimals < 18) {
            // casting to 'uint256' is safe because OracleLib guarantees a non-negative answer
            // forge-lint: disable-next-line(unsafe-typecast)
            return (usdAmount * 10 ** feed.tokenDecimals) / (uint256(price) * 10 ** (18 - feed.feedDecimals));
        } else {
            // casting to 'uint256' is safe because OracleLib guarantees a non-negative answer
            // forge-lint: disable-next-line(unsafe-typecast)
            return (usdAmount * 10 ** feed.tokenDecimals * 10 ** (feed.feedDecimals - 18)) / (uint256(price));
        }
    }

    /**
     * @notice Burns liquidity tokens and updates the collateral status if the balance becomes zero
     * @param liquidityToken The address of the liquidity token to burn
     * @param reserveId The ID of the reserve for which to update collateral status
     * @param scaledLiquidity The amount of liquidity tokens to burn
     */
    function _burnLiquidityToken(address liquidityToken, address user, uint256 reserveId, uint256 scaledLiquidity)
        internal
    {
        bool zeroBalance = ILiquidityToken(liquidityToken).burn(user, scaledLiquidity);
        if (zeroBalance) {
            _setUseAsCollateral(user, reserveId, false);
        }
    }

    /**
     * @notice Burns debt tokens and updates the borrowing status if the balance becomes zero
     * @param debtToken The address of the debt token to burn
     * @param reserveId The ID of the reserve for which to update borrowing status
     * @param scaledDebt The amount of debt tokens to burn
     */
    function _burnDebtToken(address debtToken, address user, uint256 reserveId, uint256 scaledDebt) internal {
        bool zeroDebt = IDebtToken(debtToken).burn(user, scaledDebt);
        if (zeroDebt) {
            _setAsBorrowing(user, reserveId, false);
        }
    }
}
