// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Script, console} from "forge-std/Script.sol";
import {ISigstoreVerifier} from "../src/ISigstoreVerifier.sol";

contract TestOnChain is Script {
    function run() external view {
        ISigstoreVerifier verifier = ISigstoreVerifier(0xbD08fd15E893094Ad3191fdA0276Ac880d0FA3e1);

        // Load proof and inputs
        bytes memory proof = vm.readFileBinary("test/proof.bin");
        bytes memory inputsRaw = vm.readFileBinary("test/inputs.bin");

        // Convert to bytes32 array
        uint256 numInputs = inputsRaw.length / 32;
        bytes32[] memory publicInputs = new bytes32[](numInputs);
        for (uint i = 0; i < numInputs; i++) {
            bytes32 val;
            assembly {
                val := mload(add(inputsRaw, add(32, mul(i, 32))))
            }
            publicInputs[i] = val;
        }

        console.log("Proof length:", proof.length);
        console.log("Public inputs count:", publicInputs.length);
        console.log("Calling verify on deployed contract...");

        bool valid = verifier.verify(proof, publicInputs);
        console.log("Result:", valid);

        if (valid) {
            ISigstoreVerifier.Attestation memory att = verifier.decodePublicInputs(publicInputs);
            console.log("Artifact hash:");
            console.logBytes32(att.artifactHash);
            console.log("Repo hash:");
            console.logBytes32(att.repoHash);
            console.log("Commit SHA:");
            console.logBytes20(att.commitSha);
        }
    }
}
