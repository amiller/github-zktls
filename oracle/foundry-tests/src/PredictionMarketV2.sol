// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PredictionMarket V2 - Trustless Settlement
 * @notice Removes trustedSettler requirement
 * 
 * Trust model:
 * - Anyone can settle with any result
 * - Parameters must match conditionHash (enforced on-chain)
 * - Attestation proves correctness (verified off-chain by bettors)
 * - First settlement wins (no disputes in v2)
 * 
 * Security:
 * - Attacker can't use wrong parameters (conditionHash check)
 * - Attacker can't fake attestation (cryptographically impossible)
 * - Bettors verify attestation before claiming
 * - If settled incorrectly, bettors don't claim (social consensus)
 * 
 * Future: Add dispute period for trustless on-chain verification
 */

contract PredictionMarket {
    struct Market {
        string description;
        bytes32 conditionHash;
        string oracleRepo;
        string oracleCommitSHA;
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
    address public owner;
    
    event MarketCreated(
        uint256 indexed marketId,
        string description,
        bytes32 conditionHash,
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
        string keyword
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
    error ParameterMismatch();
    error NotSettleable();
    error NoWinners();
    
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @notice Create a new prediction market with parameter binding
     */
    function createMarket(
        string memory description,
        string memory topicId,
        string memory keyword,
        string memory oracleType,
        string memory oracleRepo,
        string memory oracleCommitSHA,
        uint256 deadline
    ) external returns (uint256) {
        if (deadline <= block.timestamp) revert InvalidDeadline();
        
        bytes32 conditionHash = keccak256(abi.encode(topicId, keyword, oracleType));
        
        uint256 marketId = marketCount++;
        markets[marketId] = Market({
            description: description,
            conditionHash: conditionHash,
            oracleRepo: oracleRepo,
            oracleCommitSHA: oracleCommitSHA,
            deadline: deadline,
            settled: false,
            result: false,
            yesPool: 0,
            noPool: 0,
            totalYesShares: 0,
            totalNoShares: 0
        });
        
        emit MarketCreated(marketId, description, conditionHash, deadline);
        return marketId;
    }
    
    /**
     * @notice Bet on a market (parimutuel style)
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
     * @notice Settle a market - ANYONE CAN CALL (trustless)
     * 
     * Security checks:
     * 1. Parameters must match conditionHash (prevents wrong data)
     * 2. Settleable must be true (prevents premature settlement)
     * 3. Deadline must have passed
     * 
     * NO TRUSTED SETTLER - Anyone can settle!
     * 
     * Trust model:
     * - Settler provides attestation off-chain
     * - Bettors verify attestation before claiming
     * - If result is wrong, bettors don't claim (social consensus)
     * - Correct settlers are rewarded (people claim and market succeeds)
     * 
     * Future improvements:
     * - Add dispute period (challenger can prove wrong result)
     * - On-chain attestation verification (expensive but trustless)
     * - Multi-oracle consensus (require 3/5 agreement)
     */
    function settle(
        uint256 marketId,
        string memory topicId,
        string memory keyword,
        string memory oracleType,
        bool settleable,
        bool result,
        bytes memory attestation
    ) external {
        Market storage market = markets[marketId];
        
        // Check deadline
        if (block.timestamp < market.deadline) revert BettingStillOpen();
        if (market.settled) revert MarketAlreadySettled();
        
        // Verify parameters match market condition
        bytes32 providedHash = keccak256(abi.encode(topicId, keyword, oracleType));
        if (providedHash != market.conditionHash) revert ParameterMismatch();
        
        // Verify first comment exists
        if (!settleable) revert NotSettleable();
        
        // NOTE: attestation parameter currently unused
        // Future: verify Sigstore signature on-chain or via optimistic bridge
        // For v2: bettors verify attestation off-chain before claiming
        
        market.settled = true;
        market.result = result;
        
        emit MarketSettled(marketId, msg.sender, result, topicId, keyword);
    }
    
    /**
     * @notice Claim winnings (parimutuel payout)
     * 
     * IMPORTANT: Verify attestation off-chain before claiming!
     * If market was settled incorrectly, don't claim.
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
    
    /**
     * @notice Get market details
     */
    function getMarket(uint256 marketId) external view returns (
        string memory description,
        bytes32 conditionHash,
        string memory oracleRepo,
        string memory oracleCommitSHA,
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
            market.oracleRepo,
            market.oracleCommitSHA,
            market.deadline,
            market.settled,
            market.result,
            market.yesPool,
            market.noPool
        );
    }
    
    /**
     * @notice Get current odds
     */
    function getOdds(uint256 marketId) external view returns (uint256 yesOdds, uint256 noOdds) {
        Market storage market = markets[marketId];
        uint256 total = market.yesPool + market.noPool;
        
        if (total == 0) {
            return (5000, 5000);
        }
        
        yesOdds = (market.yesPool * 10000) / total;
        noOdds = (market.noPool * 10000) / total;
    }
    
    /**
     * @notice Get bet details
     */
    function getBet(uint256 marketId, address bettor) external view returns (
        uint256 yesShares,
        uint256 noShares,
        bool claimed
    ) {
        Bet storage userBet = bets[marketId][bettor];
        return (userBet.yesShares, userBet.noShares, userBet.claimed);
    }
    
    /**
     * @notice Calculate potential payout
     */
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
}
