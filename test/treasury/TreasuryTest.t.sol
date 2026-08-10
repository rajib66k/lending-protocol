// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {Treasury} from "../../src/treasury/Treasury.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract TreasuryTest is Test {
    Treasury treasury;
    ERC20Mock token;

    address user = makeAddr("user");
    address user2 = makeAddr("user2");

    uint256 constant TOKEN_AMOUNT = 100 ether;

    function setUp() public {
        treasury = new Treasury();
        token = new ERC20Mock();
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////
    function testConstructor() public view {
        assertEq(treasury.owner(), address(this));
    }

    //////////////////////////
    // Transfer Token Tests //
    //////////////////////////
    function testTransferToken() public {
        token.mint(address(treasury), TOKEN_AMOUNT);
        vm.expectEmit(true, true, true, true);
        emit Treasury.TokenWithdrawn(address(token), user, TOKEN_AMOUNT);
        treasury.transferToken(IERC20(address(token)), user, TOKEN_AMOUNT);

        assertEq(token.balanceOf(user), TOKEN_AMOUNT);
        assertEq(token.balanceOf(address(treasury)), 0);
    }

    function testTransferTokenRevertIfInvalidToken() public {
        vm.expectRevert(Treasury.DAOTreasury__InvalidToken.selector);
        treasury.transferToken(IERC20(address(0)), user, TOKEN_AMOUNT);
    }

    function testTransferTokenRevertIfInvalidAddress() public {
        vm.expectRevert(Treasury.DAOTreasury__InvalidAddress.selector);
        treasury.transferToken(IERC20(address(token)), address(0), TOKEN_AMOUNT);
    }

    function testTransferTokenRevertIfNotOwner() public {
        token.mint(address(treasury), TOKEN_AMOUNT);

        vm.prank(user);
        vm.expectRevert();
        treasury.transferToken(IERC20(address(token)), user2, TOKEN_AMOUNT);
    }

    function testTransferTokenRevertIfInsufficientBalance() public {
        vm.expectRevert();
        treasury.transferToken(IERC20(address(token)), user, TOKEN_AMOUNT);
    }

    /////////////////////////////
    // Get Token Balance Tests //
    /////////////////////////////
    function testGetTokenBalance() public {
        token.mint(address(treasury), TOKEN_AMOUNT);

        uint256 balance = treasury.getTokenBalance(IERC20(address(token)));

        assertEq(balance, TOKEN_AMOUNT);
    }

    function testGetTokenBalanceZero() public view {
        uint256 balance = treasury.getTokenBalance(IERC20(address(token)));

        assertEq(balance, 0);
    }

    function testGetTokenBalanceRevertIfInvalidToken() public {
        vm.expectRevert(Treasury.DAOTreasury__InvalidToken.selector);
        treasury.getTokenBalance(IERC20(address(0)));
    }

    ////////////////////
    // Full Flow Test //
    ////////////////////
    function testFullFlow() public {
        token.mint(address(treasury), 1_000 ether);

        assertEq(treasury.getTokenBalance(IERC20(address(token))), 1_000 ether);

        treasury.transferToken(IERC20(address(token)), user, 600 ether);

        assertEq(token.balanceOf(user), 600 ether);
        assertEq(treasury.getTokenBalance(IERC20(address(token))), 400 ether);

        treasury.transferToken(IERC20(address(token)), user2, 400 ether);

        assertEq(token.balanceOf(user2), 400 ether);
        assertEq(treasury.getTokenBalance(IERC20(address(token))), 0);
    }
}
