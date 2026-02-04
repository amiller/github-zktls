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
        bytes32 repoHash;      // Required repo (SHA-256 of "owner/repo")
        bytes32 artifactHash;  // Optional: specific artifact required (0 = any)
        uint256 amount;
        bool claimed;
    }

    mapping(uint256 => Bounty) public bounties;
    uint256 public nextBountyId;

    event BountyCreated(uint256 indexed id, address buyer, bytes32 repoHash, uint256 amount);
    event BountyClaimed(uint256 indexed id, address claimer, bytes20 commitSha);

    error BountyNotFound();
    error AlreadyClaimed();
    error RepoMismatch();
    error ArtifactMismatch();
    error TransferFailed();

    constructor(address _verifier) {
        verifier = ISigstoreVerifier(_verifier);
    }

    /// @notice Create a bounty requiring attestation from a specific repo
    /// @param repoHash SHA-256 of repo name (e.g., keccak256("owner/repo"))
    /// @param artifactHash Optional: require specific artifact (0 = any)
    function createBounty(bytes32 repoHash, bytes32 artifactHash) external payable returns (uint256 id) {
        id = nextBountyId++;
        bounties[id] = Bounty({
            buyer: msg.sender,
            repoHash: repoHash,
            artifactHash: artifactHash,
            amount: msg.value,
            claimed: false
        });
        emit BountyCreated(id, msg.sender, repoHash, msg.value);
    }

    /// @notice Claim bounty by providing a valid Sigstore attestation proof
    function claim(uint256 bountyId, bytes calldata proof, bytes32[] calldata publicInputs) external {
        Bounty storage b = bounties[bountyId];
        if (b.amount == 0) revert BountyNotFound();
        if (b.claimed) revert AlreadyClaimed();

        // Verify proof and decode attestation
        ISigstoreVerifier.Attestation memory att = verifier.verifyAndDecode(proof, publicInputs);

        // Check repo matches
        if (att.repoHash != b.repoHash) revert RepoMismatch();

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
