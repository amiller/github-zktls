// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ISigstoreVerifier} from "../src/ISigstoreVerifier.sol";

/// @title AgentEscrow
/// @notice Bounty marketplace with AI judge for evaluating claims
/// @dev Advanced example showing judge-mediated bounty claims
contract AgentEscrow {
    ISigstoreVerifier public immutable verifier;

    struct Bounty {
        address creator;
        uint256 amount;
        bytes32 promptHash;      // keccak256(prompt)
        string promptUri;        // ipfs://Qm... for retrieval
        bytes20 commitSha;       // Required: exact commit that must run
        bytes32 repoHash;        // Optional: repo filter (0 = any)
        address judge;           // AI judge address
        uint256 deadline;
        bool claimed;
    }

    struct Claim {
        uint256 bountyId;
        bytes32 artifactHash;
        bytes20 commitSha;
        address payable recipient;
        bool approved;
        bool judged;
    }

    uint256 public nextBountyId;
    uint256 public nextClaimId;

    mapping(uint256 => Bounty) public bounties;
    mapping(uint256 => Claim) public claims;
    mapping(bytes32 => bool) public claimedArtifacts;

    event BountyCreated(uint256 indexed bountyId, address indexed creator, uint256 amount, bytes20 commitSha);
    event ClaimSubmitted(uint256 indexed claimId, uint256 indexed bountyId, bytes32 artifactHash, bytes20 commitSha);
    event ClaimJudged(uint256 indexed claimId, uint256 indexed bountyId, bool approved);
    event BountyRefunded(uint256 indexed bountyId, address indexed creator, uint256 amount);

    error BountyNotFound();
    error AlreadyClaimed();
    error Expired();
    error CommitMismatch();
    error RepoMismatch();
    error NotJudge();
    error AlreadyJudged();
    error NotCreator();
    error DeadlineNotPassed();
    error TransferFailed();

    constructor(address _verifier) {
        verifier = ISigstoreVerifier(_verifier);
    }

    function createBounty(
        bytes32 promptHash,
        string calldata promptUri,
        bytes20 commitSha,
        bytes32 repoHash,
        address judge,
        uint256 deadline
    ) external payable returns (uint256 bountyId) {
        bountyId = nextBountyId++;
        bounties[bountyId] = Bounty({
            creator: msg.sender,
            amount: msg.value,
            promptHash: promptHash,
            promptUri: promptUri,
            commitSha: commitSha,
            repoHash: repoHash,
            judge: judge,
            deadline: deadline,
            claimed: false
        });
        emit BountyCreated(bountyId, msg.sender, msg.value, commitSha);
    }

    function submitClaim(
        uint256 bountyId,
        bytes calldata proof,
        bytes32[] calldata publicInputs
    ) external returns (uint256 claimId) {
        Bounty storage bounty = bounties[bountyId];
        if (bounty.amount == 0) revert BountyNotFound();
        if (bounty.claimed) revert AlreadyClaimed();
        if (block.timestamp > bounty.deadline) revert Expired();

        // Verify proof and decode attestation
        ISigstoreVerifier.Attestation memory att = verifier.verifyAndDecode(proof, publicInputs);

        // Check commit matches (required — pins immutable, auditable code)
        if (att.commitSha != bounty.commitSha) revert CommitMismatch();

        // Check repo if specified (optional — informational only)
        if (bounty.repoHash != bytes32(0) && att.repoHash != bounty.repoHash) revert RepoMismatch();

        // Prevent double-claiming
        if (claimedArtifacts[att.artifactHash]) revert AlreadyClaimed();
        claimedArtifacts[att.artifactHash] = true;

        claimId = nextClaimId++;
        claims[claimId] = Claim({
            bountyId: bountyId,
            artifactHash: att.artifactHash,
            commitSha: att.commitSha,
            recipient: payable(msg.sender),
            approved: false,
            judged: false
        });

        emit ClaimSubmitted(claimId, bountyId, att.artifactHash, att.commitSha);
    }

    function judgeClaim(uint256 claimId, bool approved) external {
        Claim storage claim = claims[claimId];
        Bounty storage bounty = bounties[claim.bountyId];

        if (msg.sender != bounty.judge) revert NotJudge();
        if (claim.judged) revert AlreadyJudged();
        if (bounty.claimed) revert AlreadyClaimed();

        claim.judged = true;
        claim.approved = approved;

        if (approved) {
            bounty.claimed = true;
            (bool ok,) = claim.recipient.call{value: bounty.amount}("");
            if (!ok) revert TransferFailed();
        }

        emit ClaimJudged(claimId, claim.bountyId, approved);
    }

    function refund(uint256 bountyId) external {
        Bounty storage bounty = bounties[bountyId];
        if (msg.sender != bounty.creator) revert NotCreator();
        if (bounty.claimed) revert AlreadyClaimed();
        if (block.timestamp <= bounty.deadline) revert DeadlineNotPassed();

        uint256 amount = bounty.amount;
        bounty.amount = 0;
        bounty.claimed = true;

        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit BountyRefunded(bountyId, msg.sender, amount);
    }

    function computeRepoHash(string calldata repo) external pure returns (bytes32) {
        return sha256(bytes(repo));
    }
}
