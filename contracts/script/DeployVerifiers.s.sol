// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {HonkVerifier} from "../src/HonkVerifier.sol";
import {SigstoreVerifier} from "../src/SigstoreVerifier.sol";

contract DeployVerifiers is Script {
    function run() external {
        vm.startBroadcast();
        HonkVerifier honk = new HonkVerifier();
        console.log("HonkVerifier deployed at:", address(honk));
        SigstoreVerifier sigstore = new SigstoreVerifier(address(honk));
        console.log("SigstoreVerifier deployed at:", address(sigstore));
        vm.stopBroadcast();
    }
}
