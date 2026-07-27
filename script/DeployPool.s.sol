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
    function run()
        public
        returns (Pool pool, HelperConfig config, Treasury treasury, LiquidityToken lToken, DebtToken dToken)
    {
        config = new HelperConfig();
        HelperConfig.NetworkConfig memory netConfig = config.getActiveNetworkConfig();

        vm.startBroadcast(netConfig.deployerKey);
        pool = new Pool();
        treasury = new Treasury();
        lToken = new LiquidityToken(
            "LEtherium", "LETH", address(treasury), address(pool), netConfig.asset, netConfig.feed.tokenDecimals
        );
        dToken = new DebtToken("DEtherium", "DETH", address(pool), netConfig.asset, netConfig.feed.tokenDecimals);
        vm.stopBroadcast();
    }
}
