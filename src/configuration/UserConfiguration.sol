// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {DataTypes} from "../types/DataTypes.sol";

/**
 * @title UserConfiguration
 * @author Rajib Kumar Pradhan
 * @notice Stores user borrowing and collateral states using a bitmap.
 * @dev Each reserve uses two bits:
 *      bit (2*i)     -> borrowing
 *      bit (2*i + 1) -> collateral
 */
library UserConfiguration {
    error InvalidReserveIndex();

    uint256 internal constant MAX_RESERVES = 128;
    uint256 internal constant BORROW_MASK = 0x5555555555555555555555555555555555555555555555555555555555555555;
    uint256 internal constant COLLATERAL_MASK = 0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;

    /**
     * @notice Sets or clears the borrowing flag for a reserve.
     * @param self User configuration bitmap.
     * @param reserveId Reserve index.
     * @param borrowing True to mark as borrowing, false to clear.
     */
    function setBorrowing(DataTypes.UserConfiguration storage self, uint256 reserveId, bool borrowing) internal {
        if (reserveId >= MAX_RESERVES) revert InvalidReserveIndex();

        unchecked {
            // forge-lint: disable-next-line(incorrect-shift)
            uint256 bit = 1 << (reserveId << 1);

            if (borrowing) {
                self.data |= bit;
            } else {
                self.data &= ~bit;
            }
        }
    }

    /**
     * @notice Sets or clears the collateral flag for a reserve.
     * @param self User configuration bitmap.
     * @param reserveId Reserve index.
     * @param collateral True to enable collateral, false to disable.
     */
    function setCollateral(DataTypes.UserConfiguration storage self, uint256 reserveId, bool collateral) internal {
        if (reserveId >= MAX_RESERVES) revert InvalidReserveIndex();

        unchecked {
            // forge-lint: disable-next-line(incorrect-shift)
            uint256 bit = 1 << ((reserveId << 1) + 1);

            if (collateral) {
                self.data |= bit;
            } else {
                self.data &= ~bit;
            }
        }
    }

    /**
     * @notice Updates both borrowing and collateral flags for a reserve.
     * @dev Performs a single storage write.
     * @param self User configuration bitmap.
     * @param reserveId Reserve index.
     * @param borrowing True if user is borrowing.
     * @param collateral True if reserve is used as collateral.
     */
    function setConfiguration(
        DataTypes.UserConfiguration storage self,
        uint256 reserveId,
        bool borrowing,
        bool collateral
    ) internal {
        if (reserveId >= MAX_RESERVES) revert InvalidReserveIndex();

        unchecked {
            uint256 offset = reserveId << 1;
            uint256 mask = uint256(3) << offset;

            uint256 value;

            if (borrowing) {
                // forge-lint: disable-next-line(incorrect-shift)
                value |= 1 << offset;
            }

            if (collateral) {
                // forge-lint: disable-next-line(incorrect-shift)
                value |= 1 << (offset + 1);
            }

            self.data = (self.data & ~mask) | value;
        }
    }

    /**
     * @notice Checks whether a user is borrowing from a reserve.
     * @param self User configuration bitmap.
     * @param reserveId Reserve index.
     * @return True if borrowing is enabled.
     */
    function isBorrowing(DataTypes.UserConfiguration storage self, uint256 reserveId) internal view returns (bool) {
        if (reserveId >= MAX_RESERVES) revert InvalidReserveIndex();

        unchecked {
            return ((self.data >> (reserveId << 1)) & 1) != 0;
        }
    }

    /**
     * @notice Checks whether a reserve is enabled as collateral.
     * @param self User configuration bitmap.
     * @param reserveId Reserve index.
     * @return True if collateral is enabled.
     */
    function isCollateral(DataTypes.UserConfiguration storage self, uint256 reserveId) internal view returns (bool) {
        if (reserveId >= MAX_RESERVES) revert InvalidReserveIndex();

        unchecked {
            return ((self.data >> ((reserveId << 1) + 1)) & 1) != 0;
        }
    }

    /**
     * @notice Checks whether the user has any active borrow position.
     * @param self User configuration bitmap.
     * @return True if at least one borrow flag is set.
     */
    function hasBorrow(DataTypes.UserConfiguration storage self) internal view returns (bool) {
        return (self.data & BORROW_MASK) != 0;
    }

    /**
     * @notice Checks whether the user has any collateral enabled.
     * @param self User configuration bitmap.
     * @return True if at least one collateral flag is set.
     */
    function hasCollateral(DataTypes.UserConfiguration storage self) internal view returns (bool) {
        return (self.data & COLLATERAL_MASK) != 0;
    }

    /**
     * @notice Checks whether the configuration bitmap is empty.
     * @param self User configuration bitmap.
     * @return True if no borrow or collateral flags are set.
     */
    function isEmpty(DataTypes.UserConfiguration storage self) internal view returns (bool) {
        return self.data == 0;
    }
}
