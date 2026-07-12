// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPool} from "../interfaces/IPool.sol";
import {Math} from "../libraries/Math.sol";

/**
 * @title DebtToken
 * @author Rajib Kumar Pradhan
 * @notice Non-transferable token representing a user's debt position.
 * @dev Balances are stored in scaled units and rebased using the reserve debt index.
 */
contract DebtToken is ERC20, Ownable {
    error DebtToken__OperationNotSupported();
    error DebtToken__MustBeMoreThanZero();

    using Math for uint256;

    IPool internal immutable pool;
    address internal immutable underlyingAsset;
    uint8 internal immutable tokenDecimals;

    /**
     * @notice Creates a debt token linked to a specific reserve.
     * @dev The pool is used to fetch the current normalized debt index.
     * @param poolAddress The address of the pool contract.
     * @param asset The underlying asset this debt token represents.
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
     * @notice Creates scaled debt tokens for a user.
     * @param to The recipient of the debt tokens.
     * @param amountScaled The scaled amount to mint.
     */
    function mint(address to, uint256 amountScaled) external onlyOwner {
        if (amountScaled == 0) revert DebtToken__MustBeMoreThanZero();

        _mint(to, amountScaled);
    }

    /**
     * @notice Burns scaled debt tokens from a user.
     * @param from The address whose debt is burned.
     * @param amountScaled The scaled amount to burn.
     * @return True if the user's scaled balance becomes zero.
     */
    function burn(address from, uint256 amountScaled) external onlyOwner returns (bool) {
        if (amountScaled == 0) revert DebtToken__MustBeMoreThanZero();

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
     * @notice Returns the user's scaled debt balance.
     * @param user The address of the user.
     * @return The scaled debt balance.
     */
    function scaledBalanceOf(address user) public view returns (uint256) {
        return super.balanceOf(user);
    }

    /**
     * @notice Returns the user's current debt balance.
     * @param user The address of the user.
     * @return The rebased debt balance.
     */
    function balanceOf(address user) public view override returns (uint256) {
        return scaledBalanceOf(user).rayMul(pool.getReserveNormalizedDebt(underlyingAsset));
    }

    /**
     * @notice Returns the total scaled debt supply.
     * @return The total scaled debt.
     */
    function scaledTotalSupply() public view returns (uint256) {
        return super.totalSupply();
    }

    /**
     * @notice Returns the current total debt supply.
     * @return The rebased total debt.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return super.totalSupply().rayMul(pool.getReserveNormalizedDebt(underlyingAsset));
    }

    /**
     * @dev Debt tokens are non-transferable.
     */
    function transfer(address, uint256) public virtual override returns (bool) {
        revert DebtToken__OperationNotSupported();
    }

    /**
     * @dev Debt tokens are non-transferable.
     */
    function transferFrom(address, address, uint256) public virtual override returns (bool) {
        revert DebtToken__OperationNotSupported();
    }

    /**
     * @dev Debt tokens do not support approvals.
     */
    function approve(address, uint256) public virtual override returns (bool) {
        revert DebtToken__OperationNotSupported();
    }

    /**
     * @notice Returns zero since allowances are not supported.
     */
    function allowance(address, address) public view virtual override returns (uint256) {
        return 0;
    }
}
