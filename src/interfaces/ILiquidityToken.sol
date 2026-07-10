// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ILiquidityToken
 * @author Rajib Kuamar Pradhan
 * @notice Defines the basic interface for a liquidity token.
 */
interface ILiquidityToken is IERC20 {
    /**
     * @notice Mints liquidity tokens.
     * @param to The address receiving the liquidity tokens.
     * @param amountScaled The scaled amount to mint.
     */
    function mint(address to, uint256 amountScaled) external;

    /**
     * @notice Burns liquidity tokens.
     * @param from The address whose liquidity tokens are burned.
     * @param amountScaled The scaled amount to burn.
     * @return True if the user's scaled balance becomes zero.
     */
    function burn(address from, uint256 amountScaled) external returns (bool);

    /**
     * @notice Transfers scaled liquidity tokens on behalf of another address.
     * @dev Only callable by the Pool.
     * @param from The source address.
     * @param to The destination address.
     * @param scaledAmount The scaled amount to transfer.
     */
    function transferOnBehalf(address from, address to, uint256 scaledAmount) external returns (bool);

    /**
     * @notice Returns the user's scaled liquidity token balance.
     */
    function scaledBalanceOf(address user) external view returns (uint256);

    /**
     * @notice Returns the total scaled liquidity token supply.
     */
    function scaledTotalSupply() external view returns (uint256);
}
