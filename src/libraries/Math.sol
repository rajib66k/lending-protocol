// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/**
 * @title Math
 * @author Rajib Kuamar Pradhan
 * @notice Collection of mathematical utilities used throughout the lending protocol.
 */
library Math {
    error Math__DivisionByZero();
    error Math__MathOverflow();

    uint256 internal constant WAD = 1e18;
    uint256 internal constant HALF_WAD = 5e17;
    uint256 internal constant RAY = 1e27;
    uint256 internal constant HALF_RAY = 5e26;
    uint256 internal constant PERCENTAGE_FACTOR = 10000;
    uint256 internal constant HALF_FACTOR = 5000;
    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    /**
     * @notice Multiplies two wads, rounding half up.
     * @return (a * b) / WAD
     */
    function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;

        if (a > (type(uint256).max - HALF_WAD) / b) {
            revert Math__MathOverflow();
        }

        return (a * b + HALF_WAD) / WAD;
    }

    /**
     * @notice Divides two wads, rounding half up.
     * @return (a * WAD) / b
     */
    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) revert Math__DivisionByZero();

        if (a > (type(uint256).max - b / 2) / WAD) {
            revert Math__MathOverflow();
        }

        return (a * WAD + b / 2) / b;
    }

    /**
     * @notice Multiplies two rays, rounding half up.
     * @return (a * b) / RAY
     */
    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;

        if (a > (type(uint256).max - HALF_RAY) / b) {
            revert Math__MathOverflow();
        }

        return (a * b + HALF_RAY) / RAY;
    }

    /**
     * @notice Divides two rays, rounding half up.
     * @return (a * RAY) / b
     */
    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) revert Math__DivisionByZero();

        if (a > (type(uint256).max - b / 2) / RAY) {
            revert Math__MathOverflow();
        }

        return (a * RAY + b / 2) / b;
    }

    /**
     * @notice Executes a percentage multiplication
     * @param value The value of which the percentage needs to be calculated
     * @param percentage The percentage of the value to be calculated
     * @return result value percentmul percentage
     */
    function percentageMul(uint256 value, uint256 percentage) internal pure returns (uint256) {
        if (value == 0 || percentage == 0) {
            return 0;
        }

        if (value > (type(uint256).max - HALF_FACTOR) / percentage) {
            revert Math__MathOverflow();
        }

        return (value * percentage + HALF_FACTOR) / PERCENTAGE_FACTOR;
    }

    /**
     * @notice Executes a percentage division
     * @param value The value to be divided
     * @param percentage The percentage divisor
     * @return result value divided by percentage
     */
    function percentageDiv(uint256 value, uint256 percentage) internal pure returns (uint256) {
        if (value == 0) {
            return 0;
        }

        if (percentage == 0) {
            revert Math__DivisionByZero();
        }

        if (value > (type(uint256).max - (percentage / 2)) / PERCENTAGE_FACTOR) {
            revert Math__MathOverflow();
        }

        return (value * PERCENTAGE_FACTOR + (percentage / 2)) / percentage;
    }

    /**
     * @dev Function to calculate the interest accumulated using a linear interest rate formula
     * @param rate The interest rate, in ray
     * @param lastUpdateTimestamp The timestamp of the last update of the interest
     * @return The interest rate linearly accumulated during the timeDelta, in ray
     */
    function calculateLinearInterest(uint256 rate, uint40 lastUpdateTimestamp) internal view returns (uint256) {
        uint256 result = rate * (block.timestamp - uint256(lastUpdateTimestamp));

        unchecked {
            result = result / SECONDS_PER_YEAR;
        }

        return RAY + result;
    }

    /**
     * @dev Calculates compounded interest using a third-order Taylor approximation
     * of the continuous compounding formula:
     * e ** (r * t)
     *
     * where:
     * r = annualized interest rate
     * t = elapsed time in years
     *
     * Instead of evaluating the exponential directly, the implementation uses the first four terms of the Taylo series expansion:
     * e ** x = 1 + x + (x ** 2) / 2 + (x ** 3) / 6
     *
     * where:
     * x = rate * timeDelta / SECONDS_PER_YEAR
     *
     * This approximation significantly reduces gas costs while remaining highly
     * accurate for the small accrual intervals typically observed between reserve updates.
     * so the approximation error decreases rapidly as x approaches zero.
     *
     * Overflow considerations:
     * rate is bounded by protocol constraints and fits within 128 bits & exp is derived from timestamps and effectively bounded by uint40.
     * The polynomial approximation grows much more slowly than the true exponential function.
     * Even under extreme theoretical inputs the computation remains safe,allowing unchecked arithmetic to be used for gas efficiency.
     *
     * Notes:
     * This implementation approximates continuous compounding (e ** (r * t)).
     * The approximation slightly underestimates the true exponential value, resulting in a very small under-accrual of interest.
     * The tradeoff is intentional and favors gas efficiency while maintaining sufficient precision for lending market operations.
     *
     * @param rate Annualized interest rate in ray precision.
     * @param lastUpdateTimestamp Timestamp of the last interest accrual.
     *
     * @return Compounded interest factor in ray precision.
     */
    function calculateCompoundedInterest(uint256 rate, uint40 lastUpdateTimestamp) internal view returns (uint256) {
        uint256 exp = block.timestamp - uint256(lastUpdateTimestamp);

        if (exp == 0) {
            return RAY;
        }

        unchecked {
            // x = r * t
            // where t is represented as a fraction of a year
            uint256 x = (rate * exp) / SECONDS_PER_YEAR;

            // e ** x = 1 + x + (x ** 2) / 2 + (x ** 3) / 6
            // e ** x = 1 + x + x ((x / 2) + x (x / 6))
            return RAY + x + rayMul(x, x / 2 + rayMul(x, x / 6));
        }
    }
}
