// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @title ISigstoreVerifier
/// @notice Interface for verifying Sigstore attestations via ZK proofs
/// @dev Implementations verify that an artifact was signed by a certificate
///      issued by Sigstore's Fulcio CA for a specific GitHub repo and commit
interface ISigstoreVerifier {
    /// @notice Attestation data extracted from a valid proof
    struct Attestation {
        bytes32 artifactHash;  // SHA-256 of the attested artifact
        bytes32 repoHash;      // SHA-256 of repo name (e.g., "owner/repo")
        bytes20 commitSha;     // Git commit SHA
    }

    /// @notice Verify a ZK proof of Sigstore attestation
    /// @param proof The proof bytes from bb prove
    /// @param publicInputs The public inputs (84 field elements as bytes32[])
    /// @return valid True if proof is valid
    function verify(bytes calldata proof, bytes32[] calldata publicInputs) external view returns (bool valid);

    /// @notice Verify and decode attestation data from proof
    /// @param proof The proof bytes
    /// @param publicInputs The public inputs
    /// @return attestation The decoded attestation if valid, reverts otherwise
    function verifyAndDecode(bytes calldata proof, bytes32[] calldata publicInputs)
        external view returns (Attestation memory attestation);

    /// @notice Decode public inputs into attestation struct (no verification)
    /// @param publicInputs The public inputs (84 field elements)
    /// @return attestation The decoded attestation
    function decodePublicInputs(bytes32[] calldata publicInputs)
        external pure returns (Attestation memory attestation);
}
