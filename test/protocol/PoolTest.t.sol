// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test, console} from "forge-std/Test.sol";
import {DeployPool} from "../../script/DeployPool.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Pool} from "../../src/protocol/Pool.sol";
import {Treasury} from "../../src/treasury/Treasury.sol";
import {LiquidityToken} from "../../src/protocol/LiquidityToken.sol";
import {DebtToken} from "../../src/protocol/DebtToken.sol";
import {DataTypes} from "../../src/types/DataTypes.sol";
import {ValidationLogic} from "../../src/libraries/ValidationLogic.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "../../src/libraries/Math.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {MockV3Aggregator} from "./../mocks/MockV3Aggregator.sol";

contract PoolTest is Test {
    using Math for uint256;
    using SafeCast for uint256;

    DeployPool public deploy;
    HelperConfig.NetworkConfig public netConfig;
    HelperConfig public config;
    Pool public pool;
    Treasury public treasury;

    LiquidityToken public lTokenWeth;
    DebtToken public dTokenWeth;
    LiquidityToken public lTokenWbtc;
    DebtToken public dTokenWbtc;

    HelperConfig.ReserveConfig public wethReserveConfig;
    HelperConfig.ReserveConfig public wbtcReserveConfig;

    address user = makeAddr("user");
    address user2 = makeAddr("user2");

    address public constant ANVIL_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 public constant MAX_RESERVES = 128;
    uint256 public constant AMOUNT = 1e18;
    uint256 public constant USER_AMOUNT = 10e18;

    event ReserveInitialized(
        address indexed asset,
        address indexed liquidityToken,
        address indexed debtToken,
        DataTypes.InterestRateParams params,
        DataTypes.FeedData feed,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 reserveFactor,
        uint256 id
    );

    event ReserveStatusUpdated(address indexed asset, bool isActive);
    event InterestRateParamsUpdated(address indexed asset, DataTypes.InterestRateParams params);
    event FeedDataUpdated(address indexed asset, DataTypes.FeedData feed);
    event ReserveDataUpdated(
        address indexed asset, uint256 liquidationThreshold, uint256 liquidationBonus, uint256 reserveFactor
    );

    event Supply(address indexed asset, address user, address indexed onBehalfOf, uint256 amount);
    event Withdraw(address indexed asset, address indexed user, address indexed to, uint256 amount);
    event Borrow(address indexed asset, address indexed user, uint256 amount);
    event Repay(
        address indexed reserve, address indexed user, address indexed repayer, uint256 amount, bool useATokens
    );

    event LiquidationCall(
        address indexed collateralAsset,
        address indexed debtAsset,
        address indexed user,
        address liquidator,
        uint256 debtRepaid,
        uint256 collateralLiquidated,
        bool receiveATokens
    );

    function setUp() public {
        deploy = new DeployPool();

        DeployPool.AssetData[] memory assetData;

        (pool, config, treasury, assetData) = deploy.run();
        console.log("assetData length", assetData.length);
        netConfig = config.getActiveNetworkConfig();

        lTokenWeth = assetData[0].lToken;
        dTokenWeth = assetData[0].dToken;

        lTokenWbtc = assetData[1].lToken;
        dTokenWbtc = assetData[1].dToken;

        wethReserveConfig = netConfig.wethReserveConfig;
        wbtcReserveConfig = netConfig.wbtcReserveConfig;

        ERC20Mock(netConfig.weth).mint(user, USER_AMOUNT);
    }

    /////////////////
    // Helpers     //
    /////////////////
    function initWethReserve() public {
        initReserveWithInput(netConfig.weth, address(lTokenWeth), address(dTokenWeth));
    }

    function initWbtcReserve() public {
        pool.initializeReserve(
            netConfig.wbtc,
            address(lTokenWbtc),
            address(dTokenWbtc),
            wbtcReserveConfig.liquidationThreshold,
            wbtcReserveConfig.liquidationBonus,
            wbtcReserveConfig.reserveFactor,
            netConfig.wbtcParams,
            netConfig.wbtcFeed
        );
    }

    function initReserveWithInput(address asset, address liqToken, address debtToken) public {
        pool.initializeReserve(
            asset,
            liqToken,
            debtToken,
            wethReserveConfig.liquidationThreshold,
            wethReserveConfig.liquidationBonus,
            wethReserveConfig.reserveFactor,
            netConfig.wethParams,
            netConfig.wethFeed
        );
    }

    function mintAndApprove(address asset, address supplier, uint256 amount) public {
        IERC20(asset).approve(address(pool), amount);
        ERC20Mock(asset).mint(supplier, amount);
    }

    function supplyUpdateReserveTest(
        address asset,
        uint256 amount,
        address supplier,
        function(address, uint256) internal action
    ) internal {
        uint256 beforeLiquidityIndex = pool.getReserveData(asset).liquidityIndex;
        uint256 beforeBorrowIndex = pool.getReserveData(asset).borrowIndex;

        vm.startPrank(supplier);
        mintAndApprove(asset, supplier, amount);
        action(asset, amount);
        vm.stopPrank();

        assertGe(pool.getReserveData(asset).liquidityIndex, beforeLiquidityIndex);
        assertGe(pool.getReserveData(asset).borrowIndex, beforeBorrowIndex);
        assertEq(
            Math.calculateLinearInterest(pool.getReserveData(asset).currentLiquidityRate, block.timestamp.toUint40())
                .rayMul(pool.getReserveData(asset).liquidityIndex),
            pool.getReserveData(asset).liquidityIndex
        );
        assertEq(
            Math.calculateCompoundedInterest(pool.getReserveData(asset).currentBorrowRate, block.timestamp.toUint40())
                .rayMul(pool.getReserveData(asset).borrowIndex),
            pool.getReserveData(asset).borrowIndex
        );
    }

    function doSupplyUser(address asset, uint256 amount) internal {
        pool.supply(asset, amount, user);
    }

    function doSupplyUser2(address asset, uint256 amount) internal {
        pool.supply(asset, amount, user2);
    }

    function doWithdrawUser2(address asset, uint256 amount) internal {
        pool.withdraw(asset, amount, user2);
    }

    function doBorrow(address asset, uint256 amount) internal {
        pool.borrow(asset, amount);
    }

    function doRepayUser2(address asset, uint256 amount) internal {
        pool.repay(asset, amount, user2);
    }

    function doRepayWithLiquidityTokensUser2(address asset, uint256 amount) internal {
        pool.repayWithLiquidityTokens(asset, amount);
    }

    /////////////////////////////
    // InitializeReserve Tests //
    /////////////////////////////
    function testInitializeReserveRevertsIfNotOwnerOrZeroAddressOrReserveCountTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        initWethReserve();

        vm.startPrank(ANVIL_ADDRESS);
        vm.expectRevert(ValidationLogic.ValidationLogic__InvalidAddress.selector);
        initReserveWithInput(address(0), address(lTokenWeth), address(dTokenWeth));

        vm.expectRevert(ValidationLogic.ValidationLogic__InvalidAddress.selector);
        initReserveWithInput(netConfig.weth, address(0), address(dTokenWeth));

        vm.expectRevert(ValidationLogic.ValidationLogic__InvalidAddress.selector);
        initReserveWithInput(netConfig.weth, address(lTokenWeth), address(0));

        for (uint256 i = 0; i < MAX_RESERVES; i++) {
            initReserveWithInput(makeAddr(vm.toString(i)), makeAddr(vm.toString(i)), makeAddr(vm.toString(i)));
        }

        vm.expectRevert(ValidationLogic.ValidationLogic__TooManyReserves.selector);
        initWethReserve();
        vm.stopPrank();

        vm.assertEq(pool.getReserveCount(), 128);
    }

    function testInitializeReserve() public {
        vm.prank(ANVIL_ADDRESS);

        vm.expectEmit(true, true, true, true);
        emit ReserveInitialized(
            netConfig.weth,
            address(lTokenWeth),
            address(dTokenWeth),
            netConfig.wethParams,
            netConfig.wethFeed,
            wethReserveConfig.liquidationThreshold,
            wethReserveConfig.liquidationBonus,
            wethReserveConfig.reserveFactor,
            0
        );
        initWethReserve();

        DataTypes.ReserveData memory reserve = pool.getReserveData(netConfig.weth);
        DataTypes.InterestRateParams memory params = pool.getInterestRateParams(netConfig.weth);
        DataTypes.FeedData memory feed = pool.getFeedData(netConfig.weth);

        assertEq(1e27, reserve.liquidityIndex);
        assertEq(1e27, reserve.borrowIndex);
        assertEq(0, reserve.currentLiquidityRate);
        assertEq(0, reserve.currentBorrowRate);
        assertEq(wethReserveConfig.liquidationThreshold, reserve.liquidationThreshold);
        assertEq(wethReserveConfig.liquidationBonus, reserve.liquidationBonus);
        assertEq(wethReserveConfig.reserveFactor, reserve.reserveFactor);
        assertEq(0, reserve.id);
        assertEq(0, reserve.lastUpdate);
        assertEq(true, reserve.isActive);
        assertEq(address(lTokenWeth), reserve.liquidityTokenAddress);
        assertEq(address(dTokenWeth), reserve.debtTokenAddress);
        assertEq(netConfig.wethParams.optimalUsageRatio, params.optimalUsageRatio);
        assertEq(netConfig.wethParams.baseBorrowRate, params.baseBorrowRate);
        assertEq(netConfig.wethParams.variableRateSlope1, params.variableRateSlope1);
        assertEq(netConfig.wethParams.variableRateSlope2, params.variableRateSlope2);
        assertEq(netConfig.wethFeed.priceFeedAddress, feed.priceFeedAddress);
        assertEq(netConfig.wethFeed.feedDecimals, feed.feedDecimals);
        assertEq(netConfig.wethFeed.tokenDecimals, feed.tokenDecimals);
    }

    ///////////////////////////////
    // UpdateReserveActive Tests //
    ///////////////////////////////
    function testUpdateReserveActiveRevertsIfNotOwnerOrReserveActiveSameAsInputOrReserveIsNotAvailable() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        pool.updateReserveActive(netConfig.weth, true);

        vm.startPrank(ANVIL_ADDRESS);
        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveDoesNotExist.selector);
        pool.updateReserveActive(netConfig.weth, true);

        initWethReserve();
        vm.expectRevert(
            abi.encodeWithSelector(ValidationLogic.ValidationLogic__ReserveIsActiveIsAlready.selector, true)
        );
        pool.updateReserveActive(netConfig.weth, true);

        pool.updateReserveActive(netConfig.weth, false);

        vm.expectRevert(
            abi.encodeWithSelector(ValidationLogic.ValidationLogic__ReserveIsActiveIsAlready.selector, false)
        );
        pool.updateReserveActive(netConfig.weth, false);
        vm.stopPrank();
    }

    function testUpdateReserveActive() public {
        vm.startPrank(ANVIL_ADDRESS);
        initWethReserve();

        vm.expectEmit(true, true, true, true);
        emit ReserveStatusUpdated(netConfig.weth, false);
        pool.updateReserveActive(netConfig.weth, false);
        vm.expectEmit(true, true, true, true);
        emit ReserveStatusUpdated(netConfig.weth, true);
        pool.updateReserveActive(netConfig.weth, true);
        vm.stopPrank();
    }

    ////////////////////////////////////
    // UpdateInterestRateParams Tests //
    ////////////////////////////////////
    function testUpdateInterestRateParamsRevertIfNotOwnerOrReserveIsNotAvailable() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        pool.updateInterestRateParams(netConfig.weth, netConfig.wethParams);

        vm.startPrank(ANVIL_ADDRESS);
        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveDoesNotExist.selector);
        pool.updateInterestRateParams(netConfig.weth, netConfig.wethParams);
        vm.stopPrank();
    }

    function testUpdateInterestRateParams() public {
        vm.startPrank(ANVIL_ADDRESS);
        initWethReserve();
        vm.expectEmit(true, true, true, true);
        emit InterestRateParamsUpdated(netConfig.weth, netConfig.wethParams);
        pool.updateInterestRateParams(netConfig.weth, netConfig.wethParams);
        vm.stopPrank();
    }

    //////////////////////////
    // UpdateFeedData Tests //
    //////////////////////////
    function testUpdateFeedDataRevertIfNotOwnerOrReserveIsNotAvailable() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        pool.updateFeedData(netConfig.weth, netConfig.wethFeed);

        vm.startPrank(ANVIL_ADDRESS);
        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveDoesNotExist.selector);
        pool.updateFeedData(netConfig.weth, netConfig.wethFeed);
        vm.stopPrank();
    }

    function testUpdateFeedData() public {
        vm.startPrank(ANVIL_ADDRESS);
        initWethReserve();
        vm.expectEmit(true, true, true, true);
        emit FeedDataUpdated(netConfig.weth, netConfig.wethFeed);
        pool.updateFeedData(netConfig.weth, netConfig.wethFeed);
        vm.stopPrank();
    }

    /////////////////////////////
    // UpdateReserveData Tests //
    /////////////////////////////
    function testUpdateReserveDataRevertIfNotOwnerOrReserveIsNotAvailable() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        pool.updateReserveData(
            netConfig.weth,
            wethReserveConfig.liquidationThreshold,
            wethReserveConfig.liquidationBonus,
            wethReserveConfig.reserveFactor
        );

        vm.startPrank(ANVIL_ADDRESS);
        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveDoesNotExist.selector);
        pool.updateReserveData(
            netConfig.weth,
            wethReserveConfig.liquidationThreshold,
            wethReserveConfig.liquidationBonus,
            wethReserveConfig.reserveFactor
        );
        vm.stopPrank();
    }

    function testUpdateReserveData() public {
        vm.startPrank(ANVIL_ADDRESS);
        initWethReserve();
        vm.expectEmit(true, true, true, true);
        emit ReserveDataUpdated(
            netConfig.weth,
            wethReserveConfig.liquidationThreshold,
            wethReserveConfig.liquidationBonus,
            wethReserveConfig.reserveFactor
        );
        pool.updateReserveData(
            netConfig.weth,
            wethReserveConfig.liquidationThreshold,
            wethReserveConfig.liquidationBonus,
            wethReserveConfig.reserveFactor
        );
        vm.stopPrank();
    }

    //////////////////
    // Supply Tests //
    //////////////////
    function testSupplyRevertIfReserveIsNotAvailableOrScaledAmountIsZero() public {
        vm.startPrank(ANVIL_ADDRESS);
        initWethReserve();
        pool.updateReserveActive(netConfig.weth, false);
        vm.stopPrank();

        vm.startPrank(user);
        IERC20(netConfig.weth).approve(address(pool), type(uint256).max);
        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveInactive.selector);
        pool.supply(netConfig.weth, AMOUNT, user);
        vm.stopPrank();

        vm.prank(ANVIL_ADDRESS);
        pool.updateReserveActive(netConfig.weth, true);

        vm.startPrank(user);
        vm.expectRevert(ValidationLogic.ValidationLogic__NeedsMoreThanZero.selector);
        pool.supply(netConfig.weth, 0, user);
        vm.stopPrank();
    }

    function testSupply(uint256 amount) public {
        amount = bound(amount, 1e8, type(uint128).max);

        vm.startPrank(ANVIL_ADDRESS);
        initWethReserve();
        vm.stopPrank();

        vm.startPrank(user2);
        mintAndApprove(netConfig.weth, user2, amount);
        vm.expectEmit(true, true, true, true);
        emit Supply(netConfig.weth, user2, user2, amount);
        pool.supply(netConfig.weth, amount, user2);
        vm.stopPrank();

        assertEq(amount, IERC20(netConfig.weth).balanceOf(address(pool)));
        assertEq(amount, lTokenWeth.balanceOf(user2));
    }

    ////////////////////
    // Withdraw Tests //
    ////////////////////
    function testWithdrawRevertIfReserveInActiveOrScaledAmntIsZeroOrHFIsBadOrNotEnoughLiquidityOrNotHaveBalance()
        public
    {
        vm.startPrank(ANVIL_ADDRESS);
        initWethReserve();
        pool.updateReserveActive(netConfig.weth, false);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveInactive.selector);
        pool.withdraw(netConfig.weth, AMOUNT, user);
        vm.stopPrank();

        vm.prank(ANVIL_ADDRESS);
        pool.updateReserveActive(netConfig.weth, true);

        vm.startPrank(user);
        vm.expectRevert(ValidationLogic.ValidationLogic__NeedsMoreThanZero.selector);
        pool.withdraw(netConfig.weth, 0, user);

        vm.expectRevert(ValidationLogic.ValidationLogic__PoolHasNotEnoughLiquidity.selector);
        pool.withdraw(netConfig.weth, AMOUNT, user);

        ERC20Mock(netConfig.weth).mint(address(pool), AMOUNT);

        vm.expectRevert(ValidationLogic.ValidationLogic__UserHasNotEnoughBalance.selector);
        pool.withdraw(netConfig.weth, AMOUNT, user2);
        vm.stopPrank();
    }

    function testWithdraw(uint256 amount) public {
        amount = bound(amount, 1e8, type(uint128).max);

        vm.startPrank(ANVIL_ADDRESS);
        initWethReserve();
        vm.stopPrank();

        vm.startPrank(user2);
        mintAndApprove(netConfig.weth, user2, amount);
        pool.supply(netConfig.weth, amount, user2);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(netConfig.weth, user2, user2, amount);
        pool.withdraw(netConfig.weth, amount, user2);
        vm.stopPrank();

        assertEq(amount, IERC20(netConfig.weth).balanceOf(user2));
        assertEq(0, lTokenWeth.balanceOf(user2));
        assertEq(0, IERC20(netConfig.weth).balanceOf(address(pool)));
    }

    //////////////////
    // Borrow Tests //
    //////////////////
    function testBorrowRevertIfReserveInActiveOrScaledAmntIsZeroOrHFIsBadOrNotEnoughLiqOrNotHaveCollateral() public {
        vm.startPrank(ANVIL_ADDRESS);
        initWethReserve();
        pool.updateReserveActive(netConfig.weth, false);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveInactive.selector);
        pool.borrow(netConfig.weth, AMOUNT);
        vm.stopPrank();

        vm.prank(ANVIL_ADDRESS);
        pool.updateReserveActive(netConfig.weth, true);

        vm.startPrank(user);
        vm.expectRevert(ValidationLogic.ValidationLogic__NeedsMoreThanZero.selector);
        pool.borrow(netConfig.weth, 0);

        vm.expectRevert(ValidationLogic.ValidationLogic__NotUsingAsCollateral.selector);
        pool.borrow(netConfig.weth, AMOUNT);
        vm.stopPrank();

        vm.startPrank(user2);
        mintAndApprove(netConfig.weth, user2, AMOUNT);
        pool.supply(netConfig.weth, AMOUNT, user);
        vm.stopPrank();

        vm.startPrank(ANVIL_ADDRESS);
        initWbtcReserve();
        vm.stopPrank();

        vm.startPrank(user);
        mintAndApprove(netConfig.wbtc, user, AMOUNT);
        pool.supply(netConfig.wbtc, AMOUNT, user);
        pool.setUseAsCollateral(netConfig.wbtc, true);

        vm.expectRevert(ValidationLogic.ValidationLogic__PoolHasNotEnoughLiquidity.selector);
        pool.borrow(netConfig.weth, 2 * AMOUNT);
        vm.stopPrank();

        vm.startPrank(user2);
        mintAndApprove(netConfig.weth, user2, 100 * AMOUNT);
        pool.supply(netConfig.weth, 100 * AMOUNT, user);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(ValidationLogic.ValidationLogic__BreaksHealthFactor.selector);
        pool.borrow(netConfig.weth, 100 * AMOUNT);
        vm.stopPrank();
    }

    function testBorrow(uint256 amount) public {
        amount = bound(amount, 1e8, type(uint128).max);

        vm.startPrank(ANVIL_ADDRESS);
        initWethReserve();
        initWbtcReserve();
        vm.stopPrank();

        vm.startPrank(user);
        mintAndApprove(netConfig.weth, user, amount);
        pool.supply(netConfig.weth, amount, user);
        vm.stopPrank();

        vm.startPrank(user2);
        mintAndApprove(netConfig.wbtc, user2, amount);
        pool.supply(netConfig.wbtc, amount, user2);
        pool.setUseAsCollateral(netConfig.wbtc, true);
        vm.stopPrank();

        vm.startPrank(user2);
        emit Borrow(netConfig.weth, user2, amount);
        pool.borrow(netConfig.weth, amount);
        vm.stopPrank();

        assertEq(USER_AMOUNT, IERC20(netConfig.weth).balanceOf(user));
        assertEq(amount, IERC20(netConfig.weth).balanceOf(user2));
        assertEq(0, IERC20(netConfig.wbtc).balanceOf(user2));
        assertEq(amount, lTokenWbtc.balanceOf(user2));
        assertEq(0, IERC20(netConfig.weth).balanceOf(address(pool)));
        assertEq(amount, IERC20(netConfig.wbtc).balanceOf(address(pool)));
    }

    /////////////////
    // Repay Tests //
    /////////////////
    function testRepayRevertsIfReserveInActiveOrScaledAmountIsZero() public {
        vm.startPrank(ANVIL_ADDRESS);
        initWethReserve();
        pool.updateReserveActive(netConfig.weth, false);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveInactive.selector);
        pool.repay(netConfig.weth, AMOUNT, user);
        vm.stopPrank();

        vm.prank(ANVIL_ADDRESS);
        pool.updateReserveActive(netConfig.weth, true);

        vm.startPrank(user);
        vm.expectRevert(ValidationLogic.ValidationLogic__NeedsMoreThanZero.selector);
        pool.repay(netConfig.weth, 0, user);
    }

    function testRepay(uint256 amount) public {
        amount = bound(amount, 1e8, type(uint128).max);

        vm.startPrank(ANVIL_ADDRESS);
        initWethReserve();
        initWbtcReserve();
        vm.stopPrank();

        vm.startPrank(user);
        mintAndApprove(netConfig.weth, user, amount);
        pool.supply(netConfig.weth, amount, user);
        vm.stopPrank();

        vm.startPrank(user2);
        mintAndApprove(netConfig.wbtc, user2, amount);
        pool.supply(netConfig.wbtc, amount, user2);
        pool.setUseAsCollateral(netConfig.wbtc, true);
        pool.borrow(netConfig.weth, amount);

        IERC20(netConfig.weth).approve(address(pool), amount);

        emit Repay(netConfig.weth, user2, user2, amount, false);
        pool.repay(netConfig.weth, amount, user2);
        vm.stopPrank();

        assertEq(USER_AMOUNT, IERC20(netConfig.weth).balanceOf(user));
        assertEq(0, IERC20(netConfig.weth).balanceOf(user2));
        assertEq(0, IERC20(netConfig.wbtc).balanceOf(user2));
        assertEq(amount, lTokenWbtc.balanceOf(user2));
        assertEq(amount, IERC20(netConfig.weth).balanceOf(address(pool)));
        assertEq(amount, IERC20(netConfig.wbtc).balanceOf(address(pool)));
    }

    function testRepayWithLiquidityTokens(uint256 amount) public {
        amount = bound(amount, 1e8, type(uint128).max);

        vm.startPrank(ANVIL_ADDRESS);
        initWethReserve();
        initWbtcReserve();
        vm.stopPrank();

        vm.startPrank(user);
        mintAndApprove(netConfig.weth, user, amount);
        pool.supply(netConfig.weth, amount, user);
        vm.stopPrank();

        vm.startPrank(user2);
        mintAndApprove(netConfig.wbtc, user2, amount);
        pool.supply(netConfig.wbtc, amount, user2);
        pool.setUseAsCollateral(netConfig.wbtc, true);
        pool.borrow(netConfig.weth, amount);

        IERC20(netConfig.weth).approve(address(pool), amount);
        pool.supply(netConfig.weth, amount, user2);

        uint256 lTokenWethAmountBeforeRepay = lTokenWeth.scaledBalanceOf(user2);

        emit Repay(netConfig.weth, user2, user2, amount, true);
        pool.repayWithLiquidityTokens(netConfig.weth, amount);
        vm.stopPrank();

        uint256 lTokenWethAmountAfterRepay = lTokenWeth.scaledBalanceOf(user2);

        assertEq(USER_AMOUNT, IERC20(netConfig.weth).balanceOf(user));
        assertEq(0, IERC20(netConfig.weth).balanceOf(user2));
        assertEq(0, IERC20(netConfig.wbtc).balanceOf(user2));
        assertEq(amount, lTokenWbtc.balanceOf(user2));
        assertEq(amount, IERC20(netConfig.weth).balanceOf(address(pool)));
        assertEq(amount, IERC20(netConfig.wbtc).balanceOf(address(pool)));

        assertEq(amount, lTokenWethAmountBeforeRepay);
        assertEq(0, lTokenWethAmountAfterRepay);
    }

    function wrapAndUpdateFeed(uint256 wrapTime) internal {
        vm.warp(block.timestamp + wrapTime);
        MockV3Aggregator(netConfig.wethFeed.priceFeedAddress)
            .updateRoundData(2, 2000e8, block.timestamp, block.timestamp);
        MockV3Aggregator(netConfig.wbtcFeed.priceFeedAddress)
            .updateRoundData(2, 10000e8, block.timestamp, block.timestamp);
    }

    function testReserveDataUpdate(uint256 amount) public {
        amount = bound(amount, 1e8, type(uint128).max);

        vm.startPrank(ANVIL_ADDRESS);
        initWethReserve();
        initWbtcReserve();
        vm.stopPrank();

        supplyUpdateReserveTest(netConfig.weth, amount, user, doSupplyUser);

        wrapAndUpdateFeed(20 days);

        supplyUpdateReserveTest(netConfig.wbtc, amount, user2, doSupplyUser2);

        wrapAndUpdateFeed(10 days);

        vm.prank(user2);
        pool.setUseAsCollateral(netConfig.wbtc, true);
        supplyUpdateReserveTest(netConfig.weth, amount, user2, doBorrow);

        wrapAndUpdateFeed(15 days);

        supplyUpdateReserveTest(netConfig.weth, amount, user, doSupplyUser);

        wrapAndUpdateFeed(30 days);

        supplyUpdateReserveTest(netConfig.weth, amount, user2, doBorrow);

        wrapAndUpdateFeed(25 days);

        supplyUpdateReserveTest(netConfig.weth, amount, user2, doRepayUser2);

        wrapAndUpdateFeed(20 days);

        supplyUpdateReserveTest(netConfig.weth, amount, user2, doRepayUser2);
    }

    /////////////////
    // Price Tests //
    /////////////////
    function testGetUsdValue(uint256 amount) public {
        amount = bound(amount, 1e8, type(uint128).max);

        vm.prank(ANVIL_ADDRESS);
        initWethReserve();

        uint256 expectedUsdValue = amount * 2000;
        uint256 usdValue = pool.getUsdValue(netConfig.weth, amount);
        assertEq(expectedUsdValue, usdValue);
    }

    function testGetTokenAmountFromUsd(uint256 usdAmount) public {
        usdAmount = bound(usdAmount, 1e8, type(uint128).max);

        vm.prank(ANVIL_ADDRESS);
        initWethReserve();

        uint256 expectedWeth = usdAmount / 2000;
        uint256 amountWeth = pool.getTokenAmountFromUsd(netConfig.weth, usdAmount);
        assertEq(expectedWeth, amountWeth);
    }

    ////////////////////////////////////
    // Transfer Liquidity Token Tests //
    ////////////////////////////////////
    function testTransferLiquidityTokenRevertsIfReserveInActiveOrZeroAmntOrNotEnoughBalanceOrHFIsBad() public {
        vm.startPrank(ANVIL_ADDRESS);
        initWethReserve();
        initWbtcReserve();
        pool.updateReserveActive(netConfig.weth, false);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveInactive.selector);
        pool.transferLiquidityToken(netConfig.weth, user2, AMOUNT);
        vm.stopPrank();

        vm.prank(ANVIL_ADDRESS);
        pool.updateReserveActive(netConfig.weth, true);

        vm.startPrank(user);
        vm.expectRevert(ValidationLogic.ValidationLogic__NeedsMoreThanZero.selector);
        pool.transferLiquidityToken(netConfig.weth, user2, 0);

        vm.expectRevert(ValidationLogic.ValidationLogic__UserHasNotEnoughBalance.selector);
        pool.transferLiquidityToken(netConfig.weth, user2, AMOUNT);
        vm.stopPrank();

        vm.startPrank(user2);
        mintAndApprove(netConfig.weth, user2, AMOUNT);
        pool.supply(netConfig.weth, AMOUNT, user2);
        vm.stopPrank();

        vm.startPrank(user);
        mintAndApprove(netConfig.wbtc, user, AMOUNT);
        pool.supply(netConfig.wbtc, AMOUNT, user);
        pool.setUseAsCollateral(netConfig.wbtc, true);

        pool.borrow(netConfig.weth, 1);

        vm.expectRevert(ValidationLogic.ValidationLogic__BreaksHealthFactor.selector);
        pool.transferLiquidityToken(netConfig.wbtc, user2, AMOUNT);
        vm.stopPrank();
    }

    function testTransferLiquidityToken(uint256 amount) public {
        amount = bound(amount, 1e8, type(uint128).max);

        vm.startPrank(ANVIL_ADDRESS);
        initWethReserve();
        initWbtcReserve();
        vm.stopPrank();

        vm.startPrank(user2);
        mintAndApprove(netConfig.weth, user2, amount);
        pool.supply(netConfig.weth, amount, user2);
        vm.stopPrank();

        vm.startPrank(user2);
        pool.transferLiquidityToken(netConfig.weth, user, amount);
        vm.stopPrank();

        assertEq(amount, lTokenWeth.balanceOf(user));
        assertEq(0, lTokenWeth.balanceOf(user2));
    }

    ////////////////////////////
    // Liquidation Call Tests //
    ////////////////////////////
    function liquidationCallPrepare(uint256 amount) internal {
        vm.startPrank(ANVIL_ADDRESS);
        initWethReserve();
        initWbtcReserve();
        vm.stopPrank();

        vm.startPrank(user);
        mintAndApprove(netConfig.weth, user, amount);
        pool.supply(netConfig.weth, amount, user);
        vm.stopPrank();

        vm.startPrank(user2);
        mintAndApprove(netConfig.wbtc, user2, amount);
        pool.supply(netConfig.wbtc, amount, user2);
        pool.setUseAsCollateral(netConfig.wbtc, true);
        pool.borrow(netConfig.weth, amount);
        vm.stopPrank();

        vm.warp(block.timestamp + 20 days);
        MockV3Aggregator(netConfig.wethFeed.priceFeedAddress)
            .updateRoundData(2, 10000e8, block.timestamp, block.timestamp);
        MockV3Aggregator(netConfig.wbtcFeed.priceFeedAddress)
            .updateRoundData(2, 10000e8, block.timestamp, block.timestamp);
    }

    function testLiquidationCallRevertsIfReservesAreInActiveOrNotUsingAsCollateralOrNoDebtOrUserHFIsNotBad() public {
        vm.startPrank(ANVIL_ADDRESS);
        initWethReserve();
        initWbtcReserve();
        pool.updateReserveActive(netConfig.weth, false);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveInactive.selector);
        pool.liquidationCall(netConfig.weth, netConfig.wbtc, user2, AMOUNT, false);
        vm.stopPrank();

        vm.prank(ANVIL_ADDRESS);
        pool.updateReserveActive(netConfig.wbtc, false);

        vm.startPrank(user);
        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveInactive.selector);
        pool.liquidationCall(netConfig.weth, netConfig.wbtc, user2, AMOUNT, false);
        vm.stopPrank();

        vm.startPrank(ANVIL_ADDRESS);
        pool.updateReserveActive(netConfig.weth, true);
        pool.updateReserveActive(netConfig.wbtc, true);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(ValidationLogic.ValidationLogic__NotUsingAsCollateral.selector);
        pool.liquidationCall(netConfig.weth, netConfig.wbtc, user2, AMOUNT, false);
        vm.stopPrank();

        vm.startPrank(user2);
        mintAndApprove(netConfig.weth, user2, AMOUNT);
        pool.supply(netConfig.weth, AMOUNT, user2);
        pool.setUseAsCollateral(netConfig.weth, true);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(ValidationLogic.ValidationLogic__NoDebtOfSelectedType.selector);
        pool.liquidationCall(netConfig.weth, netConfig.wbtc, user2, AMOUNT, false);
        vm.stopPrank();

        vm.startPrank(user);
        mintAndApprove(netConfig.wbtc, user, AMOUNT);
        pool.supply(netConfig.wbtc, AMOUNT, user);
        vm.stopPrank();

        vm.startPrank(user2);
        pool.setUseAsCollateral(netConfig.weth, true);
        pool.borrow(netConfig.wbtc, AMOUNT / 63);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(ValidationLogic.ValidationLogic__HealthFactorNotBelowThreshold.selector);
        pool.liquidationCall(netConfig.weth, netConfig.wbtc, user2, AMOUNT, false);
        vm.stopPrank();
    }

    function testLiquidationCallTrue(uint256 amount) public {
        amount = bound(amount, 1e8, type(uint128).max);

        liquidationCallPrepare(amount);

        vm.startPrank(user);
        mintAndApprove(netConfig.weth, user, amount);
        vm.expectEmit(true, true, true, true);
        emit LiquidationCall(netConfig.wbtc, netConfig.weth, user2, user, amount / 2, amount, true);
        pool.liquidationCall(netConfig.wbtc, netConfig.weth, user2, amount, true);
        vm.stopPrank();
    }

    function testLiquidationCallFalse(uint256 amount) public {
        amount = bound(amount, 1e8, type(uint128).max);

        liquidationCallPrepare(amount);

        vm.startPrank(user);
        mintAndApprove(netConfig.weth, user, amount);
        vm.expectEmit(true, true, true, true);
        emit LiquidationCall(netConfig.wbtc, netConfig.weth, user2, user, amount / 2, amount, false);
        pool.liquidationCall(netConfig.wbtc, netConfig.weth, user2, amount, false);
        vm.stopPrank();
    }
}
