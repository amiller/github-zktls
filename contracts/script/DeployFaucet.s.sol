// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {GitHubFaucet} from "../examples/GitHubFaucet.sol";

contract DeployFaucet is Script {
    function run() external {
        address verifier = 0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725;

        vm.startBroadcast();
        GitHubFaucet faucet = new GitHubFaucet(verifier);
        vm.stopBroadcast();

        console.log("GitHubFaucet deployed at:", address(faucet));
    }
}
