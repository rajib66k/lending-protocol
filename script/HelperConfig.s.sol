// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Script} from "forge-std/Script.sol";
import {DataTypes} from "../src/types/DataTypes.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {LiquidityToken} from "../src/protocol/LiquidityToken.sol";
import {DebtToken} from "../src/protocol/DebtToken.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address asset;
        uint256 liquidationThreshold;
        uint256 liquidationBonus;
        uint256 reserveFactor;
        DataTypes.InterestRateParams params;
        DataTypes.FeedData feed;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    uint256 public constant LIQUIDARION_THRESHOLD = 8000;
    uint256 public constant LIQUIDARION_BONUS = 10000;
    uint256 public constant RESERVE_FACTOR = 10000;
    uint8 public constant TOKEN_DECIMALS = 8;
    uint8 public constant FEED_DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
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
        DataTypes.FeedData memory feed = DataTypes.FeedData({
            priceFeedAddress: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            feedDecimals: FEED_DECIMALS,
            tokenDecimals: TOKEN_DECIMALS
        });

        DataTypes.InterestRateParams memory params = DataTypes.InterestRateParams({
            optimalUsageRatio: 8e26, baseBorrowRate: 2e25, variableRateSlope1: 5e25, variableRateSlope2: 7e26
        });

        return NetworkConfig({
            asset: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            liquidationThreshold: LIQUIDARION_THRESHOLD,
            liquidationBonus: LIQUIDARION_BONUS,
            reserveFactor: RESERVE_FACTOR,
            params: params,
            feed: feed,
            deployerKey: vm.envUint("SEPOLIA_PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.asset != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        ERC20Mock weth = new ERC20Mock();
        MockV3Aggregator wethUsdPriceFeed = new MockV3Aggregator(TOKEN_DECIMALS, ETH_USD_PRICE);
        vm.stopBroadcast();

        DataTypes.FeedData memory feed = DataTypes.FeedData({
            priceFeedAddress: address(wethUsdPriceFeed), feedDecimals: FEED_DECIMALS, tokenDecimals: TOKEN_DECIMALS
        });

        DataTypes.InterestRateParams memory params = DataTypes.InterestRateParams({
            optimalUsageRatio: 8e26, baseBorrowRate: 2e25, variableRateSlope1: 5e25, variableRateSlope2: 7e26
        });

        vm.stopBroadcast();
        return NetworkConfig({
            asset: address(weth),
            liquidationThreshold: LIQUIDARION_THRESHOLD,
            liquidationBonus: LIQUIDARION_BONUS,
            reserveFactor: RESERVE_FACTOR,
            params: params,
            feed: feed,
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }

    function getActiveNetworkConfig() external view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}
