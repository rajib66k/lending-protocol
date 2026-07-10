// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {UserConfiguration} from "src/configuration/UserConfiguration.sol";
import {DataTypes} from "src/types/DataTypes.sol";

/// forge-config: default.allow_internal_expect_revert = true
contract UserConfigurationTest is Test {
    using UserConfiguration for DataTypes.UserConfiguration;

    DataTypes.UserConfiguration public config;

    ////////////////////////
    // INITIAL STATE      //
    ////////////////////////
    function testInitialState() public view {
        assertTrue(config.isEmpty());
        assertFalse(config.hasBorrow());
        assertFalse(config.hasCollateral());
    }

    ////////////////////
    // BORROWING      //
    ////////////////////
    function testSetBorrowingAndIsBorrowingRevertIfInvalidReserve() public {
        vm.expectRevert(UserConfiguration.InvalidReserveIndex.selector);
        config.setBorrowing(128, true);

        vm.expectRevert(UserConfiguration.InvalidReserveIndex.selector);
        config.isBorrowing(128);
    }

    function testSetBorrowing() public {
        config.setBorrowing(0, true);

        assertTrue(config.isBorrowing(0));
        assertTrue(config.hasBorrow());

        assertFalse(config.isCollateral(0));
        assertFalse(config.hasCollateral());

        config.setBorrowing(0, false);

        assertFalse(config.isBorrowing(0));
        assertFalse(config.hasBorrow());
        assertTrue(config.isEmpty());
    }

    function testFuzzSetBorrowing(uint8 reserveId, bool borrowing) public {
        reserveId = uint8(bound(reserveId, 0, 127));

        config.setBorrowing(reserveId, borrowing);

        assertEq(config.isBorrowing(reserveId), borrowing);
    }

    /////////////////////
    // COLLATERAL      //
    /////////////////////
    function testSetCollateralAndIsCollateralRevertIfInvalidReserve() public {
        vm.expectRevert(UserConfiguration.InvalidReserveIndex.selector);
        config.setCollateral(128, true);

        vm.expectRevert(UserConfiguration.InvalidReserveIndex.selector);
        config.isCollateral(128);
    }

    function testSetCollateral() public {
        config.setCollateral(3, true);

        assertTrue(config.isCollateral(3));
        assertTrue(config.hasCollateral());

        assertFalse(config.isBorrowing(3));
        assertFalse(config.hasBorrow());

        config.setCollateral(3, false);

        assertFalse(config.isCollateral(3));
        assertFalse(config.hasCollateral());
        assertTrue(config.isEmpty());
    }

    function testFuzzSetCollateral(uint8 reserveId, bool collateral) public {
        reserveId = uint8(bound(reserveId, 0, 127));

        config.setCollateral(reserveId, collateral);

        assertEq(config.isCollateral(reserveId), collateral);
    }

    ////////////////////////////
    // SET CONFIGURATION      //
    ////////////////////////////
    function testSetConfigurationRevertInvalidReserve() public {
        vm.expectRevert(UserConfiguration.InvalidReserveIndex.selector);
        config.setConfiguration(128, true, true);
    }

    function testSetConfiguration() public {
        config.setConfiguration(5, true, false);

        assertTrue(config.isBorrowing(5));
        assertFalse(config.isCollateral(5));

        assertTrue(config.hasBorrow());
        assertFalse(config.hasCollateral());

        config.setConfiguration(5, false, true);

        assertFalse(config.isBorrowing(5));
        assertTrue(config.isCollateral(5));

        assertFalse(config.hasBorrow());
        assertTrue(config.hasCollateral());

        config.setConfiguration(8, true, true);

        assertTrue(config.isBorrowing(8));
        assertTrue(config.isCollateral(8));

        assertTrue(config.hasBorrow());
        assertTrue(config.hasCollateral());

        config.setConfiguration(8, false, false);

        assertFalse(config.isBorrowing(8));
        assertFalse(config.isCollateral(8));

        assertFalse(config.hasBorrow());
        assertTrue(config.hasCollateral());

        config.setBorrowing(7, true);

        assertFalse(config.isBorrowing(6));
        assertFalse(config.isBorrowing(8));

        config.setCollateral(12, true);

        assertFalse(config.isCollateral(11));
        assertFalse(config.isCollateral(13));

        assertFalse(config.isEmpty());
    }

    function testFuzzSetConfiguration(uint8 reserveId, bool borrowing, bool collateral) public {
        reserveId = uint8(bound(reserveId, 0, 127));

        config.setConfiguration(reserveId, borrowing, collateral);

        assertEq(config.isBorrowing(reserveId), borrowing);
        assertEq(config.isCollateral(reserveId), collateral);
    }
}
