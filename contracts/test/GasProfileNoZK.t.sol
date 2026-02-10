// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {HonkVerifierNoZK} from "../src/HonkVerifierNoZK.sol";
import "../src/HonkVerifierNoZK.sol";

contract GasProfiledVerifierNoZK is BaseHonkVerifier(NOZK_N, NOZK_LOG_N, NOZK_VK_HASH, NOZK_NUMBER_OF_PUBLIC_INPUTS) {
    function loadVerificationKey() internal pure override returns (HonkNoZK.VerificationKey memory) {
        return HonkVerificationKeyNoZK.loadVerificationKey();
    }

    struct GasBreakdown {
        uint256 loadProof;
        uint256 transcript;
        uint256 delta;
        uint256 sumcheck;
        uint256 shplemini;
        uint256 total;
    }

    function profileVerify(bytes calldata proof, bytes32[] calldata publicInputs)
        external view returns (GasBreakdown memory g)
    {
        uint256 g0 = gasleft();

        HonkNoZK.VerificationKey memory vk = loadVerificationKey();
        HonkNoZK.Proof memory p = TranscriptLibNoZK.loadProof(proof, $LOG_N);
        uint256 g1 = gasleft();
        g.loadProof = g0 - g1;

        Transcript memory t = TranscriptLibNoZK.generateTranscript(
            p, publicInputs, $VK_HASH, $NUM_PUBLIC_INPUTS, $LOG_N
        );
        uint256 g2 = gasleft();
        g.transcript = g1 - g2;

        t.relationParameters.publicInputsDelta = computePublicInputDelta(
            publicInputs, p.pairingPointObject,
            t.relationParameters.beta, t.relationParameters.gamma, 1
        );
        uint256 g3 = gasleft();
        g.delta = g2 - g3;

        require(verifySumcheck(p, t), "sumcheck");
        uint256 g4 = gasleft();
        g.sumcheck = g3 - g4;

        require(verifyShplemini(p, vk, t), "shplemini");
        uint256 g5 = gasleft();
        g.shplemini = g4 - g5;

        g.total = g0 - g5;
    }
}

contract GasProfileNoZKTest is Test {
    GasProfiledVerifierNoZK profiler;
    bytes proof;
    bytes32[] publicInputs;

    function setUp() public {
        profiler = new GasProfiledVerifierNoZK();
        proof = vm.readFileBinary("test/proof_nozk.bin");
        bytes memory inputsRaw = vm.readFileBinary("test/inputs_nozk.bin");
        uint256 n = inputsRaw.length / 32;
        publicInputs = new bytes32[](n);
        for (uint i = 0; i < n; i++) {
            bytes32 val;
            assembly { val := mload(add(inputsRaw, add(32, mul(i, 32)))) }
            publicInputs[i] = val;
        }
    }

    function test_GasProfileNoZK() public view {
        GasProfiledVerifierNoZK.GasBreakdown memory g = profiler.profileVerify(proof, publicInputs);

        console.log("=== HonkVerifier (No-ZK) Gas Profile ===");
        console.log("Circuit size: 2^20 = 1,048,576 gates");
        console.log("Public inputs:", publicInputs.length);
        console.log("Proof bytes:", proof.length);
        console.log("");
        console.log("--- Component Breakdown ---");
        console.log("1. Load VK + parse proof:", g.loadProof);
        console.log("2. Fiat-Shamir transcript:", g.transcript);
        console.log("3. Public input delta:    ", g.delta);
        console.log("4. Sumcheck (20 rounds):  ", g.sumcheck);
        console.log("5. Shplemini (MSM+pairing):", g.shplemini);
        console.log("---");
        console.log("TOTAL (internal):         ", g.total);
        console.log("");

        console.log("--- Percentage Breakdown ---");
        console.log("1. Load+parse:  ", g.loadProof * 1000 / g.total, "/ 1000");
        console.log("2. Transcript:  ", g.transcript * 1000 / g.total, "/ 1000");
        console.log("3. Delta:       ", g.delta * 1000 / g.total, "/ 1000");
        console.log("4. Sumcheck:    ", g.sumcheck * 1000 / g.total, "/ 1000");
        console.log("5. Shplemini:   ", g.shplemini * 1000 / g.total, "/ 1000");
    }
}
