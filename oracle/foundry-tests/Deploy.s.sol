// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PredictionMarket.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        PredictionMarket market = new PredictionMarket();
        
        console.log("PredictionMarket deployed to:", address(market));
        
        vm.stopBroadcast();
    }
}
