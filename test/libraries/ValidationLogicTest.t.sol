// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ValidationLogic} from "../../src/libraries/ValidationLogic.sol";
import {DataTypes} from "../../src/types/DataTypes.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {LiquidityToken} from "../../src/protocol/LiquidityToken.sol";
import {DebtToken} from "../../src/protocol/DebtToken.sol";
import {UserConfiguration} from "../../src/configuration/UserConfiguration.sol";

/// forge-config: default.allow_internal_expect_revert = true
contract ValidationLogicTest is Test {
    using ValidationLogic for uint256;
    using ValidationLogic for DataTypes.ReserveCache;
    using ValidationLogic for DataTypes.ReserveData;
    using UserConfiguration for DataTypes.UserConfiguration;

    mapping(address asset => DataTypes.ReserveData) public sReserves;
    mapping(address asset => DataTypes.ReserveCache) public sCache;
    mapping(address user => DataTypes.UserConfiguration) sUserConfig;
    address public sLiquidityToken;
    address public sDebtToken;
    address public sToken;
    address public sUser = makeAddr("user");
    address public sUser2 = makeAddr("user2");

    uint256 public constant MAX_RESERVES = 128;
    uint256 public constant MAX_RESERVES_PLUS_ONE = 129;
    uint8 public constant DECIMALS = 18;
    uint256 public constant AMOUNT = 1e18;
    uint256 public constant USER_AMOUNT = 10e18;

    function setUp() public {
        ERC20Mock token = new ERC20Mock();
        sToken = address(token);

        LiquidityToken liquidityToken = new LiquidityToken("LiqToken", "LT", address(0), address(0), sToken, DECIMALS);
        sLiquidityToken = address(liquidityToken);

        DebtToken debtToken = new DebtToken("DebToken", "DT", address(0), sToken, DECIMALS);
        sDebtToken = address(debtToken);

        LiquidityToken(sLiquidityToken).mint(sUser2, USER_AMOUNT);
    }

    //////////////////////////////
    // validateReserveInit      //
    //////////////////////////////
    function testValidateReserveInitRevertIfAssetIsZeroAddress() public {
        vm.expectRevert(ValidationLogic.ValidationLogic__InvalidAddress.selector);
        MAX_RESERVES.validateReserveInit(address(0), sToken, sToken);
    }

    function testValidateReserveInitRevertIfLiquidityTokenIsZeroAddress() public {
        vm.expectRevert(ValidationLogic.ValidationLogic__InvalidAddress.selector);
        MAX_RESERVES.validateReserveInit(sToken, address(0), sToken);
    }

    function testValidateReserveInitRevertIfDebtTokenIsZeroAddress() public {
        vm.expectRevert(ValidationLogic.ValidationLogic__InvalidAddress.selector);
        MAX_RESERVES.validateReserveInit(sToken, sToken, address(0));
    }

    function testValidateReserveInitRevertIfReserveCountTooHigh() public {
        vm.expectRevert(ValidationLogic.ValidationLogic__TooManyReserves.selector);
        MAX_RESERVES_PLUS_ONE.validateReserveInit(sToken, sToken, sToken);
    }

    function testValidateReserveInitSuccess() public view {
        MAX_RESERVES.validateReserveInit(sToken, sToken, sToken);
    }

    function testValidateReserveInitSuccessAtMaxMinusOne() public view {
        (MAX_RESERVES - 1).validateReserveInit(sToken, sToken, sToken);
    }

    ////////////////////////////////////////////
    // validateReserveActiveStatusChange      //
    ////////////////////////////////////////////
    function testValidateReserveActiveStatusChangeRevertIfAlreadyTrue() public {
        DataTypes.ReserveData storage reserve = sReserves[sToken];
        reserve.isActive = true;
        reserve.liquidityTokenAddress = sToken;

        vm.expectRevert(
            abi.encodeWithSelector(ValidationLogic.ValidationLogic__ReserveIsActiveIsAlready.selector, true)
        );
        reserve.validateReserveActiveStatusChange(true);
    }

    function testValidateReserveActiveStatusChangeRevertIfAlreadyFalse() public {
        DataTypes.ReserveData storage reserve = sReserves[sToken];
        reserve.isActive = false;
        reserve.liquidityTokenAddress = sToken;

        vm.expectRevert(
            abi.encodeWithSelector(ValidationLogic.ValidationLogic__ReserveIsActiveIsAlready.selector, false)
        );
        reserve.validateReserveActiveStatusChange(false);
    }

    function testValidateReserveActiveStatusChangeRevertIfReserveNotInitialized() public {
        DataTypes.ReserveData storage reserve = sReserves[sToken];
        reserve.isActive = true;
        reserve.liquidityTokenAddress = address(0);

        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveNotInitialized.selector);
        reserve.validateReserveActiveStatusChange(false);
    }

    function testValidateReserveActiveStatusChangeSuccess() public {
        DataTypes.ReserveData storage reserve = sReserves[sToken];
        reserve.isActive = true;
        reserve.liquidityTokenAddress = sToken;

        reserve.validateReserveActiveStatusChange(false);
    }

    /////////////////////////
    // validateSupply      //
    /////////////////////////
    function testValidateSupplyRevertIfReserveInactive() public {
        DataTypes.ReserveCache storage cache = sCache[sToken];
        cache.isActive = false;

        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveInactive.selector);
        cache.validateSupply(1);
    }

    function testValidateSupplyRevertIfAmountZero() public {
        DataTypes.ReserveCache storage cache = sCache[sToken];
        cache.isActive = true;

        vm.expectRevert(ValidationLogic.ValidationLogic__NeedsMoreThanZero.selector);
        cache.validateSupply(0);
    }

    function testValidateSupplySuccess() public {
        DataTypes.ReserveCache storage cache = sCache[sToken];
        cache.isActive = true;

        cache.validateSupply(100 ether);
    }

    ///////////////////////////
    // validateWithdraw      //
    ///////////////////////////
    function testValidateWithdrawRevertIfReserveInactive() public {
        DataTypes.ReserveCache storage cache = sCache[sToken];
        cache.isActive = false;

        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveInactive.selector);
        ValidationLogic.validateWithdraw(cache, sUser2, sToken, AMOUNT, AMOUNT, ValidationLogic.MIN_HEALTH_FACTOR);
    }

    function testValidateWithdrawRevertIfScaledAmountIsZero() public {
        DataTypes.ReserveCache storage cache = sCache[sToken];
        cache.isActive = true;

        vm.expectRevert(ValidationLogic.ValidationLogic__NeedsMoreThanZero.selector);
        ValidationLogic.validateWithdraw(cache, sUser, sToken, 0, 0, AMOUNT);
    }

    function testValidateWithdrawRevertIfHealthFactorIsBroken() public {
        DataTypes.ReserveCache storage cache = sCache[sToken];
        cache.isActive = true;
        cache.liquidityTokenAddress = sLiquidityToken;

        vm.expectRevert(ValidationLogic.ValidationLogic__BreaksHealthFactor.selector);
        ValidationLogic.validateWithdraw(cache, sUser2, sToken, AMOUNT, AMOUNT, ValidationLogic.MIN_HEALTH_FACTOR - 1);
    }

    function testValidateWithdrawSuccess() public {
        DataTypes.ReserveCache storage cache = sCache[sToken];
        cache.isActive = true;
        cache.liquidityTokenAddress = sLiquidityToken;

        ERC20Mock(sToken).mint(address(this), USER_AMOUNT);

        ValidationLogic.validateWithdraw(cache, sUser2, sToken, AMOUNT, AMOUNT, ValidationLogic.MIN_HEALTH_FACTOR);
    }

    /////////////////////////
    // validateRepay       //
    /////////////////////////
    function testValidateRepayRevertIfReserveInactive() public {
        DataTypes.ReserveCache storage cache = sCache[sToken];
        cache.isActive = false;

        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveInactive.selector);
        cache.validateRepay(1);
    }

    function testValidateRepayRevertIfScaledDebtIsZero() public {
        DataTypes.ReserveCache storage cache = sCache[sToken];
        cache.isActive = true;

        vm.expectRevert(ValidationLogic.ValidationLogic__NeedsMoreThanZero.selector);
        cache.validateRepay(0);
    }

    function testValidateRepaySuccess() public {
        DataTypes.ReserveCache storage cache = sCache[sToken];
        cache.isActive = true;

        cache.validateRepay(AMOUNT);
    }

    /////////////////////////
    // validateAmount      //
    /////////////////////////
    function testValidateAmountRevertIfZero() public {
        vm.expectRevert(ValidationLogic.ValidationLogic__NeedsMoreThanZero.selector);
        ValidationLogic.validateAmount(0);
    }

    function testValidateAmountSuccess() public pure {
        ValidationLogic.validateAmount(1);
    }

    ////////////////////////////////
    // validateReserveActive      //
    ////////////////////////////////
    function testValidateReserveActiveRevertIfInactive() public {
        DataTypes.ReserveCache storage cache = sCache[sToken];
        cache.isActive = false;

        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveInactive.selector);
        cache.validateReserveActive();
    }

    function testValidateReserveActiveSuccess() public {
        DataTypes.ReserveCache storage cache = sCache[sToken];
        cache.isActive = true;

        cache.validateReserveActive();
    }

    /////////////////////////////////////////
    // validateUserHaveEnoughBalance       //
    /////////////////////////////////////////
    function testValidateUserHaveEnoughBalanceRevertIfNotEnough() public {
        vm.expectRevert(ValidationLogic.ValidationLogic__UserHasNotEnoughBalance.selector);

        ValidationLogic.validateUserHaveEnoughBalance(10, 11);
    }

    function testValidateUserHaveEnoughBalanceSuccessIfEqual() public pure {
        ValidationLogic.validateUserHaveEnoughBalance(10, 10);
    }

    function testValidateUserHaveEnoughBalanceSuccessIfGreater() public pure {
        ValidationLogic.validateUserHaveEnoughBalance(11, 10);
    }

    //////////////////////////////////////////////
    // validateUserHealthFactorAfterAction      //
    //////////////////////////////////////////////
    function testValidateUserHealthFactorAfterActionRevert() public {
        vm.expectRevert(ValidationLogic.ValidationLogic__BreaksHealthFactor.selector);

        ValidationLogic.validateUserHealthFactorAfterAction(ValidationLogic.MIN_HEALTH_FACTOR - 1);
    }

    function testValidateUserHealthFactorAfterActionSuccessEqual() public pure {
        ValidationLogic.MIN_HEALTH_FACTOR.validateUserHealthFactorAfterAction();
    }

    function testValidateUserHealthFactorAfterActionSuccessGreater() public pure {
        ValidationLogic.MIN_HEALTH_FACTOR.validateUserHealthFactorAfterAction();
    }

    //////////////////////////////////////////////////
    // validateTransferLiquidityTokenSuccessful     //
    //////////////////////////////////////////////////
    function testValidateTransferLiquidityTokenSuccessfulRevert() public {
        vm.expectRevert(ValidationLogic.ValidationLogic__TransferFailed.selector);

        ValidationLogic.validateTransferLiquidityTokenSuccessful(false);
    }

    function testValidateTransferLiquidityTokenSuccessfulSuccess() public pure {
        ValidationLogic.validateTransferLiquidityTokenSuccessful(true);
    }

    //////////////////////////////
    // validateReserveExists    //
    //////////////////////////////
    function testValidateReserveExistsRevert() public {
        DataTypes.ReserveData storage reserve = sReserves[sToken];
        reserve.liquidityTokenAddress = address(0);

        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveDoesNotExist.selector);
        ValidationLogic.validateReserveExists(reserve);
    }

    function testValidateReserveExistsSuccess() public {
        DataTypes.ReserveData storage reserve = sReserves[sToken];
        reserve.liquidityTokenAddress = sToken;
        ValidationLogic.validateReserveExists(reserve);
    }

    //////////////////////////
    // validateBorrow       //
    //////////////////////////
    function testValidateBorrowRevertIfReserveInactive() public {
        DataTypes.ReserveCache storage cache = sCache[sToken];
        cache.isActive = false;

        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveInactive.selector);
        ValidationLogic.validateBorrow(
            cache, sUserConfig[sUser], sToken, AMOUNT, AMOUNT, ValidationLogic.MIN_HEALTH_FACTOR
        );
    }

    function testValidateBorrowRevertIfScaledAmountIsZero() public {
        DataTypes.ReserveCache storage cache = sCache[sToken];
        cache.isActive = true;

        vm.expectRevert(ValidationLogic.ValidationLogic__NeedsMoreThanZero.selector);
        ValidationLogic.validateBorrow(cache, sUserConfig[sUser], sToken, AMOUNT, 0, ValidationLogic.MIN_HEALTH_FACTOR);
    }

    function testValidateBorrowRevertIfUserHasNoCollateral() public {
        DataTypes.ReserveCache storage cache = sCache[sToken];
        cache.isActive = true;

        vm.expectRevert(ValidationLogic.ValidationLogic__NotUsingAsCollateral.selector);
        ValidationLogic.validateBorrow(
            cache, sUserConfig[sUser], sToken, AMOUNT, AMOUNT, ValidationLogic.MIN_HEALTH_FACTOR
        );
    }

    function testValidateBorrowRevertIfHealthFactorBroken() public {
        DataTypes.ReserveCache storage cache = sCache[sToken];
        cache.isActive = true;

        sUserConfig[sUser].setCollateral(0, true);

        vm.expectRevert(ValidationLogic.ValidationLogic__BreaksHealthFactor.selector);
        ValidationLogic.validateBorrow(
            cache, sUserConfig[sUser], sToken, AMOUNT, AMOUNT, ValidationLogic.MIN_HEALTH_FACTOR - 1
        );
    }

    function testValidateBorrowSuccess() public {
        DataTypes.ReserveCache storage cache = sCache[sToken];
        cache.isActive = true;

        sUserConfig[sUser].setCollateral(0, true);

        ERC20Mock(sToken).mint(address(this), 100 ether);
        ValidationLogic.validateBorrow(
            cache, sUserConfig[sUser], sToken, AMOUNT, AMOUNT, ValidationLogic.MIN_HEALTH_FACTOR
        );
    }

    //////////////////////////////////////
    // validateSetUseAsCollateral      //
    //////////////////////////////////////
    function testValidateSetUseAsCollateralRevertIfReserveInactive() public {
        DataTypes.ReserveData storage reserve = sReserves[sToken];
        reserve.isActive = false;

        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveInactive.selector);
        reserve.validateSetUseAsCollateral(sUser2, true);
    }

    function testValidateSetUseAsCollateralSuccessDisable() public {
        DataTypes.ReserveData storage reserve = sReserves[sToken];
        reserve.isActive = true;
        reserve.liquidityTokenAddress = sLiquidityToken;

        reserve.validateSetUseAsCollateral(sUser2, false);
    }

    function testValidateSetUseAsCollateralSuccessEnable() public {
        DataTypes.ReserveData storage reserve = sReserves[sToken];
        reserve.isActive = true;
        reserve.liquidityTokenAddress = sLiquidityToken;

        reserve.validateSetUseAsCollateral(sUser2, true);
    }

    //////////////////////////////////////////////
    // validateSetUseAsCollateralInternal      //
    //////////////////////////////////////////////
    function testValidateSetUseAsCollateralInternalRevertTrue() public {
        sUserConfig[sUser].setCollateral(0, true);

        vm.expectRevert(
            abi.encodeWithSelector(ValidationLogic.ValidationLogic__AlreadyUsingAsCollateralIs.selector, true)
        );
        ValidationLogic.validateSetUseAsCollateralInternal(0, sUserConfig[sUser], true);
    }

    function testValidateSetUseAsCollateralInternalRevertFalse() public {
        vm.expectRevert(
            abi.encodeWithSelector(ValidationLogic.ValidationLogic__AlreadyUsingAsCollateralIs.selector, false)
        );
        ValidationLogic.validateSetUseAsCollateralInternal(0, sUserConfig[sUser], false);
    }

    function testValidateSetUseAsCollateralInternalSuccess() public view {
        ValidationLogic.validateSetUseAsCollateralInternal(0, sUserConfig[sUser], true);
    }

    ////////////////////////////////
    // validateSetAsBorrowing     //
    ////////////////////////////////
    function testValidateSetAsBorrowingRevertTrue() public {
        sUserConfig[sUser].setBorrowing(0, true);

        vm.expectRevert(abi.encodeWithSelector(ValidationLogic.ValidationLogic__AlreadyBorrowingIs.selector, true));
        ValidationLogic.validateSetAsBorrowing(0, sUserConfig[sUser], true);
    }

    function testValidateSetAsBorrowingRevertFalse() public {
        vm.expectRevert(abi.encodeWithSelector(ValidationLogic.ValidationLogic__AlreadyBorrowingIs.selector, false));
        ValidationLogic.validateSetAsBorrowing(0, sUserConfig[sUser], false);
    }

    function testValidateSetAsBorrowingSuccess() public view {
        ValidationLogic.validateSetAsBorrowing(0, sUserConfig[sUser], true);
    }

    /////////////////////////////////////////
    // validateTransferLiquidityToken      //
    /////////////////////////////////////////
    function testValidateTransferLiquidityTokenRevertIfReserveInactive() public {
        DataTypes.ReserveCache storage cache = sCache[sToken];
        cache.isActive = false;

        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveInactive.selector);
        ValidationLogic.validateTransferLiquidityToken(cache, address(this), 1, ValidationLogic.MIN_HEALTH_FACTOR);
    }

    function testValidateTransferLiquidityTokenRevertIfHealthFactorBroken() public {
        DataTypes.ReserveCache storage cache = sCache[sToken];
        cache.isActive = true;

        vm.expectRevert(ValidationLogic.ValidationLogic__BreaksHealthFactor.selector);
        ValidationLogic.validateTransferLiquidityToken(cache, address(this), 1, ValidationLogic.MIN_HEALTH_FACTOR - 1);
    }

    function testValidateTransferLiquidityTokenSuccess() public {
        DataTypes.ReserveCache storage cache = sCache[sToken];
        cache.isActive = true;
        cache.liquidityTokenAddress = sLiquidityToken;

        ValidationLogic.validateTransferLiquidityToken(cache, sUser2, 10, ValidationLogic.MIN_HEALTH_FACTOR);
    }

    //////////////////////////////////////////////////
    // validateTransferLiquidityTokenInternal       //
    //////////////////////////////////////////////////
    function testValidateTransferLiquidityTokenInternalRevertIfAmountZero() public {
        vm.expectRevert(ValidationLogic.ValidationLogic__NeedsMoreThanZero.selector);
        ValidationLogic.validateTransferLiquidityTokenInternal(0, sLiquidityToken, sUser);
    }

    function testValidateTransferLiquidityTokenInternalSuccess() public view {
        ValidationLogic.validateTransferLiquidityTokenInternal(AMOUNT, sLiquidityToken, sUser2);
    }

    ///////////////////////////////
    // validatePoolLiquidity     //
    ///////////////////////////////
    function testValidatePoolLiquiditySuccess() public {
        ERC20Mock(sToken).mint(address(this), 100 ether);

        ValidationLogic.validatePoolLiquidity(sToken, AMOUNT);
    }

    //////////////////////////////
    // validateLiquidation      //
    //////////////////////////////
    function testValidateLiquidationRevertIfCollateralReserveInactive() public {
        DataTypes.ReserveCache storage collateralCache = sCache[sToken];
        DataTypes.ReserveCache storage debtCache = sCache[address(1)];

        collateralCache.isActive = false;
        debtCache.isActive = true;

        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveInactive.selector);
        ValidationLogic.validateLiquidation(collateralCache, debtCache, sUserConfig[sUser], address(this), 0, 1e18);
    }

    function testValidateLiquidationRevertIfDebtReserveInactive() public {
        DataTypes.ReserveCache storage collateralCache = sCache[sToken];
        DataTypes.ReserveCache storage debtCache = sCache[address(1)];

        collateralCache.isActive = true;
        debtCache.isActive = false;

        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveInactive.selector);
        ValidationLogic.validateLiquidation(collateralCache, debtCache, sUserConfig[sUser], address(this), 0, 1e18);
    }

    function testValidateLiquidationRevertIfHealthFactorBroken() public {
        DataTypes.ReserveCache storage collateralCache = sCache[sToken];
        DataTypes.ReserveCache storage debtCache = sCache[address(1)];

        collateralCache.isActive = true;
        debtCache.isActive = true;

        vm.expectRevert(ValidationLogic.ValidationLogic__BreaksHealthFactor.selector);
        ValidationLogic.validateLiquidation(collateralCache, debtCache, sUserConfig[sUser], address(this), 0, 1e18 - 1);
    }

    function testValidateLiquidationRevertIfReserveNotUsedAsCollateral() public {
        DataTypes.ReserveCache storage collateralCache = sCache[sToken];
        DataTypes.ReserveCache storage debtCache = sCache[address(1)];

        collateralCache.isActive = true;
        debtCache.isActive = true;

        vm.expectRevert(ValidationLogic.ValidationLogic__NotUsingAsCollateral.selector);
        ValidationLogic.validateLiquidation(collateralCache, debtCache, sUserConfig[sUser], address(this), 0, 1e18);
    }
}
