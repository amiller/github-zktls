// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ISigstoreVerifier} from "../src/ISigstoreVerifier.sol";

/// @title SimpleEscrow
/// @notice Example escrow that releases funds when a valid Sigstore attestation is provided
/// @dev Shows how to use ISigstoreVerifier - not production ready
contract SimpleEscrow {
    ISigstoreVerifier public immutable verifier;

    struct Bounty {
        address buyer;
        bytes20 commitSha;     // Required: exact commit that must run (pins immutable code)
        bytes32 repoHash;      // Optional: repo filter (0 = any). Informational — prover controls their repo
        bytes32 artifactHash;  // Optional: specific artifact required (0 = any)
        uint256 amount;
        bool claimed;
    }

    mapping(uint256 => Bounty) public bounties;
    uint256 public nextBountyId;

    event BountyCreated(uint256 indexed id, address buyer, bytes20 commitSha, uint256 amount);
    event BountyClaimed(uint256 indexed id, address claimer, bytes20 commitSha);

    error BountyNotFound();
    error AlreadyClaimed();
    error CommitMismatch();
    error RepoMismatch();
    error ArtifactMismatch();
    error TransferFailed();

    constructor(address _verifier) {
        verifier = ISigstoreVerifier(_verifier);
    }

    /// @notice Create a bounty requiring attestation from a specific commit
    /// @param commitSha Required: exact git commit SHA (pins auditable code)
    /// @param repoHash Optional: SHA-256 of "owner/repo" (0 = skip check)
    /// @param artifactHash Optional: require specific artifact (0 = any)
    function createBounty(bytes20 commitSha, bytes32 repoHash, bytes32 artifactHash) external payable returns (uint256 id) {
        id = nextBountyId++;
        bounties[id] = Bounty({
            buyer: msg.sender,
            commitSha: commitSha,
            repoHash: repoHash,
            artifactHash: artifactHash,
            amount: msg.value,
            claimed: false
        });
        emit BountyCreated(id, msg.sender, commitSha, msg.value);
    }

    /// @notice Claim bounty by providing a valid Sigstore attestation proof
    function claim(uint256 bountyId, bytes calldata proof, bytes32[] calldata publicInputs) external {
        Bounty storage b = bounties[bountyId];
        if (b.amount == 0) revert BountyNotFound();
        if (b.claimed) revert AlreadyClaimed();

        // Verify proof and decode attestation
        ISigstoreVerifier.Attestation memory att = verifier.verifyAndDecode(proof, publicInputs);

        // Check commit matches (required — pins immutable, auditable code)
        if (att.commitSha != b.commitSha) revert CommitMismatch();

        // Check repo if specified (optional — informational only)
        if (b.repoHash != bytes32(0) && att.repoHash != b.repoHash) revert RepoMismatch();

        // Check artifact if specified
        if (b.artifactHash != bytes32(0) && att.artifactHash != b.artifactHash) revert ArtifactMismatch();

        // Mark claimed and transfer
        b.claimed = true;
        (bool ok,) = msg.sender.call{value: b.amount}("");
        if (!ok) revert TransferFailed();

        emit BountyClaimed(bountyId, msg.sender, att.commitSha);
    }

    /// @notice Helper to compute repo hash
    function computeRepoHash(string calldata repo) external pure returns (bytes32) {
        return sha256(bytes(repo));
    }
}
