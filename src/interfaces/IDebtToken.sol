// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IDebtToken
 * @author Rajib Kuamar Pradhan
 * @notice Defines the basic interface for a debt token.
 */
interface IDebtToken is IERC20 {
    /**
     * @notice Mints scaled debt tokens.
     * @param to The address receiving the debt tokens.
     * @param amountScaled The scaled amount to mint.
     */
    function mint(address to, uint256 amountScaled) external;

    /**
     * @notice Burns scaled debt tokens.
     * @param from The address whose debt is burned.
     * @param amountScaled The scaled amount to burn.
     * @return True if the user's scaled balance becomes zero.
     */
    function burn(address from, uint256 amountScaled) external returns (bool);

    /**
     * @notice Returns the user's scaled debt balance.
     */
    function scaledBalanceOf(address user) external view returns (uint256);

    /**
     * @notice Returns the total scaled debt supply.
     */
    function scaledTotalSupply() external view returns (uint256);
}
