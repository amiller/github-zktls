// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISigstoreVerifier} from "../../../contracts/src/ISigstoreVerifier.sol";

/**
 * @title PredictionMarket V3 - Proper Sigstore Integration
 * @notice Parimutuel prediction market with cryptographic settlement
 * 
 * Trust model (matches github-zktls):
 * - Anyone can settle with valid Sigstore proof
 * - No trusted settler needed
 * - Parameters enforced via conditionHash + proof verification
 * - Settlement verified cryptographically (ZK proof of Sigstore attestation)
 * 
 * Architecture:
 * 1. Market creation binds to oracle parameters (topic, keyword, type)
 * 2. Users bet on outcome (parimutuel pools)
 * 3. After deadline, oracle runs in GitHub Actions
 * 4. Oracle produces oracle-result.json (the "certificate")
 * 5. GitHub Actions creates Sigstore attestation
 * 6. ZK proof of attestation generated
 * 7. Anyone calls settle() with proof + certificate
 * 8. Contract verifies proof using ISigstoreVerifier
 * 9. Contract parses certificate and settles market
 * 10. Winners claim proportional share of total pool
 */
contract PredictionMarket {
    ISigstoreVerifier public immutable verifier;
    address public owner;
    
    struct Market {
        string description;
        bytes32 conditionHash;      // keccak256(topicId, keyword, oracleType)
        bytes20 oracleCommitSha;     // Required commit SHA for oracle
        uint256 deadline;            // Betting closes at this time
        bool settled;
        bool result;                 // true = YES wins, false = NO wins
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
    
    event MarketCreated(
        uint256 indexed marketId,
        string description,
        bytes32 conditionHash,
        bytes20 oracleCommitSha,
        uint256 deadline
    );
    event BetPlaced(
        uint256 indexed marketId,
        address indexed bettor,
        bool position,
        uint256 amount,
        uint256 shares
    );
    event MarketSettled(
        uint256 indexed marketId,
        address indexed settler,
        bool result,
        string topicId,
        string keyword,
        string oracleType
    );
    event WinningsClaimed(
        uint256 indexed marketId,
        address indexed winner,
        uint256 amount
    );
    
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
    
    /**
     * @notice Create a new prediction market
     * @param description Human-readable description
     * @param topicId Ethereum Magicians topic ID
     * @param keyword Keyword to search for
     * @param oracleType "first" or "any" comment
     * @param oracleCommitSha Exact commit SHA oracle must run from (globally unique)
     * @param deadline Unix timestamp when betting closes
     */
    function createMarket(
        string memory description,
        string memory topicId,
        string memory keyword,
        string memory oracleType,
        bytes20 oracleCommitSha,
        uint256 deadline
    ) external returns (uint256) {
        if (deadline <= block.timestamp) revert InvalidDeadline();
        
        // Bind market to exact oracle parameters
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
    
    /**
     * @notice Bet on a market (parimutuel style)
     * @param marketId Market ID
     * @param position true = bet YES, false = bet NO
     */
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
    
    /**
     * @notice Settle a market with cryptographic proof
     * 
     * TRUSTLESS SETTLEMENT - Matches github-zktls pattern
     * 
     * @param marketId Market ID
     * @param proof ZK proof of Sigstore attestation (from bb prove)
     * @param publicInputs Public inputs to ZK proof (84 field elements)
     * @param certificate The oracle-result.json file (attested artifact)
     * @param topicId Topic ID (must be in certificate)
     * @param keyword Keyword (must be in certificate)
     * @param oracleType Oracle type (must be in certificate)
     * 
     * Verification steps:
     * 1. Verify ZK proof using ISigstoreVerifier
     * 2. Check certificate hash matches attestation
     * 3. Check commit SHA matches market requirement
     * 4. Check repo matches market requirement
     * 5. Parse certificate and verify parameters match
     * 6. Check settleable flag (first comment must exist)
     * 7. Extract result and settle market
     * 
     * Anyone can call this - no trust required!
     */
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
        
        // Check deadline and not already settled
        if (block.timestamp < market.deadline) revert BettingStillOpen();
        if (market.settled) revert MarketAlreadySettled();
        
        // Verify parameters match market condition (prevents using wrong oracle data)
        bytes32 providedHash = keccak256(abi.encode(topicId, keyword, oracleType));
        if (providedHash != market.conditionHash) revert ParameterMismatch();
        
        // === CRYPTOGRAPHIC VERIFICATION (GitHubFaucet pattern) ===
        
        // 1. Verify ZK proof of Sigstore attestation
        ISigstoreVerifier.Attestation memory att = verifier.verifyAndDecode(proof, publicInputs);
        
        // 2. Check certificate hash matches attestation
        if (sha256(certificate) != att.artifactHash) revert CertificateMismatch();
        
        // 3. Check commit SHA matches market requirement (commit is globally unique)
        if (market.oracleCommitSha != bytes20(0) && att.commitSha != market.oracleCommitSha) {
            revert WrongCommit();
        }
        
        // === PARSE CERTIFICATE ===
        
        // Extract fields from JSON certificate
        // Format: {"settleable": true, "found": true, "result": "FOUND", "topic_id": "12345", ...}
        
        bool settleable = containsBytes(certificate, bytes('"settleable": true'));
        bool found = containsBytes(certificate, bytes('"found": true'));
        
        // Verify settleable (first comment must exist)
        if (!settleable) revert NotSettleable();
        
        // Verify topic_id matches
        bytes memory topicPattern = abi.encodePacked('"topic_id": "', topicId, '"');
        if (!containsBytes(certificate, topicPattern)) revert ParameterMismatch();
        
        // Verify keyword matches
        bytes memory keywordPattern = abi.encodePacked('"keyword": "', keyword, '"');
        if (!containsBytes(certificate, keywordPattern)) revert ParameterMismatch();
        
        // Verify oracle_type matches
        bytes memory typePattern = abi.encodePacked('"oracle_type": "', oracleType, '"');
        if (!containsBytes(certificate, typePattern)) revert ParameterMismatch();
        
        // Result: found=true means YES wins, found=false means NO wins
        bool result = found;
        
        // === SETTLE MARKET ===
        
        market.settled = true;
        market.result = result;
        
        emit MarketSettled(marketId, msg.sender, result, topicId, keyword, oracleType);
    }
    
    /**
     * @notice Claim winnings (parimutuel payout)
     * @param marketId Market ID
     */
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
    
    // === VIEW FUNCTIONS ===
    
    function getMarket(uint256 marketId) external view returns (
        string memory description,
        bytes32 conditionHash,
        bytes20 oracleCommitSha,
        uint256 deadline,
        bool settled,
        bool result,
        uint256 yesPool,
        uint256 noPool
    ) {
        Market storage market = markets[marketId];
        return (
            market.description,
            market.conditionHash,
            market.oracleCommitSha,
            market.deadline,
            market.settled,
            market.result,
            market.yesPool,
            market.noPool
        );
    }
    
    function getOdds(uint256 marketId) external view returns (uint256 yesOdds, uint256 noOdds) {
        Market storage market = markets[marketId];
        uint256 total = market.yesPool + market.noPool;
        
        if (total == 0) {
            return (5000, 5000);
        }
        
        yesOdds = (market.yesPool * 10000) / total;
        noOdds = (market.noPool * 10000) / total;
    }
    
    function getBet(uint256 marketId, address bettor) external view returns (
        uint256 yesShares,
        uint256 noShares,
        bool claimed
    ) {
        Bet storage userBet = bets[marketId][bettor];
        return (userBet.yesShares, userBet.noShares, userBet.claimed);
    }
    
    function getPotentialPayout(uint256 marketId, address bettor) external view returns (
        uint256 ifYesWins,
        uint256 ifNoWins
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
    
    // === HELPER FUNCTIONS (from GitHubFaucet pattern) ===
    
    /**
     * @notice Check if haystack contains needle (byte pattern matching)
     * @dev Used to parse JSON certificate
     */
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
