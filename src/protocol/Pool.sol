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
 * @dev Currently implements the supply operation. Additional functionality such as withdrawals,
 *      borrowing, repayment, and liquidation will be added incrementally.
 */
abstract contract Pool is IPool, ReentrancyGuard, Ownable {
    error Pool__NotEnoughAvailableUserBalance();

    using ReserveLogic for DataTypes.ReserveData;
    using ValidationLogic for DataTypes.ReserveCache;
    using ValidationLogic for uint256;
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

    /// @dev Maximum number of reserves supported by the protocol.
    uint256 internal constant MAX_RESERVE_LENGTH = 128;

    /// @notice Emitted when a user supplies assets to the pool.
    event Supply(address indexed asset, address user, address indexed onBehalfOf, uint256 amount);

    constructor() Ownable(msg.sender) {}

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
     * @notice Sets whether a reserve can be used as collateral by a user.
     * @param user The address of the user.
     * @param reserveId The ID of the reserve.
     * @param useAsCollateral The flag indicating if the reserve should be used as collateral.
     */
    function _setUseAsCollateral(address user, uint256 reserveId, bool useAsCollateral) internal {
        DataTypes.UserConfiguration storage userConfig = sUserConfig[user];
        reserveId.validateSetUseAsCollateral(userConfig, useAsCollateral);

        userConfig.setCollateral(reserveId, useAsCollateral);
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
}
