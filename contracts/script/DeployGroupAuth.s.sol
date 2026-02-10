// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {GroupAuth} from "../examples/GroupAuth.sol";

contract DeployGroupAuth is Script {
    function run() external {
        address sigstoreVerifier = vm.envAddress("SIGSTORE_VERIFIER");
        address kmsRoot = vm.envAddress("KMS_ROOT");

        vm.startBroadcast();
        GroupAuth ga = new GroupAuth(sigstoreVerifier, kmsRoot);
        vm.stopBroadcast();

        console.log("GroupAuth deployed at:", address(ga));
        console.log("SigstoreVerifier:", sigstoreVerifier);
        console.log("KMS root:", kmsRoot);
    }
}
