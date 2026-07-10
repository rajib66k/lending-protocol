// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/**
 * @title IPool
 * @author Rajib Kumar Pradhan
 * @notice Defines the basic interface for Pool.
 */
interface IPool {
    /**
     * @notice Supplies an asset to the pool and receives liquidity tokens.
     * @param asset The address of the underlying asset.
     * @param amount The amount of asset supplied.
     * @param onBehalfOf The address receiving liquidity tokens.
     */
    function supply(address asset, uint256 amount, address onBehalfOf) external;

    /**
     * @notice Withdraws supplied liquidity from the pool.
     * @param asset The address of the underlying asset.
     * @param amount The amount to withdraw.
     * @param to The address receiving the withdrawn asset.
     */
    function withdraw(address asset, uint256 amount, address to) external;

    /**
     * @notice Borrows an asset from the pool.
     * @param asset The address of the asset to borrow.
     * @param amount The amount to borrow.
     */
    function borrow(address asset, uint256 amount) external;

    /**
     * @notice Repays borrowed debt using the underlying asset.
     * @param asset The address of the borrowed asset.
     * @param amount The amount to repay.
     * @param onBehalfOf The address whose debt is repaid.
     */
    function repay(address asset, uint256 amount, address onBehalfOf) external;

    /**
     * @notice Repays debt using liquidity tokens.
     * @param asset The address of the asset.
     * @param amount The amount of debt to repay.
     */
    function repayWithLiquidityTokens(address asset, uint256 amount) external;

    /**
     * @notice Enables or disables an asset as collateral.
     * @param asset The address of the collateral asset.
     * @param useAsCollateral Whether the asset should be used as collateral.
     */
    function setUseAsCollateral(address asset, bool useAsCollateral) external;

    /**
     * @notice Liquidates an unhealthy position.
     * @param collateralAsset The collateral asset to seize.
     * @param debtAsset The debt asset to repay.
     * @param user The user being liquidated.
     * @param debtToCover The amount of debt to cover.
     * @param receiveLiquidityToken Whether to receive liquidity tokens instead of the underlying asset.
     */
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveLiquidityToken
    ) external;

    /**
     * @notice Transfers liquidity tokens on behalf of a user.
     * @param asset The underlying asset.
     * @param to The receiver.
     * @param amount The amount of liquidity tokens to transfer.
     */
    function transferLiquidityToken(address asset, address to, uint256 amount) external;

    /**
     * @notice Returns the current normalized liquidity index of a reserve.
     */
    function getReserveNormalizedIncome(address asset) external view returns (uint256);

    /**
     * @notice Returns the current normalized variable debt index of a reserve.
     */
    function getReserveNormalizedDebt(address asset) external view returns (uint256);
}
