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
        bytes32[] memory inputs = new bytes32[](4); // Wrong length (not 5)

        vm.expectRevert(SigstoreVerifier.InvalidPublicInputsLength.selector);
        verifier.decodePublicInputs(inputs);
    }

    function test_HonkVerifierDeployed() public view {
        assertTrue(address(verifier.honk()) != address(0));
    }

    // Helper: pack bytes32/bytes20 into 5-element public inputs array
    function _mockPublicInputs(
        bytes32 artifactHash,
        bytes32 repoHash,
        bytes20 commitSha
    ) internal pure returns (bytes32[] memory) {
        bytes32[] memory inputs = new bytes32[](5);
        inputs[0] = bytes32(uint256(artifactHash) >> 128); // artifact_hash_hi
        inputs[1] = bytes32(uint256(artifactHash) & ((1 << 128) - 1)); // artifact_hash_lo
        inputs[2] = bytes32(uint256(repoHash) >> 128); // repo_hash_hi
        inputs[3] = bytes32(uint256(repoHash) & ((1 << 128) - 1)); // repo_hash_lo
        inputs[4] = bytes32(uint256(uint160(commitSha))); // commit_sha_packed
        return inputs;
    }
}
