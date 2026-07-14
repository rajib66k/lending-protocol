// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {DataTypes} from "../types/DataTypes.sol";
import {ReserveLogic} from "../libraries/ReserveLogic.sol";
import {ValidationLogic} from "../libraries/ValidationLogic.sol";
import {Math} from "../libraries/Math.sol";
import {IPool} from "../interfaces/IPool.sol";
import {ILiquidityToken} from "../interfaces/ILiquidityToken.sol";
import {IDebtToken} from "../interfaces/IDebtToken.sol";
import {UserConfiguration} from "../configuration/UserConfiguration.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

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
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @notice Interest rate configuration for each supported reserve.
    mapping(address asset => DataTypes.InterestRateParams) public interestRateParams;

    /// @notice Reserve data for each supported asset.
    mapping(address asset => DataTypes.ReserveData) public reserves;

    /// @notice Maps reserve IDs to their underlying asset addresses.
    mapping(uint256 id => address asset) internal reservesList;

    /// @notice Price feed configuration for supported assets.
    mapping(address asset => DataTypes.FeedData) public feeds;

    /// @notice User collateral and borrowing configuration.
    mapping(address user => DataTypes.UserConfiguration) public userConfig;

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
        DataTypes.ReserveData storage reserve = reserves[asset];
        DataTypes.ReserveCache memory reserveCache = reserve.cache();

        reserve.updateState(reserveCache);

        uint256 scaledAmount = amount.rayDivFloor(reserveCache.nextLiquidityIndex);
        reserveCache.validateSupply(scaledAmount);

        reserve.updateInterestRates(reserveCache, amount, 0, interestRateParams[asset]);

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        ILiquidityToken(reserveCache.liquidityTokenAddress).mint(onBehalfOf, scaledAmount);
        emit Supply(asset, msg.sender, onBehalfOf, amount);
    }
}
