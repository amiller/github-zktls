// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ISigstoreVerifier} from "./ISigstoreVerifier.sol";
import {HonkVerifier} from "./HonkVerifier.sol";

/// @title SigstoreVerifier
/// @notice Verifies ZK proofs of Sigstore attestations
/// @dev Wraps the generated HonkVerifier with typed helpers
///      Public inputs layout (5 packed field elements, each as bytes32):
///      [0]: artifact_hash_hi (upper 16 bytes, big-endian)
///      [1]: artifact_hash_lo (lower 16 bytes, big-endian)
///      [2]: repo_hash_hi
///      [3]: repo_hash_lo
///      [4]: commit_sha_packed (20 bytes as uint160)
contract SigstoreVerifier is ISigstoreVerifier {
    HonkVerifier public immutable honk;

    error InvalidProof();
    error InvalidPublicInputsLength();

    uint256 constant EXPECTED_PUBLIC_INPUTS = 5;

    constructor(address _honkVerifier) {
        honk = HonkVerifier(_honkVerifier);
    }

    /// @inheritdoc ISigstoreVerifier
    function verify(bytes calldata proof, bytes32[] calldata publicInputs) external view override returns (bool) {
        return honk.verify(proof, publicInputs);
    }

    /// @inheritdoc ISigstoreVerifier
    function verifyAndDecode(bytes calldata proof, bytes32[] calldata publicInputs)
        external view override returns (Attestation memory attestation)
    {
        if (!honk.verify(proof, publicInputs)) revert InvalidProof();
        return _decode(publicInputs);
    }

    /// @inheritdoc ISigstoreVerifier
    function decodePublicInputs(bytes32[] calldata publicInputs)
        external pure override returns (Attestation memory attestation)
    {
        return _decode(publicInputs);
    }

    function _decode(bytes32[] calldata inputs) internal pure returns (Attestation memory att) {
        if (inputs.length != EXPECTED_PUBLIC_INPUTS) revert InvalidPublicInputsLength();
        att.artifactHash = bytes32((uint256(inputs[0]) << 128) | uint256(inputs[1]));
        att.repoHash = bytes32((uint256(inputs[2]) << 128) | uint256(inputs[3]));
        att.commitSha = bytes20(uint160(uint256(inputs[4])));
    }
}
