// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISigstoreVerifier} from "../src/ISigstoreVerifier.sol";

/// @title GitHubFaucet
/// @notice Testnet faucet that distributes ETH to unique GitHub repos (one claim per day)
contract GitHubFaucet {
    ISigstoreVerifier public immutable verifier;

    uint256 public constant COOLDOWN = 1 days;
    uint256 public constant MAX_CLAIM = 0.001 ether;
    uint256 public constant RESERVE_DIVISOR = 20; // max 5% of reserves per claim

    // repoHash => last claim timestamp
    mapping(bytes32 => uint256) public lastClaim;

    // Required workflow commit (set to 0 to accept any)
    bytes32 public requiredRepoHash;
    bytes20 public requiredCommitSha;

    event Claimed(address indexed recipient, bytes32 indexed repoHash, uint256 amount);
    event RequirementsUpdated(bytes32 repoHash, bytes20 commitSha);

    constructor(address _verifier) {
        verifier = ISigstoreVerifier(_verifier);
    }

    receive() external payable {}

    /// @notice Claim testnet ETH by proving GitHub identity
    /// @param proof The ZK proof
    /// @param publicInputs The public inputs (artifactHash, repoHash, commitSha)
    /// @param recipient Address to receive ETH
    function claim(
        bytes calldata proof,
        bytes32[] calldata publicInputs,
        address payable recipient
    ) external {
        ISigstoreVerifier.Attestation memory att = verifier.verifyAndDecode(proof, publicInputs);

        // Check workflow requirements if set
        if (requiredRepoHash != bytes32(0)) {
            require(att.repoHash == requiredRepoHash, "Wrong repo");
        }
        if (requiredCommitSha != bytes20(0)) {
            require(att.commitSha == requiredCommitSha, "Wrong commit");
        }

        // Check cooldown (per repo, not per user - Sybil resistant)
        require(block.timestamp - lastClaim[att.repoHash] >= COOLDOWN, "Already claimed today");
        lastClaim[att.repoHash] = block.timestamp;

        // Calculate claim amount: min(MAX_CLAIM, balance/RESERVE_DIVISOR)
        uint256 amount = address(this).balance / RESERVE_DIVISOR;
        if (amount > MAX_CLAIM) amount = MAX_CLAIM;
        require(amount > 0, "Faucet empty");

        emit Claimed(recipient, att.repoHash, amount);
        recipient.transfer(amount);
    }

    /// @notice Set required workflow repo/commit (owner only for production)
    /// @dev In production, add access control. For demo, anyone can set.
    function setRequirements(bytes32 _repoHash, bytes20 _commitSha) external {
        requiredRepoHash = _repoHash;
        requiredCommitSha = _commitSha;
        emit RequirementsUpdated(_repoHash, _commitSha);
    }

    /// @notice Check if a repo can claim
    function canClaim(bytes32 repoHash) external view returns (bool, uint256 nextClaimTime) {
        uint256 last = lastClaim[repoHash];
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
}
