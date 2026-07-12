// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPool} from "../interfaces/IPool.sol";
import {Math} from "../libraries/Math.sol";

/**
 * @title LiquidityToken
 * @author Rajib Kumar Pradhan
 * @notice Token representing a user's supplied liquidity position.
 * @dev Balances are stored in scaled units and rebased using the reserve liquidity index.
 */
contract LiquidityToken is ERC20, Ownable {
    error LiquidityToken__MustBeMoreThanZero();
    error LiquidityToken__OperationNotSupported();

    using Math for uint256;

    address internal immutable underlyingAsset;
    uint8 internal immutable tokenDecimals;
    IPool internal immutable pool;

    /**
     * @notice Creates a liquidity token linked to a specific reserve.
     * @dev The pool is used to fetch the current normalized liquidity index.
     * @param poolAddress The address of the pool contract.
     * @param asset The underlying asset this liquidity token represents.
     */
    constructor(string memory tokenName, string memory symbol, address poolAddress, address asset, uint8 assetDecimals)
        Ownable(msg.sender)
        ERC20(tokenName, symbol)
    {
        pool = IPool(poolAddress);
        underlyingAsset = asset;
        tokenDecimals = assetDecimals;
    }

    /**
     * @notice Mints scaled liquidity tokens to a user.
     * @param to The address receiving the liquidity tokens.
     * @param amountScaled The scaled amount to mint.
     */
    function mint(address to, uint256 amountScaled) external onlyOwner {
        if (amountScaled == 0) revert LiquidityToken__MustBeMoreThanZero();

        _mint(to, amountScaled);
    }

    /**
     * @notice Burns scaled liquidity tokens from a user.
     * @param from The address whose liquidity tokens are burned.
     * @param amountScaled The scaled amount to burn.
     * @return True if the user's scaled balance becomes zero.
     */
    function burn(address from, uint256 amountScaled) external onlyOwner returns (bool) {
        if (amountScaled == 0) revert LiquidityToken__MustBeMoreThanZero();

        _burn(from, amountScaled);
        return scaledBalanceOf(from) == 0;
    }

    /**
     * @notice Returns the decimals of liquidity token.
     */
    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }

    /**
     * @notice Transfers scaled liquidity tokens on behalf of a user.
     * @dev Used by the pool for operations such as liquidation.
     * @param from The address tokens are transferred from.
     * @param to The address receiving the tokens.
     * @param scaledAmount The scaled amount to transfer.
     * @return True after successful transfer.
     */
    function transferOnBehalf(address from, address to, uint256 scaledAmount) external onlyOwner returns (bool) {
        if (scaledAmount == 0) revert LiquidityToken__MustBeMoreThanZero();

        _transfer(from, to, scaledAmount);
        return true;
    }

    /**
     * @notice Returns the user's scaled liquidity token balance.
     * @param user The address of the user.
     * @return The scaled balance before applying the liquidity index.
     */
    function scaledBalanceOf(address user) public view returns (uint256) {
        return super.balanceOf(user);
    }

    /**
     * @notice Returns the user's current liquidity balance.
     * @dev Applies the current normalized liquidity index.
     * @param user The address of the user.
     * @return The rebased liquidity balance.
     */
    function balanceOf(address user) public view override returns (uint256) {
        return scaledBalanceOf(user).rayMulFloor(pool.getReserveNormalizedIncome(underlyingAsset));
    }

    /**
     * @notice Returns the total scaled liquidity token supply.
     * @return The total scaled supply before applying the liquidity index.
     */
    function scaledTotalSupply() public view returns (uint256) {
        return super.totalSupply();
    }

    /**
     * @notice Returns the current total liquidity token supply.
     * @dev Applies the current normalized liquidity index.
     * @return The rebased total supply.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return super.totalSupply().rayMulFloor(pool.getReserveNormalizedIncome(underlyingAsset));
    }

    /**
     * @dev Liquidity tokens cannot be transferred directly.
     */
    function transfer(address, uint256) public virtual override returns (bool) {
        revert LiquidityToken__OperationNotSupported();
    }

    /**
     * @dev Liquidity tokens cannot be transferred using allowances.
     */
    function transferFrom(address, address, uint256) public virtual override returns (bool) {
        revert LiquidityToken__OperationNotSupported();
    }

    /**
     * @dev Liquidity tokens do not support approvals.
     */
    function approve(address, uint256) public virtual override returns (bool) {
        revert LiquidityToken__OperationNotSupported();
    }

    /**
     * @notice Returns zero since allowances are not supported.
     */
    function allowance(address, address) public view virtual override returns (uint256) {
        return 0;
    }
}
