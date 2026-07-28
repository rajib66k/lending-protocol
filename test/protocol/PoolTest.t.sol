// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {DeployPool} from "../../script/DeployPool.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Pool} from "../../src/protocol/Pool.sol";
import {Treasury} from "../../src/treasury/Treasury.sol";
import {LiquidityToken} from "../../src/protocol/LiquidityToken.sol";
import {DebtToken} from "../../src/protocol/DebtToken.sol";
import {DataTypes} from "../../src/types/DataTypes.sol";
import {ValidationLogic} from "../../src/libraries/ValidationLogic.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PoolTest is Test {
    DeployPool public deploy;
    HelperConfig.NetworkConfig public netConfig;
    HelperConfig public config;
    Pool public pool;
    Treasury public treasury;
    LiquidityToken public lToken;
    DebtToken public dToken;

    address public constant ANVIL_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 public constant MAX_RESERVES = 128;

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

    function setUp() public {
        deploy = new DeployPool();

        (pool, config, treasury, lToken, dToken) = deploy.run();
        netConfig = config.getActiveNetworkConfig();
    }

    //////////////////////////////
    // InitializeReserve Helper //
    //////////////////////////////
    function initReserve() public {
        pool.initializeReserve(
            netConfig.asset,
            address(lToken),
            address(dToken),
            netConfig.liquidationThreshold,
            netConfig.liquidationBonus,
            netConfig.reserveFactor,
            netConfig.params,
            netConfig.feed
        );
    }

    function initReserveWithInput(address asset, address liqToken, address debtToken) public {
        pool.initializeReserve(
            asset,
            liqToken,
            debtToken,
            netConfig.liquidationThreshold,
            netConfig.liquidationBonus,
            netConfig.reserveFactor,
            netConfig.params,
            netConfig.feed
        );
    }

    /////////////////////////////
    // InitializeReserve Tests //
    /////////////////////////////
    function testInitializeReserveRevertsIfNotOwnerOrZeroAddressOrReserveCountTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        initReserve();

        vm.startPrank(ANVIL_ADDRESS);
        vm.expectRevert(ValidationLogic.ValidationLogic__InvalidAddress.selector);
        initReserveWithInput(address(0), address(lToken), address(dToken));

        vm.expectRevert(ValidationLogic.ValidationLogic__InvalidAddress.selector);
        initReserveWithInput(netConfig.asset, address(0), address(dToken));

        vm.expectRevert(ValidationLogic.ValidationLogic__InvalidAddress.selector);
        initReserveWithInput(netConfig.asset, address(lToken), address(0));

        for (uint256 i = 0; i < MAX_RESERVES; i++) {
            initReserveWithInput(makeAddr(vm.toString(i)), makeAddr(vm.toString(i)), makeAddr(vm.toString(i)));
        }

        vm.expectRevert(ValidationLogic.ValidationLogic__TooManyReserves.selector);
        initReserve();
        vm.stopPrank();

        vm.assertEq(pool.getReserveCount(), 128);
    }

    function testInitializeReserve() public {
        vm.prank(ANVIL_ADDRESS);

        vm.expectEmit(true, true, true, true);
        emit ReserveInitialized(
            netConfig.asset,
            address(lToken),
            address(dToken),
            netConfig.params,
            netConfig.feed,
            netConfig.liquidationThreshold,
            netConfig.liquidationBonus,
            netConfig.reserveFactor,
            0
        );
        initReserve();

        DataTypes.ReserveData memory reserve = pool.getReserveData(netConfig.asset);
        DataTypes.InterestRateParams memory params = pool.getInterestRateParams(netConfig.asset);
        DataTypes.FeedData memory feed = pool.getFeedData(netConfig.asset);

        assertEq(1e27, reserve.liquidityIndex);
        assertEq(1e27, reserve.borrowIndex);
        assertEq(0, reserve.currentLiquidityRate);
        assertEq(0, reserve.currentBorrowRate);
        assertEq(netConfig.liquidationThreshold, reserve.liquidationThreshold);
        assertEq(netConfig.liquidationBonus, reserve.liquidationBonus);
        assertEq(netConfig.reserveFactor, reserve.reserveFactor);
        assertEq(0, reserve.id);
        assertEq(0, reserve.lastUpdate);
        assertEq(true, reserve.isActive);
        assertEq(address(lToken), reserve.liquidityTokenAddress);
        assertEq(address(dToken), reserve.debtTokenAddress);
        assertEq(netConfig.params.optimalUsageRatio, params.optimalUsageRatio);
        assertEq(netConfig.params.baseBorrowRate, params.baseBorrowRate);
        assertEq(netConfig.params.variableRateSlope1, params.variableRateSlope1);
        assertEq(netConfig.params.variableRateSlope2, params.variableRateSlope2);
        assertEq(netConfig.feed.priceFeedAddress, feed.priceFeedAddress);
        assertEq(netConfig.feed.feedDecimals, feed.feedDecimals);
        assertEq(netConfig.feed.tokenDecimals, feed.tokenDecimals);
    }

    ///////////////////////////////
    // UpdateReserveActive Tests //
    ///////////////////////////////
    function testUpdateReserveActiveRevertsIfNotOwnerOrReserveActiveSameAsInputOrReserveIsNotAvailable() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        pool.updateReserveActive(netConfig.asset, true);

        vm.startPrank(ANVIL_ADDRESS);
        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveDoesNotExist.selector);
        pool.updateReserveActive(netConfig.asset, true);

        initReserve();
        vm.expectRevert(
            abi.encodeWithSelector(ValidationLogic.ValidationLogic__ReserveIsActiveIsAlready.selector, true)
        );
        pool.updateReserveActive(netConfig.asset, true);

        pool.updateReserveActive(netConfig.asset, false);

        vm.expectRevert(
            abi.encodeWithSelector(ValidationLogic.ValidationLogic__ReserveIsActiveIsAlready.selector, false)
        );
        pool.updateReserveActive(netConfig.asset, false);
        vm.stopPrank();
    }

    function testUpdateReserveActive() public {
        vm.startPrank(ANVIL_ADDRESS);
        initReserve();

        pool.updateReserveActive(netConfig.asset, false);
        pool.updateReserveActive(netConfig.asset, true);
        vm.stopPrank();
    }

    ////////////////////////////////////
    // UpdateInterestRateParams Tests //
    ////////////////////////////////////
    function testUpdateInterestRateParamsRevertIfNotOwnerOrReserveIsNotAvailable() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        pool.updateInterestRateParams(netConfig.asset, netConfig.params);

        vm.startPrank(ANVIL_ADDRESS);
        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveDoesNotExist.selector);
        pool.updateInterestRateParams(netConfig.asset, netConfig.params);
        vm.stopPrank();
    }

    function testUpdateInterestRateParams() public {
        vm.startPrank(ANVIL_ADDRESS);
        initReserve();
        pool.updateInterestRateParams(netConfig.asset, netConfig.params);
        vm.stopPrank();
    }

    //////////////////////////
    // UpdateFeedData Tests //
    //////////////////////////
    function testUpdateFeedDataRevertIfNotOwnerOrReserveIsNotAvailable() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        pool.updateFeedData(netConfig.asset, netConfig.feed);

        vm.startPrank(ANVIL_ADDRESS);
        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveDoesNotExist.selector);
        pool.updateFeedData(netConfig.asset, netConfig.feed);
        vm.stopPrank();
    }

    function testUpdateFeedData() public {
        vm.startPrank(ANVIL_ADDRESS);
        initReserve();
        pool.updateInterestRateParams(netConfig.asset, netConfig.params);
        vm.stopPrank();
    }

    function testUpdateReserveDataRevertIfNotOwnerOrReserveIsNotAvailable() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        pool.updateReserveData(
            netConfig.asset, netConfig.liquidationThreshold, netConfig.liquidationBonus, netConfig.reserveFactor
        );

        vm.startPrank(ANVIL_ADDRESS);
        vm.expectRevert(ValidationLogic.ValidationLogic__ReserveDoesNotExist.selector);
        pool.updateReserveData(
            netConfig.asset, netConfig.liquidationThreshold, netConfig.liquidationBonus, netConfig.reserveFactor
        );
        vm.stopPrank();
    }

    function testUpdateReserveData() public {
        vm.startPrank(ANVIL_ADDRESS);
        initReserve();
        pool.updateReserveData(
            netConfig.asset, netConfig.liquidationThreshold, netConfig.liquidationBonus, netConfig.reserveFactor
        );
        vm.stopPrank();
    }
}
