// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {HonkVerifier} from "../src/HonkVerifier.sol";
import "../src/HonkVerifier.sol"; // import all free-standing constants/types

// Harness: exposes verify() internals with gas checkpoints
contract GasProfiledVerifier is BaseZKHonkVerifier(N, LOG_N, VK_HASH, NUMBER_OF_PUBLIC_INPUTS) {
    function loadVerificationKey() internal pure override returns (Honk.VerificationKey memory) {
        return HonkVerificationKey.loadVerificationKey();
    }

    struct GasBreakdown {
        uint256 loadProof;      // VK load + proof deserialization
        uint256 transcript;     // Fiat-Shamir challenge generation
        uint256 delta;          // Public input delta computation
        uint256 sumcheck;       // Sumcheck verification (LOG_N rounds)
        uint256 shplemini;      // Shplemini (MSM + fold + pairing)
        uint256 total;
    }

    function profileVerify(bytes calldata proof, bytes32[] calldata publicInputs)
        external view returns (GasBreakdown memory g)
    {
        uint256 g0 = gasleft();

        // --- Stage 1: Load VK + deserialize proof ---
        Honk.VerificationKey memory vk = loadVerificationKey();
        Honk.ZKProof memory p = ZKTranscriptLib.loadProof(proof, $LOG_N);
        uint256 g1 = gasleft();
        g.loadProof = g0 - g1;

        // --- Stage 2: Fiat-Shamir transcript ---
        ZKTranscript memory t = ZKTranscriptLib.generateTranscript(
            p, publicInputs, $VK_HASH, $NUM_PUBLIC_INPUTS, $LOG_N
        );
        uint256 g2 = gasleft();
        g.transcript = g1 - g2;

        // --- Stage 3: Public input delta ---
        t.relationParameters.publicInputsDelta = computePublicInputDelta(
            publicInputs, p.pairingPointObject,
            t.relationParameters.beta, t.relationParameters.gamma, 1
        );
        uint256 g3 = gasleft();
        g.delta = g2 - g3;

        // --- Stage 4: Sumcheck ---
        require(verifySumcheck(p, t), "sumcheck");
        uint256 g4 = gasleft();
        g.sumcheck = g3 - g4;

        // --- Stage 5: Shplemini (MSM + fold + pairing) ---
        require(verifyShplemini(p, vk, t), "shplemini");
        uint256 g5 = gasleft();
        g.shplemini = g4 - g5;

        g.total = g0 - g5;
    }
}

contract GasProfileTest is Test {
    GasProfiledVerifier profiler;
    bytes proof;
    bytes32[] publicInputs;

    function setUp() public {
        profiler = new GasProfiledVerifier();

        // Load real proof + inputs
        proof = vm.readFileBinary("test/proof.bin");
        bytes memory inputsRaw = vm.readFileBinary("test/inputs.bin");
        uint256 n = inputsRaw.length / 32;
        publicInputs = new bytes32[](n);
        for (uint i = 0; i < n; i++) {
            bytes32 val;
            assembly { val := mload(add(inputsRaw, add(32, mul(i, 32)))) }
            publicInputs[i] = val;
        }
    }

    function test_GasProfile() public view {
        GasProfiledVerifier.GasBreakdown memory g = profiler.profileVerify(proof, publicInputs);

        console.log("=== HonkVerifier Gas Profile ===");
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

        // Percentages (integer math, x10 for one decimal)
        console.log("--- Percentage Breakdown ---");
        console.log("1. Load+parse:  ", g.loadProof * 1000 / g.total, "/ 1000");
        console.log("2. Transcript:  ", g.transcript * 1000 / g.total, "/ 1000");
        console.log("3. Delta:       ", g.delta * 1000 / g.total, "/ 1000");
        console.log("4. Sumcheck:    ", g.sumcheck * 1000 / g.total, "/ 1000");
        console.log("5. Shplemini:   ", g.shplemini * 1000 / g.total, "/ 1000");
    }

    // --- Isolated precompile benchmarks ---

    function test_PrecompileCost_MODEXP() public view {
        // FrLib.invert: modexp(v, MODULUS-2, MODULUS) — field inversion
        uint256 MODULUS = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001;
        uint256 v = 42;
        uint256 g0 = gasleft();
        assembly {
            let free := mload(0x40)
            mstore(free, 0x20)
            mstore(add(free, 0x20), 0x20)
            mstore(add(free, 0x40), 0x20)
            mstore(add(free, 0x60), v)
            mstore(add(free, 0x80), sub(MODULUS, 2))
            mstore(add(free, 0xa0), MODULUS)
            pop(staticcall(gas(), 0x05, free, 0xc0, 0x00, 0x20))
        }
        uint256 g1 = gasleft();
        console.log("MODEXP (field invert) gas:", g0 - g1);
    }

    function test_PrecompileCost_ECMUL() public view {
        // bn254 G1 generator * scalar
        uint256 g0 = gasleft();
        assembly {
            let free := mload(0x40)
            mstore(free, 1) // G1.x
            mstore(add(free, 0x20), 2) // G1.y
            mstore(add(free, 0x40), 7) // scalar
            pop(staticcall(gas(), 7, free, 0x60, free, 0x40))
        }
        uint256 g1 = gasleft();
        console.log("ECMUL gas:", g0 - g1);
    }

    function test_PrecompileCost_ECADD() public view {
        // G1 + G1
        uint256 g0 = gasleft();
        assembly {
            let free := mload(0x40)
            mstore(free, 1)
            mstore(add(free, 0x20), 2)
            mstore(add(free, 0x40), 1)
            mstore(add(free, 0x60), 2)
            pop(staticcall(gas(), 6, free, 0x80, free, 0x40))
        }
        uint256 g1 = gasleft();
        console.log("ECADD gas:", g0 - g1);
    }

    function test_PrecompileCost_ECPAIRING() public view {
        // Single pairing check: e(G1, G2) == e(G1, G2)
        uint256 g0 = gasleft();
        assembly {
            let free := mload(0x40)
            // P1 (G1 generator)
            mstore(free, 1)
            mstore(add(free, 0x20), 2)
            // Q1 (G2 generator)
            mstore(add(free, 0x40), 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2)
            mstore(add(free, 0x60), 0x1800deef121f1e76426a00665e5c4479674322d4f75edadd46debd5cd992f6ed)
            mstore(add(free, 0x80), 0x090689d0585ff075ec9e99ad690c3395bc4b313370b38ef355acdadcd122975b)
            mstore(add(free, 0xa0), 0x12c85ea5db8c6deb4aab71808dcb408fe3d1e7690c43d37b4ce6cc0166fa7daa)
            // P2 = -G1 (negate y)
            mstore(add(free, 0xc0), 1)
            mstore(add(free, 0xe0), 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd45) // P - 2
            // Q2 = G2 generator (same)
            mstore(add(free, 0x100), 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2)
            mstore(add(free, 0x120), 0x1800deef121f1e76426a00665e5c4479674322d4f75edadd46debd5cd992f6ed)
            mstore(add(free, 0x140), 0x090689d0585ff075ec9e99ad690c3395bc4b313370b38ef355acdadcd122975b)
            mstore(add(free, 0x160), 0x12c85ea5db8c6deb4aab71808dcb408fe3d1e7690c43d37b4ce6cc0166fa7daa)
            pop(staticcall(gas(), 8, free, 0x180, free, 0x20))
        }
        uint256 g1 = gasleft();
        console.log("ECPAIRING (2 pairs) gas:", g0 - g1);
    }

    function test_PrecompileCost_Summary() public view {
        console.log("=== Precompile Unit Costs ===");
        console.log("These are the per-call costs of each EVM precompile.");
        console.log("Multiply by call count to estimate component gas.");
        console.log("");
        console.log("Expected call counts in HonkVerifier:");
        console.log("  MODEXP:    ~40-60x (sumcheck barycentrics + shplemini inversions)");
        console.log("  ECMUL:     62x (MSMSize = 37 + LOG_N + 3 + 2)");
        console.log("  ECADD:     62x (one per MSM accumulation)");
        console.log("  ECPAIRING: 1x (final check, 2 pairs)");
    }
}
