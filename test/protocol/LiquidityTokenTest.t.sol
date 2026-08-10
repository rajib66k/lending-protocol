// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {LiquidityToken} from "../../src/protocol/LiquidityToken.sol";
import {Pool} from "../../src/protocol/Pool.sol";
import {IPool} from "../../src/interfaces/IPool.sol";
import {Math} from "../../src/libraries/Math.sol";

contract LiquidityTokenTest is Test {
    using Math for uint256;

    LiquidityToken liquidityToken;
    IPool pool;

    address user = makeAddr("user");
    address user2 = makeAddr("user2");

    address treasury = makeAddr("treasury");
    address asset = makeAddr("asset");
    uint8 constant ASSET_DECIMALS = 18;

    function setUp() public {
        pool = new Pool();

        vm.prank(address(pool));
        liquidityToken = new LiquidityToken("Liquidity Token", "LT", treasury, address(pool), asset, ASSET_DECIMALS);
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////
    function test_Constructor() public view {
        assertEq(liquidityToken.name(), "Liquidity Token");
        assertEq(liquidityToken.symbol(), "LT");
        assertEq(liquidityToken.treasury(), treasury);
        assertEq(liquidityToken.underlyingAsset(), asset);
        assertEq(liquidityToken.owner(), address(pool));
    }

    /////////////////////////
    // Mint and Burn Tests //
    /////////////////////////
    function testMint() public {
        uint256 amount = 100 ether;

        vm.prank(address(pool));
        liquidityToken.mint(user, amount);

        assertEq(liquidityToken.scaledBalanceOf(user), amount);
        assertEq(liquidityToken.scaledTotalSupply(), amount);
    }

    function testMintRevertIfZero() public {
        vm.prank(address(pool));

        vm.expectRevert(LiquidityToken.LiquidityToken__MustBeMoreThanZero.selector);

        liquidityToken.mint(user, 0);
    }

    function testMintRevertIfNotpool() public {
        vm.prank(user);

        vm.expectRevert();

        liquidityToken.mint(user, 100 ether);
    }

    function testBurn() public {
        uint256 amount = 100 ether;
        vm.startPrank(address(pool));
        liquidityToken.mint(user, amount);
        bool result = liquidityToken.burn(user, amount);
        vm.stopPrank();

        assertTrue(result);
        assertEq(liquidityToken.scaledBalanceOf(user), 0);
        assertEq(liquidityToken.scaledTotalSupply(), 0);
    }

    function testBurnReturnsFalseIfBalanceRemains() public {
        vm.startPrank(address(pool));
        liquidityToken.mint(user, 100 ether);
        bool result = liquidityToken.burn(user, 40 ether);
        vm.stopPrank();

        assertFalse(result);
        assertEq(liquidityToken.scaledBalanceOf(user), 60 ether);
    }

    function testBurnRevertIfZero() public {
        vm.prank(address(pool));
        vm.expectRevert(LiquidityToken.LiquidityToken__MustBeMoreThanZero.selector);
        liquidityToken.burn(user, 0);
    }

    function testBurnRevertIfNotpool() public {
        vm.prank(user);
        vm.expectRevert();
        liquidityToken.burn(user, 100 ether);
    }

    //////////////////////////////
    // Transfer On Behalf Tests //
    //////////////////////////////
    function testTransferOnBehalf() public {
        vm.startPrank(address(pool));
        liquidityToken.mint(user, 100 ether);
        bool result = liquidityToken.transferOnBehalf(user, user2, 40 ether);
        vm.stopPrank();

        assertTrue(result);
        assertEq(liquidityToken.scaledBalanceOf(user), 60 ether);
        assertEq(liquidityToken.scaledBalanceOf(user2), 40 ether);
    }

    function testTransferOnBehalfRevertIfZero() public {
        vm.prank(address(pool));
        vm.expectRevert(LiquidityToken.LiquidityToken__MustBeMoreThanZero.selector);
        liquidityToken.transferOnBehalf(user, user2, 0);
    }

    function testTransferOnBehalfRevertIfNotpool() public {
        vm.prank(user);
        vm.expectRevert();
        liquidityToken.transferOnBehalf(user, user2, 100 ether);
    }

    //////////////////////
    // Mint To Treasury //
    //////////////////////
    function testMintTotreasury() public {
        uint256 amount = 100 ether;

        vm.prank(address(pool));
        liquidityToken.mintToTreasury(amount);

        assertEq(liquidityToken.scaledBalanceOf(treasury), amount);
        assertEq(liquidityToken.scaledTotalSupply(), amount);
    }

    function testMintTotreasuryRevertIfZero() public {
        vm.prank(address(pool));

        vm.expectRevert(LiquidityToken.LiquidityToken__MustBeMoreThanZero.selector);
        liquidityToken.mintToTreasury(0);
    }

    function testMintToTreasuryRevertIfNotpool() public {
        vm.prank(user);

        vm.expectRevert();
        liquidityToken.mintToTreasury(100 ether);
    }

    ///////////////////////////////////////////////
    // Decimals, BalanceOf and TotalSupply Tests //
    ///////////////////////////////////////////////
    function testDecimals() public view {
        assertEq(liquidityToken.decimals(), ASSET_DECIMALS);
    }

    function testBalanceOf() public {
        vm.prank(address(pool));
        liquidityToken.mint(user, 100 ether);

        uint256 index = pool.getReserveNormalizedIncome(asset);
        uint256 expected = liquidityToken.scaledBalanceOf(user).rayMulFloor(index);

        assertEq(liquidityToken.balanceOf(user), expected);
    }

    function testScaledBalanceOf() public {
        vm.prank(address(pool));
        liquidityToken.mint(user, 100 ether);

        assertEq(liquidityToken.scaledBalanceOf(user), 100 ether);
    }

    function testTotalSupply() public {
        vm.startPrank(address(pool));
        liquidityToken.mint(user, 100 ether);
        liquidityToken.mint(user2, 200 ether);
        vm.stopPrank();

        uint256 index = pool.getReserveNormalizedIncome(asset);
        uint256 expected = liquidityToken.scaledTotalSupply().rayMulFloor(index);

        assertEq(liquidityToken.totalSupply(), expected);
    }

    function testScaledTotalSupply() public {
        vm.startPrank(address(pool));
        liquidityToken.mint(user, 100 ether);
        liquidityToken.mint(user2, 200 ether);
        vm.stopPrank();

        assertEq(liquidityToken.scaledTotalSupply(), 300 ether);
    }

    function testBalanceOfZeroBalance() public view {
        assertEq(liquidityToken.balanceOf(user), 0);
    }

    function testTotalSupplyZero() public view {
        assertEq(liquidityToken.totalSupply(), 0);
    }

    /////////////////////////////////
    // Unsupported Functions Tests //
    /////////////////////////////////
    function testTransferRevert() public {
        vm.expectRevert(LiquidityToken.LiquidityToken__OperationNotSupported.selector);
        bool success = liquidityToken.transfer(user, 100 ether);
        assertFalse(success);
    }

    function testTransferFromRevert() public {
        vm.expectRevert(LiquidityToken.LiquidityToken__OperationNotSupported.selector);
        bool success = liquidityToken.transferFrom(user, user2, 100 ether);
        assertFalse(success);
    }

    function test_Approve_Revert() public {
        vm.expectRevert(LiquidityToken.LiquidityToken__OperationNotSupported.selector);
        liquidityToken.approve(user, 100 ether);
    }

    function testAllowance() public view {
        assertEq(liquidityToken.allowance(user, user2), 0);
    }

    ////////////////////
    // Full Flow Test //
    ////////////////////
    function testFullFlow() public {
        vm.startPrank(address(pool));
        liquidityToken.mint(user, 1_000 ether);
        liquidityToken.transferOnBehalf(user, user2, 300 ether);
        liquidityToken.mintToTreasury(100 ether);
        bool result = liquidityToken.burn(user, 700 ether);
        vm.stopPrank();

        assertTrue(result);
        assertEq(liquidityToken.scaledBalanceOf(treasury), 100 ether);
        assertEq(liquidityToken.scaledBalanceOf(user), 0);
        assertEq(liquidityToken.scaledBalanceOf(user2), 300 ether);
        assertEq(liquidityToken.scaledTotalSupply(), 400 ether);
    }
}
