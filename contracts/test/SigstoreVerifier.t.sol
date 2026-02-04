// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {SigstoreVerifier} from "../src/SigstoreVerifier.sol";
import {ISigstoreVerifier} from "../src/ISigstoreVerifier.sol";
import {HonkVerifier} from "../src/HonkVerifier.sol";

contract SigstoreVerifierTest is Test {
    SigstoreVerifier verifier;
    HonkVerifier honk;

    function setUp() public {
        honk = new HonkVerifier();
        verifier = new SigstoreVerifier(address(honk));
    }

    function test_DecodePublicInputs() public view {
        bytes32[] memory inputs = _mockPublicInputs(
            bytes32(uint256(0x1234)),  // artifactHash
            bytes32(uint256(0x5678)),  // repoHash
            bytes20(uint160(0xABCD))   // commitSha
        );

        ISigstoreVerifier.Attestation memory att = verifier.decodePublicInputs(inputs);

        assertEq(uint256(att.artifactHash), 0x1234);
        assertEq(uint256(att.repoHash), 0x5678);
        assertEq(uint160(att.commitSha), 0xABCD);
    }

    function test_DecodePublicInputs_RealValues() public view {
        // Test with realistic hash values
        bytes32 artifactHash = sha256("test artifact content");
        bytes32 repoHash = sha256("owner/repo");
        bytes20 commitSha = bytes20(hex"a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2");

        bytes32[] memory inputs = _mockPublicInputs(artifactHash, repoHash, commitSha);
        ISigstoreVerifier.Attestation memory att = verifier.decodePublicInputs(inputs);

        assertEq(att.artifactHash, artifactHash);
        assertEq(att.repoHash, repoHash);
        assertEq(att.commitSha, commitSha);
    }

    function test_DecodePublicInputs_RevertIfWrongLength() public {
        bytes32[] memory inputs = new bytes32[](83); // Wrong length

        vm.expectRevert(SigstoreVerifier.InvalidPublicInputsLength.selector);
        verifier.decodePublicInputs(inputs);
    }

    function test_HonkVerifierDeployed() public view {
        // Check that the HonkVerifier was deployed
        assertTrue(address(verifier.honk()) != address(0));
    }

    // Helper: create mock public inputs from components
    function _mockPublicInputs(
        bytes32 artifactHash,
        bytes32 repoHash,
        bytes20 commitSha
    ) internal pure returns (bytes32[] memory) {
        bytes32[] memory inputs = new bytes32[](84);

        // artifact_hash: bytes 0-31
        for (uint i = 0; i < 32; i++) {
            inputs[i] = bytes32(uint256(uint8(artifactHash[i])));
        }

        // repo_hash: bytes 32-63
        for (uint i = 0; i < 32; i++) {
            inputs[32 + i] = bytes32(uint256(uint8(repoHash[i])));
        }

        // commit_sha: bytes 64-83
        for (uint i = 0; i < 20; i++) {
            inputs[64 + i] = bytes32(uint256(uint8(commitSha[i])));
        }

        return inputs;
    }
}
