// SPDX-License-Identifier: MIT
// pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {Math} from "../../src/libraries/Math.sol";

/// forge-config: default.allow_internal_expect_revert = true
contract MathTest is Test {
    using Math for uint256;

    //////////////////////////////
    // Wad Mul & Div Tests      //
    //////////////////////////////
    function testWadMulReturnsZero() public pure {
        assertEq(Math.wadMul(0, 1e18), 0);
        assertEq(Math.wadMul(1e18, 0), 0);
        assertEq(Math.wadMul(0, 0), 0);
    }

    function testWadMulRevertIfOverflow(uint256 a, uint256 b) public {
        b = bound(b, 1, type(uint96).max);
        a = bound(a, ((type(uint256).max - Math.HALF_WAD) / b) + 1, type(uint256).max);

        vm.expectRevert(Math.Math__MathOverflow.selector);
        Math.wadMul(a, b);
    }

    function testWadMul(uint256 a, uint256 b) public pure {
        b = bound(b, 1e8, type(uint96).max);
        a = bound(a, 1e8, (type(uint256).max - Math.HALF_WAD) / b);

        assertEq(Math.wadMul(a, b), (a * b + Math.HALF_WAD) / Math.WAD);
    }

    function testWadDivRevertIfDenominatorIsZero() public {
        vm.expectRevert(Math.Math__DivisionByZero.selector);
        Math.wadDiv(1e18, 0);
    }

    function testWadDivRevertIfOverflow(uint256 b) public {
        b = bound(b, 1, type(uint96).max);
        uint256 a = (type(uint256).max - b / 2) / Math.WAD + 1;

        vm.expectRevert(Math.Math__MathOverflow.selector);
        Math.wadDiv(a, b);
    }

    function testWadDiv(uint256 a, uint256 b) public pure {
        b = bound(b, 1e8, type(uint96).max);
        a = bound(a, 1e8, (type(uint256).max - b / 2) / Math.WAD);

        assertEq(Math.wadDiv(a, b), (a * Math.WAD + b / 2) / b);
    }

    //////////////////////////////
    // Ray Mul & Div Tests      //
    //////////////////////////////
    function testRayMulReturnsZero() public pure {
        assertEq(Math.rayMul(0, 1e18), 0);
        assertEq(Math.rayMul(1e18, 0), 0);
        assertEq(Math.rayMul(0, 0), 0);
    }

    function testRayMulRevertIfOverflow(uint256 a, uint256 b) public {
        b = bound(b, 1, type(uint96).max);
        a = bound(a, ((type(uint256).max - Math.HALF_RAY) / b) + 1, type(uint256).max);

        vm.expectRevert(Math.Math__MathOverflow.selector);
        Math.rayMul(a, b);
    }

    function testRayMul(uint256 a, uint256 b) public pure {
        b = bound(b, 1e8, type(uint96).max);
        a = bound(a, 1e8, (type(uint256).max - Math.HALF_RAY) / b);

        assertEq(Math.rayMul(a, b), (a * b + Math.HALF_RAY) / Math.RAY);
    }

    //////////////////////////////
    // Ray Mul & Div Tests      //
    //////////////////////////////
    function testRayDivRevertIfDenominatorIsZero() public {
        vm.expectRevert(Math.Math__DivisionByZero.selector);
        Math.rayDiv(1e27, 0);
    }

    function testRayDivRevertIfOverflow(uint256 b) public {
        b = bound(b, 1, type(uint96).max);
        uint256 a = (type(uint256).max - b / 2) / Math.RAY + 1;

        vm.expectRevert(Math.Math__MathOverflow.selector);
        Math.rayDiv(a, b);
    }

    function testRayDiv(uint256 a, uint256 b) public pure {
        b = bound(b, 1e8, type(uint96).max);
        a = bound(a, 1e8, (type(uint256).max - b / 2) / Math.RAY);

        assertEq(Math.rayDiv(a, b), (a * Math.RAY + b / 2) / b);
    }

    /////////////////////////////////////
    // Percentage Mul & Div Tests      //
    /////////////////////////////////////
    function testPercentageMulReturnsZero() public pure {
        assertEq(Math.percentageMul(0, 1e18), 0);
        assertEq(Math.percentageMul(1e18, 0), 0);
        assertEq(Math.percentageMul(0, 0), 0);
    }

    function testPercentageMulRevertIfOverflow(uint256 value, uint256 percentage) public {
        percentage = bound(percentage, 1, type(uint96).max);
        value = bound(value, (type(uint256).max - Math.HALF_FACTOR) / percentage + 1, type(uint256).max);

        vm.expectRevert(Math.Math__MathOverflow.selector);
        Math.percentageMul(value, percentage);
    }

    function testPercentageMul(uint256 value, uint256 percentage) public pure {
        percentage = bound(percentage, 1e8, type(uint96).max);
        value = bound(value, 1e8, (type(uint256).max - Math.HALF_FACTOR) / percentage);

        assertEq(
            Math.percentageMul(value, percentage), (value * percentage + Math.HALF_FACTOR) / Math.PERCENTAGE_FACTOR
        );
    }

    function testPercentageDivReturnsZero() public pure {
        assertEq(Math.percentageDiv(0, 100), 0);
    }

    function testPercentageDivRevertIfDenominatorIsZero() public {
        vm.expectRevert(Math.Math__DivisionByZero.selector);
        Math.percentageDiv(1e18, 0);
    }

    function testPercentageDivRevertIfOverflow(uint256 percentage) public {
        percentage = bound(percentage, 1, type(uint96).max);
        uint256 value = (type(uint256).max - (percentage / 2)) / Math.PERCENTAGE_FACTOR + 1;

        vm.expectRevert(Math.Math__MathOverflow.selector);
        Math.percentageDiv(value, percentage);
    }

    function testPercentageDiv(uint256 value, uint256 percentage) public pure {
        percentage = bound(percentage, 1e8, type(uint96).max);
        value = bound(value, 1e8, (type(uint256).max - (percentage / 2)) / Math.PERCENTAGE_FACTOR);

        assertEq(
            Math.percentageDiv(value, percentage), (value * Math.PERCENTAGE_FACTOR + (percentage / 2)) / percentage
        );
    }

    ////////////////////////////////
    // Linear Interest Tests      //
    ////////////////////////////////
    function testCalculateLinearInterest(uint256 rate, uint40 lastUpdateTimestamp) public view {
        rate = bound(rate, 1e8, type(uint96).max);
        lastUpdateTimestamp = uint40(bound(lastUpdateTimestamp, 1, block.timestamp));

        uint256 expectedIntRate = (rate * (block.timestamp - uint256(lastUpdateTimestamp))) / Math.SECONDS_PER_YEAR;

        assertEq(Math.calculateLinearInterest(rate, lastUpdateTimestamp), Math.RAY + expectedIntRate);
    }

    ////////////////////////////////////
    // Compounded Interest Tests      //
    ////////////////////////////////////
    function testCalculateCompoundedInterest(uint256 rate, uint40 lastUpdateTimestamp) public view {
        rate = bound(rate, 1e8, type(uint96).max);
        lastUpdateTimestamp = uint40(bound(lastUpdateTimestamp, 1, block.timestamp));

        uint256 exp = block.timestamp - uint256(lastUpdateTimestamp);
        uint256 x = (rate * exp) / Math.SECONDS_PER_YEAR;

        assertEq(
            Math.calculateCompoundedInterest(rate, lastUpdateTimestamp),
            Math.RAY + x + Math.rayMul(x, x / 2 + Math.rayMul(x, x / 6))
        );
    }

    function testCompoundedInterestExpZero() public view {
        assertEq(Math.calculateCompoundedInterest(1e27, uint40(block.timestamp)), Math.RAY);
    }

    function testCompoundedInterestExpNonZero() public {
        vm.warp(1000);

        assertGt(Math.calculateCompoundedInterest(1e27, 999), Math.RAY);
    }
}
