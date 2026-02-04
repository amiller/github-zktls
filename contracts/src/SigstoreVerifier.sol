// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ISigstoreVerifier} from "./ISigstoreVerifier.sol";
import {HonkVerifier} from "./HonkVerifier.sol";

/// @title SigstoreVerifier
/// @notice Verifies ZK proofs of Sigstore attestations
/// @dev Wraps the generated HonkVerifier with typed helpers
///      Public inputs layout (84 field elements, each as bytes32):
///      [0-31]:  artifact_hash (32 bytes)
///      [32-63]: repo_hash (32 bytes)
///      [64-83]: commit_sha (20 bytes)
contract SigstoreVerifier is ISigstoreVerifier {
    HonkVerifier public immutable honk;

    error InvalidProof();
    error InvalidPublicInputsLength();

    uint256 constant EXPECTED_PUBLIC_INPUTS = 84;

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

        // artifact_hash: bytes 0-31
        for (uint i = 0; i < 32; i++) {
            att.artifactHash |= bytes32(uint256(inputs[i]) << (248 - i * 8));
        }

        // repo_hash: bytes 32-63
        for (uint i = 0; i < 32; i++) {
            att.repoHash |= bytes32(uint256(inputs[32 + i]) << (248 - i * 8));
        }

        // commit_sha: bytes 64-83
        for (uint i = 0; i < 20; i++) {
            att.commitSha |= bytes20(uint160(uint256(inputs[64 + i]) << (152 - i * 8)));
        }
    }
}
