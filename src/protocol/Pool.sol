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
    using ReserveLogic for DataTypes.ReserveData;
    using ValidationLogic for DataTypes.ReserveCache;
    using OracleLib for AggregatorV3Interface;
    using Math for uint256;
    using SafeERC20 for IERC20;

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
