// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {GitHubFaucet} from "../examples/GitHubFaucet.sol";

contract ClaimFaucet is Script {
    function run() external {
        GitHubFaucet faucet = GitHubFaucet(payable(vm.envAddress("FAUCET_ADDRESS")));

        // Read proof, inputs, and certificate
        bytes memory proof = vm.readFileBinary("proof/proof.bin");
        bytes memory inputsRaw = vm.readFileBinary("proof/inputs.bin");
        bytes memory certificate = bytes(vm.readFile("proof/certificate.json"));
        string memory username = vm.envString("GITHUB_USERNAME");
        address recipient = vm.envAddress("RECIPIENT_ADDRESS");

        // Convert raw bytes to bytes32 array
        uint256 numInputs = inputsRaw.length / 32;
        bytes32[] memory publicInputs = new bytes32[](numInputs);
        for (uint256 i = 0; i < numInputs; i++) {
            bytes32 val;
            assembly {
                val := mload(add(add(inputsRaw, 32), mul(i, 32)))
            }
            publicInputs[i] = val;
        }

        console.log("Proof length:", proof.length);
        console.log("Public inputs count:", publicInputs.length);
        console.log("Certificate length:", certificate.length);
        console.log("Username:", username);
        console.log("Faucet balance:", address(faucet).balance);
        console.log("Claim amount:", faucet.claimAmount());
        console.log("Recipient:", recipient);

        vm.startBroadcast();
        faucet.claim(proof, publicInputs, certificate, username, payable(recipient));
        vm.stopBroadcast();

        console.log("Claim successful!");
    }
}
