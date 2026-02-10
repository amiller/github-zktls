// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;
import {Script} from "forge-std/Script.sol";
import {GroupAuth} from "../examples/GroupAuth.sol";

contract DeployGroupAuth is Script {
    // Reuse existing deployments on Base mainnet
    address constant SIGSTORE_VERIFIER = 0x904Ae91989C4C96F2f51f1F8c9eF65C3730b3d8d;
    address constant KMS_ROOT = 0xd5BDeB037F237Baac161EA37999B6aA37f7f4C77;

    function run() external {
        vm.startBroadcast();
        new GroupAuth(SIGSTORE_VERIFIER, KMS_ROOT);
        vm.stopBroadcast();
    }
}
