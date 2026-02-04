// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "./GitHubAttestationVerifier.sol";

/// @title GitHubAttestation
/// @notice Verifies ZK proofs of GitHub Actions attestations and tracks verified claims
contract GitHubAttestation {
    HonkVerifier public immutable verifier;

    // Events
    event AttestationVerified(
        bytes32 indexed artifactHash,
        bytes32 indexed repoHash,
        bytes20 indexed commitSha,
        address verifier
    );

    // Mapping to track verified attestations
    mapping(bytes32 => bool) public verifiedArtifacts;

    // Store verified attestation data
    struct Attestation {
        bytes32 artifactHash;
        bytes32 repoHash;
        bytes20 commitSha;
        uint256 timestamp;
        address verifiedBy;
    }
    mapping(bytes32 => Attestation) public attestations;

    constructor() {
        verifier = new HonkVerifier();
    }

    /// @notice Verify a GitHub attestation proof
    /// @param proof The ZK proof bytes
    /// @param publicInputs The public inputs (artifact_hash, repo_hash, commit_sha)
    /// @return success Whether the proof verified successfully
    function verifyAttestation(
        bytes calldata proof,
        bytes32[] calldata publicInputs
    ) external returns (bool success) {
        // Verify the proof
        success = verifier.verify(proof, publicInputs);
        require(success, "Proof verification failed");

        // Extract public inputs (each is 32 bytes in the proof, but we pack them)
        // artifact_hash: 32 bytes (indices 0-31)
        // repo_hash: 32 bytes (indices 32-63)
        // commit_sha: 20 bytes (indices 64-83)
        bytes32 artifactHash = extractArtifactHash(publicInputs);
        bytes32 repoHash = extractRepoHash(publicInputs);
        bytes20 commitSha = extractCommitSha(publicInputs);

        // Store attestation
        bytes32 attestationId = keccak256(abi.encodePacked(artifactHash, repoHash, commitSha));
        verifiedArtifacts[artifactHash] = true;
        attestations[attestationId] = Attestation({
            artifactHash: artifactHash,
            repoHash: repoHash,
            commitSha: commitSha,
            timestamp: block.timestamp,
            verifiedBy: msg.sender
        });

        emit AttestationVerified(artifactHash, repoHash, commitSha, msg.sender);
        return true;
    }

    /// @notice Check if an artifact has been verified
    function isArtifactVerified(bytes32 artifactHash) external view returns (bool) {
        return verifiedArtifacts[artifactHash];
    }

    /// @notice Get attestation details
    function getAttestation(bytes32 attestationId) external view returns (Attestation memory) {
        return attestations[attestationId];
    }

    /// @notice Compute attestation ID from components
    function computeAttestationId(
        bytes32 artifactHash,
        bytes32 repoHash,
        bytes20 commitSha
    ) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(artifactHash, repoHash, commitSha));
    }

    // Extract artifact hash from public inputs (first 32 field elements, each is 1 byte)
    function extractArtifactHash(bytes32[] calldata publicInputs) internal pure returns (bytes32) {
        bytes memory result = new bytes(32);
        for (uint i = 0; i < 32; i++) {
            result[i] = bytes1(uint8(uint256(publicInputs[i])));
        }
        return bytes32(result);
    }

    // Extract repo hash from public inputs (next 32 field elements)
    function extractRepoHash(bytes32[] calldata publicInputs) internal pure returns (bytes32) {
        bytes memory result = new bytes(32);
        for (uint i = 0; i < 32; i++) {
            result[i] = bytes1(uint8(uint256(publicInputs[32 + i])));
        }
        return bytes32(result);
    }

    // Extract commit SHA from public inputs (next 20 field elements)
    function extractCommitSha(bytes32[] calldata publicInputs) internal pure returns (bytes20) {
        bytes memory result = new bytes(20);
        for (uint i = 0; i < 20; i++) {
            result[i] = bytes1(uint8(uint256(publicInputs[64 + i])));
        }
        return bytes20(result);
    }
}
