// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {SigstoreVerifier} from "../src/SigstoreVerifier.sol";
import {HonkVerifier} from "../src/HonkVerifier.sol";

contract IntegrationTest is Test {
    SigstoreVerifier verifier;
    HonkVerifier honk;

    function setUp() public {
        honk = new HonkVerifier();
        verifier = new SigstoreVerifier(address(honk));
    }

    function test_VerifyRealProof() public view {
        // Load proof from file
        bytes memory proof = vm.readFileBinary("test/proof.bin");
        console.log("Proof length:", proof.length);

        // Load public inputs from file
        bytes memory inputsRaw = vm.readFileBinary("test/inputs.bin");
        console.log("Inputs raw length:", inputsRaw.length);

        // Convert to bytes32 array (5 packed elements)
        uint256 numInputs = inputsRaw.length / 32;
        console.log("Number of inputs:", numInputs);

        bytes32[] memory publicInputs = new bytes32[](numInputs);
        for (uint i = 0; i < numInputs; i++) {
            bytes32 val;
            assembly {
                val := mload(add(inputsRaw, add(32, mul(i, 32))))
            }
            publicInputs[i] = val;
        }

        // Verify
        bool valid = verifier.verify(proof, publicInputs);
        assertTrue(valid, "Proof should be valid");
    }
}
