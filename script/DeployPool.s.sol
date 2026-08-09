// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Script} from "forge-std/Script.sol";
import {DataTypes} from "src/types/DataTypes.sol";
import {Pool} from "../src/protocol/Pool.sol";
import {Treasury} from "../src/treasury/Treasury.sol";
import {LiquidityToken} from "../src/protocol/LiquidityToken.sol";
import {DebtToken} from "../src/protocol/DebtToken.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployPool is Script {
    struct AssetData {
        LiquidityToken lToken;
        DebtToken dToken;
    }

    function run() public returns (Pool pool, HelperConfig config, Treasury treasury, AssetData[] memory assetData) {
        config = new HelperConfig();
        HelperConfig.NetworkConfig memory netConfig = config.getActiveNetworkConfig();

        vm.startBroadcast(netConfig.deployerKey);
        pool = new Pool();
        treasury = new Treasury();

        LiquidityToken ltokenWeth = new LiquidityToken(
            "LEtherium", "LETH", address(treasury), address(pool), netConfig.weth, netConfig.wethFeed.tokenDecimals
        );
        ltokenWeth.transferOwnership(address(pool));
        DebtToken dtokenWeth =
            new DebtToken("DEtherium", "DETH", address(pool), netConfig.weth, netConfig.wethFeed.tokenDecimals);
        dtokenWeth.transferOwnership(address(pool));

        LiquidityToken ltokenWbtc = new LiquidityToken(
            "LBitcoin", "LBTC", address(treasury), address(pool), netConfig.wbtc, netConfig.wbtcFeed.tokenDecimals
        );
        ltokenWbtc.transferOwnership(address(pool));
        DebtToken dtokenWbtc =
            new DebtToken("DEtherium", "DETH", address(pool), netConfig.wbtc, netConfig.wbtcFeed.tokenDecimals);
        dtokenWbtc.transferOwnership(address(pool));
        vm.stopBroadcast();

        AssetData memory wethData = AssetData({lToken: ltokenWeth, dToken: dtokenWeth});
        AssetData memory wbtcData = AssetData({lToken: ltokenWbtc, dToken: dtokenWbtc});

        assetData = new AssetData[](2);
        assetData[0] = wethData;
        assetData[1] = wbtcData;
    }
}
