// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ISigstoreVerifier} from "../src/ISigstoreVerifier.sol";

/// @title SelfJudgingEscrow
/// @notice Bounty escrow where Claude (in GitHub Actions) judges the work
/// @dev Worker runs a workflow that calls Claude to evaluate their diff.
///      The certificate includes "judgment": "approved" which we verify on-chain.
contract SelfJudgingEscrow {
    ISigstoreVerifier public immutable verifier;

    struct Bounty {
        address creator;
        uint256 amount;
        bytes32 promptHash;
        string prompt;
        bytes20 commitSha;     // Required: exact commit that must run
        bytes32 repoHash;      // Optional: repo filter (0 = any)
        uint256 deadline;
        bool claimed;
    }

    mapping(uint256 => Bounty) public bounties;
    uint256 public nextBountyId;

    event BountyCreated(uint256 indexed id, address creator, bytes20 commitSha, uint256 amount);
    event BountyClaimed(uint256 indexed id, address claimer, bytes20 commitSha);
    event BountyRefunded(uint256 indexed id, address creator, uint256 amount);

    error BountyNotFound();
    error AlreadyClaimed();
    error CommitMismatch();
    error RepoMismatch();
    error JudgmentNotApproved();
    error CertificateMismatch();
    error NotCreator();
    error DeadlineNotPassed();
    error Expired();
    error TransferFailed();

    constructor(address _verifier) {
        verifier = ISigstoreVerifier(_verifier);
    }

    /// @notice Create a bounty for work verified at a specific commit
    function createBounty(
        bytes32 promptHash,
        string calldata prompt,
        bytes20 commitSha,
        bytes32 repoHash,
        uint256 deadline
    ) external payable returns (uint256 id) {
        id = nextBountyId++;
        bounties[id] = Bounty({
            creator: msg.sender,
            amount: msg.value,
            promptHash: promptHash,
            prompt: prompt,
            commitSha: commitSha,
            repoHash: repoHash,
            deadline: deadline,
            claimed: false
        });
        emit BountyCreated(id, msg.sender, commitSha, msg.value);
    }

    /// @notice Claim bounty by providing proof that Claude approved the work
    function claim(
        uint256 bountyId,
        bytes calldata proof,
        bytes32[] calldata publicInputs,
        bytes calldata certificate
    ) external {
        Bounty storage b = bounties[bountyId];
        if (b.amount == 0) revert BountyNotFound();
        if (b.claimed) revert AlreadyClaimed();
        if (block.timestamp > b.deadline) revert Expired();

        ISigstoreVerifier.Attestation memory att = verifier.verifyAndDecode(proof, publicInputs);

        // Certificate must match attested artifact
        if (sha256(certificate) != att.artifactHash) revert CertificateMismatch();

        // Check commit matches (required — pins immutable, auditable code)
        if (att.commitSha != b.commitSha) revert CommitMismatch();

        // Check repo if specified (optional — informational only)
        if (b.repoHash != bytes32(0) && att.repoHash != b.repoHash) revert RepoMismatch();

        // Check certificate contains "judgment": "approved"
        // Using the exact JSON format from the workflow
        if (!containsBytes(certificate, bytes('"judgment": "approved"'))) {
            revert JudgmentNotApproved();
        }

        b.claimed = true;
        (bool ok,) = msg.sender.call{value: b.amount}("");
        if (!ok) revert TransferFailed();

        emit BountyClaimed(bountyId, msg.sender, att.commitSha);
    }

    /// @notice Refund bounty after deadline
    function refund(uint256 bountyId) external {
        Bounty storage b = bounties[bountyId];
        if (msg.sender != b.creator) revert NotCreator();
        if (b.claimed) revert AlreadyClaimed();
        if (block.timestamp <= b.deadline) revert DeadlineNotPassed();

        uint256 amount = b.amount;
        b.amount = 0;
        b.claimed = true;

        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit BountyRefunded(bountyId, msg.sender, amount);
    }

    function computeRepoHash(string calldata repo) external pure returns (bytes32) {
        return sha256(bytes(repo));
    }

    function containsBytes(bytes calldata haystack, bytes memory needle) internal pure returns (bool) {
        if (needle.length > haystack.length) return false;
        uint256 end = haystack.length - needle.length + 1;
        for (uint256 i = 0; i < end; i++) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }
}
