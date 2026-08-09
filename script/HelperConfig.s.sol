// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Script} from "forge-std/Script.sol";
import {DataTypes} from "../src/types/DataTypes.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {LiquidityToken} from "../src/protocol/LiquidityToken.sol";
import {DebtToken} from "../src/protocol/DebtToken.sol";

contract HelperConfig is Script {
    struct ReserveConfig {
        uint256 liquidationThreshold;
        uint256 liquidationBonus;
        uint256 reserveFactor;
    }

    struct NetworkConfig {
        address weth;
        address wbtc;
        ReserveConfig wethReserveConfig;
        ReserveConfig wbtcReserveConfig;
        DataTypes.InterestRateParams wethParams;
        DataTypes.InterestRateParams wbtcParams;
        DataTypes.FeedData wethFeed;
        DataTypes.FeedData wbtcFeed;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    uint8 public constant TOKEN_DECIMALS = 8;
    uint8 public constant FEED_DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 100000e8;
    uint256 public constant SEPOLIA_CHAINID = 11155111;
    uint256 public constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == SEPOLIA_CHAINID) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        DataTypes.FeedData memory wethFeed = DataTypes.FeedData({
            priceFeedAddress: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            feedDecimals: FEED_DECIMALS,
            tokenDecimals: TOKEN_DECIMALS
        });

        DataTypes.FeedData memory wbtcFeed = DataTypes.FeedData({
            priceFeedAddress: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            feedDecimals: FEED_DECIMALS,
            tokenDecimals: TOKEN_DECIMALS
        });

        DataTypes.InterestRateParams memory wethParams = DataTypes.InterestRateParams({
            optimalUsageRatio: 8e26, baseBorrowRate: 2e25, variableRateSlope1: 5e25, variableRateSlope2: 7e26
        });

        DataTypes.InterestRateParams memory wbtcParams = DataTypes.InterestRateParams({
            optimalUsageRatio: 8e26, baseBorrowRate: 2e25, variableRateSlope1: 5e25, variableRateSlope2: 7e26
        });

        ReserveConfig memory wethReserveConfig =
            ReserveConfig({liquidationThreshold: 8000, liquidationBonus: 10000, reserveFactor: 1000});

        ReserveConfig memory wbtcReserveConfig =
            ReserveConfig({liquidationThreshold: 8000, liquidationBonus: 10000, reserveFactor: 1000});

        return NetworkConfig({
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x29f2D40B0605204364af54EC677bD022dA425d03,
            wethReserveConfig: wethReserveConfig,
            wbtcReserveConfig: wbtcReserveConfig,
            wethParams: wethParams,
            wbtcParams: wbtcParams,
            wethFeed: wethFeed,
            wbtcFeed: wbtcFeed,
            deployerKey: vm.envUint("SEPOLIA_PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.weth != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        ERC20Mock weth = new ERC20Mock();
        MockV3Aggregator wethUsdPriceFeed = new MockV3Aggregator(TOKEN_DECIMALS, ETH_USD_PRICE);
        ERC20Mock wbtc = new ERC20Mock();
        MockV3Aggregator wbtcUsdPriceFeed = new MockV3Aggregator(TOKEN_DECIMALS, BTC_USD_PRICE);
        vm.stopBroadcast();

        ReserveConfig memory wethReserveConfig =
            ReserveConfig({liquidationThreshold: 8000, liquidationBonus: 10000, reserveFactor: 1000});

        ReserveConfig memory wbtcReserveConfig =
            ReserveConfig({liquidationThreshold: 8000, liquidationBonus: 10000, reserveFactor: 1000});

        DataTypes.FeedData memory wethFeed = DataTypes.FeedData({
            priceFeedAddress: address(wethUsdPriceFeed), feedDecimals: FEED_DECIMALS, tokenDecimals: TOKEN_DECIMALS
        });

        DataTypes.FeedData memory wbtcFeed = DataTypes.FeedData({
            priceFeedAddress: address(wbtcUsdPriceFeed), feedDecimals: FEED_DECIMALS, tokenDecimals: TOKEN_DECIMALS
        });

        DataTypes.InterestRateParams memory wethParams = DataTypes.InterestRateParams({
            optimalUsageRatio: 8e26, baseBorrowRate: 2e25, variableRateSlope1: 5e25, variableRateSlope2: 7e26
        });

        DataTypes.InterestRateParams memory wbtcParams = DataTypes.InterestRateParams({
            optimalUsageRatio: 8e26, baseBorrowRate: 2e25, variableRateSlope1: 5e25, variableRateSlope2: 7e26
        });

        return NetworkConfig({
            weth: address(weth),
            wbtc: address(wbtc),
            wethReserveConfig: wethReserveConfig,
            wbtcReserveConfig: wbtcReserveConfig,
            wethParams: wethParams,
            wbtcParams: wbtcParams,
            wethFeed: wethFeed,
            wbtcFeed: wbtcFeed,
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }

    function getActiveNetworkConfig() external view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}
