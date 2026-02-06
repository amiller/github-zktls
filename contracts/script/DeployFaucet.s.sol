// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {GitHubFaucet} from "../examples/GitHubFaucet.sol";

contract DeployFaucet is Script {
    function run() external {
        address verifier = 0xbD08fd15E893094Ad3191fdA0276Ac880d0FA3e1;
        bytes20 commitSha = bytes20(vm.envOr("COMMIT_SHA", bytes20(0)));

        vm.startBroadcast();
        GitHubFaucet faucet = new GitHubFaucet(verifier, commitSha);
        vm.stopBroadcast();

        console.log("GitHubFaucet deployed at:", address(faucet));
        console.log("Required commit SHA:", vm.toString(commitSha));
    }
}
