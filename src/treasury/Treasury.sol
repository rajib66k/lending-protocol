// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Treasury
 * @author Rajib Kumar Pradhan
 * @notice Treasury for managing ERC20 assets securely.
 */
contract Treasury is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error DAOTreasury__InvalidAddress();
    error DAOTreasury__InvalidToken();

    /// @notice Emitted when ERC20 tokens are withdrawn from the treasury.
    event TokenWithdrawn(address indexed token, address indexed to, uint256 amount);

    /**
     * @notice Initializes the treasury and sets the deployer as the initial owner.
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @notice Transfers ERC20 tokens from the treasury to a recipient.
     * @dev Can only be called by the contract owner.
     * @param token The ERC20 token to transfer.
     * @param to The address receiving the tokens.
     * @param amount The amount of tokens to transfer.
     */
    function transferToken(IERC20 token, address to, uint256 amount) external onlyOwner nonReentrant {
        if (address(token) == address(0)) revert DAOTreasury__InvalidToken();
        if (to == address(0)) revert DAOTreasury__InvalidAddress();

        token.safeTransfer(to, amount);
        emit TokenWithdrawn(address(token), to, amount);
    }

    /**
     * @notice Returns the treasury balance of an ERC20 token.
     * @param token The ERC20 token to query.
     * @return The token balance held by the treasury.
     */
    function getTokenBalance(IERC20 token) external view returns (uint256) {
        if (address(token) == address(0)) revert DAOTreasury__InvalidToken();

        return token.balanceOf(address(this));
    }
}
