// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

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

/**
 * @title PredictionMarket V3 - Proper Sigstore Integration
 * @notice Parimutuel prediction market with cryptographic settlement
 */
contract PredictionMarket {
    ISigstoreVerifier public immutable verifier;
    address public owner;
    
    struct Market {
        string description;
        bytes32 conditionHash;
        bytes20 oracleCommitSha;
        uint256 deadline;
        bool settled;
        bool result;
        uint256 yesPool;
        uint256 noPool;
        uint256 totalYesShares;
        uint256 totalNoShares;
    }
    
    struct Bet {
        uint256 yesShares;
        uint256 noShares;
        bool claimed;
    }
    
    mapping(uint256 => Market) public markets;
    mapping(uint256 => mapping(address => Bet)) public bets;
    uint256 public marketCount;
    
    event MarketCreated(uint256 indexed marketId, string description, bytes32 conditionHash, bytes20 oracleCommitSha, uint256 deadline);
    event BetPlaced(uint256 indexed marketId, address indexed bettor, bool position, uint256 amount, uint256 shares);
    event MarketSettled(uint256 indexed marketId, address indexed settler, bool result, string topicId, string keyword, string oracleType);
    event WinningsClaimed(uint256 indexed marketId, address indexed winner, uint256 amount);
    
    error BettingClosed();
    error MarketAlreadySettled();
    error BettingStillOpen();
    error NoWinningBet();
    error AlreadyClaimed();
    error TransferFailed();
    error InvalidDeadline();
    error ZeroBet();
    error InvalidProof();
    error CertificateMismatch();
    error WrongCommit();
    error ParameterMismatch();
    error NotSettleable();
    error NoWinners();
    error NotOwner();
    
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }
    
    constructor(address _verifier) {
        verifier = ISigstoreVerifier(_verifier);
        owner = msg.sender;
    }
    
    function createMarket(
        string memory description,
        string memory topicId,
        string memory keyword,
        string memory oracleType,
        bytes20 oracleCommitSha,
        uint256 deadline
    ) external returns (uint256) {
        if (deadline <= block.timestamp) revert InvalidDeadline();
        bytes32 conditionHash = keccak256(abi.encode(topicId, keyword, oracleType));
        uint256 marketId = marketCount++;
        markets[marketId] = Market({
            description: description,
            conditionHash: conditionHash,
            oracleCommitSha: oracleCommitSha,
            deadline: deadline,
            settled: false,
            result: false,
            yesPool: 0,
            noPool: 0,
            totalYesShares: 0,
            totalNoShares: 0
        });
        emit MarketCreated(marketId, description, conditionHash, oracleCommitSha, deadline);
        return marketId;
    }
    
    function bet(uint256 marketId, bool position) external payable {
        Market storage market = markets[marketId];
        if (block.timestamp >= market.deadline) revert BettingClosed();
        if (market.settled) revert MarketAlreadySettled();
        if (msg.value == 0) revert ZeroBet();
        Bet storage userBet = bets[marketId][msg.sender];
        uint256 shares = msg.value;
        if (position) {
            market.yesPool += msg.value;
            market.totalYesShares += shares;
            userBet.yesShares += shares;
        } else {
            market.noPool += msg.value;
            market.totalNoShares += shares;
            userBet.noShares += shares;
        }
        emit BetPlaced(marketId, msg.sender, position, msg.value, shares);
    }
    
    function settle(
        uint256 marketId,
        bytes calldata proof,
        bytes32[] calldata publicInputs,
        bytes calldata certificate,
        string calldata topicId,
        string calldata keyword,
        string calldata oracleType
    ) external {
        Market storage market = markets[marketId];
        if (block.timestamp < market.deadline) revert BettingStillOpen();
        if (market.settled) revert MarketAlreadySettled();
        bytes32 providedHash = keccak256(abi.encode(topicId, keyword, oracleType));
        if (providedHash != market.conditionHash) revert ParameterMismatch();
        ISigstoreVerifier.Attestation memory att = verifier.verifyAndDecode(proof, publicInputs);
        if (sha256(certificate) != att.artifactHash) revert CertificateMismatch();
        if (market.oracleCommitSha != bytes20(0) && att.commitSha != market.oracleCommitSha) {
            revert WrongCommit();
        }
        bool settleable = containsBytes(certificate, bytes('"settleable": true'));
        bool found = containsBytes(certificate, bytes('"found": true'));
        if (!settleable) revert NotSettleable();
        bytes memory topicPattern = abi.encodePacked('"topic_id": "', topicId, '"');
        if (!containsBytes(certificate, topicPattern)) revert ParameterMismatch();
        bytes memory keywordPattern = abi.encodePacked('"keyword": "', keyword, '"');
        if (!containsBytes(certificate, keywordPattern)) revert ParameterMismatch();
        bytes memory typePattern = abi.encodePacked('"oracle_type": "', oracleType, '"');
        if (!containsBytes(certificate, typePattern)) revert ParameterMismatch();
        bool result = found;
        market.settled = true;
        market.result = result;
        emit MarketSettled(marketId, msg.sender, result, topicId, keyword, oracleType);
    }
    
    function claim(uint256 marketId) external {
        Market storage market = markets[marketId];
        if (!market.settled) revert MarketAlreadySettled();
        Bet storage userBet = bets[marketId][msg.sender];
        if (userBet.claimed) revert AlreadyClaimed();
        uint256 winningShares = market.result ? userBet.yesShares : userBet.noShares;
        if (winningShares == 0) revert NoWinningBet();
        userBet.claimed = true;
        uint256 totalPot = market.yesPool + market.noPool;
        uint256 totalWinningShares = market.result ? market.totalYesShares : market.totalNoShares;
        if (totalWinningShares == 0) revert NoWinners();
        uint256 payout = (winningShares * totalPot) / totalWinningShares;
        emit WinningsClaimed(marketId, msg.sender, payout);
        (bool success, ) = msg.sender.call{value: payout}("");
        if (!success) revert TransferFailed();
    }
    
    function getMarket(uint256 marketId) external view returns (
        string memory description, bytes32 conditionHash, bytes20 oracleCommitSha,
        uint256 deadline, bool settled, bool result, uint256 yesPool, uint256 noPool
    ) {
        Market storage market = markets[marketId];
        return (market.description, market.conditionHash, market.oracleCommitSha,
            market.deadline, market.settled, market.result, market.yesPool, market.noPool);
    }
    
    function getOdds(uint256 marketId) external view returns (uint256 yesOdds, uint256 noOdds) {
        Market storage market = markets[marketId];
        uint256 total = market.yesPool + market.noPool;
        if (total == 0) return (5000, 5000);
        yesOdds = (market.yesPool * 10000) / total;
        noOdds = (market.noPool * 10000) / total;
    }
    
    function getBet(uint256 marketId, address bettor) external view returns (
        uint256 yesShares, uint256 noShares, bool claimed
    ) {
        Bet storage userBet = bets[marketId][bettor];
        return (userBet.yesShares, userBet.noShares, userBet.claimed);
    }
    
    function getPotentialPayout(uint256 marketId, address bettor) external view returns (
        uint256 ifYesWins, uint256 ifNoWins
    ) {
        Market storage market = markets[marketId];
        Bet storage userBet = bets[marketId][bettor];
        uint256 totalPot = market.yesPool + market.noPool;
        if (market.totalYesShares > 0 && userBet.yesShares > 0) {
            ifYesWins = (userBet.yesShares * totalPot) / market.totalYesShares;
        }
        if (market.totalNoShares > 0 && userBet.noShares > 0) {
            ifNoWins = (userBet.noShares * totalPot) / market.totalNoShares;
        }
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
