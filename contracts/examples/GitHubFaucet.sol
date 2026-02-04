// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISigstoreVerifier} from "../src/ISigstoreVerifier.sol";

/// @title GitHubFaucet
/// @notice Testnet faucet that distributes ETH to unique GitHub users (one claim per day)
/// @dev Verifies the certificate JSON matches the attested artifactHash, then rate-limits per username
contract GitHubFaucet {
    ISigstoreVerifier public immutable verifier;

    uint256 public constant COOLDOWN = 1 days;
    uint256 public constant MAX_CLAIM = 0.001 ether;
    uint256 public constant RESERVE_DIVISOR = 20; // max 5% of reserves per claim

    // keccak256(username) => last claim timestamp
    mapping(bytes32 => uint256) public lastClaim;

    // Required workflow commit (set to 0 to accept any)
    bytes20 public requiredCommitSha;

    event Claimed(address indexed recipient, string indexed username, uint256 amount);
    event RequirementsUpdated(bytes20 commitSha);

    error InvalidProof();
    error CertificateMismatch();
    error UsernameMismatch();
    error WrongCommit();
    error AlreadyClaimedToday();
    error FaucetEmpty();

    constructor(address _verifier) {
        verifier = ISigstoreVerifier(_verifier);
    }

    receive() external payable {}

    /// @notice Claim testnet ETH by proving GitHub identity
    /// @param proof The ZK proof
    /// @param publicInputs The public inputs (artifactHash, repoHash, commitSha)
    /// @param certificate The raw certificate.json that was attested
    /// @param username The GitHub username (must appear in certificate as "github_actor")
    /// @param recipient Address to receive ETH
    function claim(
        bytes calldata proof,
        bytes32[] calldata publicInputs,
        bytes calldata certificate,
        string calldata username,
        address payable recipient
    ) external {
        ISigstoreVerifier.Attestation memory att = verifier.verifyAndDecode(proof, publicInputs);

        // Verify certificate matches attested artifact
        if (sha256(certificate) != att.artifactHash) revert CertificateMismatch();

        // Verify username appears in certificate as "github_actor":"<username>"
        // We check for the exact pattern to prevent injection
        bytes memory pattern = abi.encodePacked('"github_actor":"', username, '"');
        if (!containsBytes(certificate, pattern)) revert UsernameMismatch();

        // Check commit requirement if set
        if (requiredCommitSha != bytes20(0) && att.commitSha != requiredCommitSha) {
            revert WrongCommit();
        }

        // Rate limit per user (not per repo)
        bytes32 userKey = keccak256(bytes(username));
        if (block.timestamp - lastClaim[userKey] < COOLDOWN) revert AlreadyClaimedToday();
        lastClaim[userKey] = block.timestamp;

        // Calculate claim amount
        uint256 amount = address(this).balance / RESERVE_DIVISOR;
        if (amount > MAX_CLAIM) amount = MAX_CLAIM;
        if (amount == 0) revert FaucetEmpty();

        emit Claimed(recipient, username, amount);
        recipient.transfer(amount);
    }

    /// @notice Set required commit SHA (owner only for production)
    function setRequirements(bytes20 _commitSha) external {
        requiredCommitSha = _commitSha;
        emit RequirementsUpdated(_commitSha);
    }

    /// @notice Check if a user can claim
    function canClaim(string calldata username) external view returns (bool, uint256 nextClaimTime) {
        bytes32 userKey = keccak256(bytes(username));
        uint256 last = lastClaim[userKey];
        if (block.timestamp - last >= COOLDOWN) {
            return (true, 0);
        }
        return (false, last + COOLDOWN);
    }

    /// @notice Get current claim amount
    function claimAmount() external view returns (uint256) {
        uint256 amount = address(this).balance / RESERVE_DIVISOR;
        return amount > MAX_CLAIM ? MAX_CLAIM : amount;
    }

    /// @dev Check if haystack contains needle
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
