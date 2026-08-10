// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {DebtToken} from "../../src/protocol/DebtToken.sol";
import {Pool} from "../../src/protocol/Pool.sol";
import {IPool} from "../../src/interfaces/IPool.sol";
import {Math} from "../../src/libraries/Math.sol";

contract DebtTokenTest is Test {
    using Math for uint256;

    DebtToken debtToken;
    IPool pool;

    address user = makeAddr("user");
    address user2 = makeAddr("user2");
    address asset = makeAddr("asset");

    uint8 constant ASSET_DECIMALS = 18;

    function setUp() public {
        pool = new Pool();

        vm.prank(address(pool));
        debtToken = new DebtToken("Debt Token", "DT", address(pool), asset, ASSET_DECIMALS);
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////
    function testConstructor() public view {
        assertEq(debtToken.name(), "Debt Token");
        assertEq(debtToken.symbol(), "DT");
        assertEq(debtToken.owner(), address(pool));
    }

    ///////////////////////////
    // Mint and Burn Tests //
    ///////////////////////////
    function testMint() public {
        uint256 amount = 100 ether;

        vm.prank(address(pool));
        debtToken.mint(user, amount);

        assertEq(debtToken.scaledBalanceOf(user), amount);
        assertEq(debtToken.scaledTotalSupply(), amount);
    }

    function testMintRevertIfZero() public {
        vm.prank(address(pool));
        vm.expectRevert(DebtToken.DebtToken__MustBeMoreThanZero.selector);
        debtToken.mint(user, 0);
    }

    function testMintRevertIfNotpool() public {
        vm.prank(user);
        vm.expectRevert();
        debtToken.mint(user, 100 ether);
    }

    function testBurn() public {
        uint256 amount = 100 ether;

        vm.startPrank(address(pool));
        debtToken.mint(user, amount);
        bool result = debtToken.burn(user, amount);
        vm.stopPrank();

        assertTrue(result);
        assertEq(debtToken.scaledBalanceOf(user), 0);
        assertEq(debtToken.scaledTotalSupply(), 0);
    }

    function testBurnReturnsFalseIfBalanceRemains() public {
        vm.startPrank(address(pool));
        debtToken.mint(user, 100 ether);
        bool result = debtToken.burn(user, 40 ether);
        vm.stopPrank();

        assertFalse(result);
        assertEq(debtToken.scaledBalanceOf(user), 60 ether);
    }

    function testBurnRevertIfZero() public {
        vm.prank(address(pool));
        vm.expectRevert(DebtToken.DebtToken__MustBeMoreThanZero.selector);
        debtToken.burn(user, 0);
    }

    function testBurnRevertIfNotpool() public {
        vm.prank(user);
        vm.expectRevert();
        debtToken.burn(user, 100 ether);
    }

    ////////////////////////////
    // Decimals and BalanceOf //
    ////////////////////////////
    function testDecimals() public view {
        assertEq(debtToken.decimals(), ASSET_DECIMALS);
    }

    function testBalanceOf() public {
        vm.prank(address(pool));
        debtToken.mint(user, 100 ether);

        uint256 index = pool.getReserveNormalizedDebt(asset);
        uint256 expected = debtToken.scaledBalanceOf(user).rayMul(index);

        assertEq(debtToken.balanceOf(user), expected);
    }

    function testScaledBalanceOf() public {
        vm.prank(address(pool));
        debtToken.mint(user, 100 ether);

        assertEq(debtToken.scaledBalanceOf(user), 100 ether);
    }

    function testTotalSupply() public {
        vm.startPrank(address(pool));
        debtToken.mint(user, 100 ether);
        debtToken.mint(user2, 200 ether);
        vm.stopPrank();

        uint256 index = pool.getReserveNormalizedDebt(asset);
        uint256 expected = debtToken.scaledTotalSupply().rayMul(index);

        assertEq(debtToken.totalSupply(), expected);
    }

    function testScaledTotalSupply() public {
        vm.startPrank(address(pool));
        debtToken.mint(user, 100 ether);
        debtToken.mint(user2, 200 ether);
        vm.stopPrank();

        assertEq(debtToken.scaledTotalSupply(), 300 ether);
    }

    function testBalanceOfZeroBalance() public view {
        assertEq(debtToken.balanceOf(user), 0);
    }

    function testTotalSupplyZero() public view {
        assertEq(debtToken.totalSupply(), 0);
    }

    /////////////////////////////////
    // Unsupported Functions Tests //
    /////////////////////////////////
    function testTransferRevert() public {
        vm.expectRevert(DebtToken.DebtToken__OperationNotSupported.selector);
        bool success = debtToken.transfer(user, 100 ether);
        assertFalse(success);
    }

    function testTransferFromRevert() public {
        vm.expectRevert(DebtToken.DebtToken__OperationNotSupported.selector);
        bool success = debtToken.transferFrom(user, user2, 100 ether);
        assertFalse(success);
    }

    function testApproveRevert() public {
        vm.expectRevert(DebtToken.DebtToken__OperationNotSupported.selector);
        debtToken.approve(user, 100 ether);
    }

    function testAllowance() public view {
        assertEq(debtToken.allowance(user, user2), 0);
    }

    ////////////////////
    // Full Flow Test //
    ////////////////////
    function testFullFlow() public {
        vm.startPrank(address(pool));
        debtToken.mint(user, 1_000 ether);
        bool result = debtToken.burn(user, 300 ether);
        vm.stopPrank();

        assertFalse(result);
        assertEq(debtToken.scaledBalanceOf(user), 700 ether);
        assertEq(debtToken.scaledTotalSupply(), 700 ether);
    }
}
