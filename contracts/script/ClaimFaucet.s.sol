// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {GitHubFaucet} from "../examples/GitHubFaucet.sol";

contract ClaimFaucet is Script {
    function run() external {
        GitHubFaucet faucet = GitHubFaucet(payable(0xcfb53ce24F4B5CfA3c4a70F559F60e84C96bf863));

        // Read proof and inputs
        bytes memory proof = vm.readFileBinary("test/proof.bin");
        bytes memory inputsRaw = vm.readFileBinary("test/inputs.bin");

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
        console.log("Faucet balance:", address(faucet).balance);
        console.log("Claim amount:", faucet.claimAmount());

        address recipient = 0x5A370b73385085091de23E0fD21B54F2724EAD8D;
        console.log("Recipient before:", recipient.balance);

        vm.startBroadcast();
        faucet.claim(proof, publicInputs, payable(recipient));
        vm.stopBroadcast();

        console.log("Recipient after:", recipient.balance);
        console.log("Claim successful!");
    }
}
