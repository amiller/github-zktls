// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PredictionMarket
 * @notice Parimutuel prediction market with GitHub Actions oracle
 * 
 * Parimutuel mechanics:
 * - All bets go into YES or NO pool
 * - You buy in at current pool ratio (if 50/50, you get .5/.5 effective odds)
 * - Payout = (your share of winning pool) × (total pot)
 * - Can bet anytime before deadline
 * 
 * Trust model (same as github-zktls):
 * - Oracle code is public and auditable
 * - Sigstore attestation proves execution from exact commit SHA
 * - Anyone can verify attestation independently
 */

contract PredictionMarket {
    struct Market {
        string description;
        string oracleRepo;      // e.g., "claw-tee-dah/github-zktls"
        string oracleCommitSHA; // Exact commit SHA oracle must run from
        uint256 deadline;       // Timestamp when betting closes
        bool settled;
        bool result;            // true = YES wins, false = NO wins
        uint256 yesPool;
        uint256 noPool;
        uint256 totalYesShares; // Track shares for proportional payout
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
    
    event MarketCreated(uint256 indexed marketId, string description, uint256 deadline);
    event BetPlaced(uint256 indexed marketId, address indexed bettor, bool position, uint256 amount, uint256 shares);
    event MarketSettled(uint256 indexed marketId, bool result);
    event WinningsClaimed(uint256 indexed marketId, address indexed winner, uint256 amount);
    
    error BettingClosed();
    error MarketAlreadySettled();
    error BettingStillOpen();
    error NoWinningBet();
    error AlreadyClaimed();
    error TransferFailed();
    error InvalidDeadline();
    error ZeroBet();
    
    /**
     * @notice Create a new prediction market
     */
    function createMarket(
        string memory description,
        string memory oracleRepo,
        string memory oracleCommitSHA,
        uint256 deadline
    ) external returns (uint256) {
        if (deadline <= block.timestamp) revert InvalidDeadline();
        
        uint256 marketId = marketCount++;
        markets[marketId] = Market({
            description: description,
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
        
        emit MarketCreated(marketId, description, deadline);
        return marketId;
    }
    
    /**
     * @notice Bet on a market (parimutuel style)
     * @param marketId ID of the market
     * @param position true for YES, false for NO
     * 
     * Parimutuel: Your shares = amount you bet
     * Payout = (your shares / total winning shares) × (total pot)
     */
    function bet(uint256 marketId, bool position) external payable {
        Market storage market = markets[marketId];
        if (block.timestamp >= market.deadline) revert BettingClosed();
        if (market.settled) revert MarketAlreadySettled();
        if (msg.value == 0) revert ZeroBet();
        
        Bet storage userBet = bets[marketId][msg.sender];
        
        // In parimutuel, shares = amount bet (1:1)
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
     * @notice Settle a market with oracle result
     * @param marketId ID of the market
     * @param result The oracle result (true = YES wins, false = NO wins)
     * @param proofData Attestation proof (future: verify Sigstore on-chain)
     * 
     * Note: In MVP, anyone can settle after deadline (trust GitHub attestation)
     * Production: verify Sigstore signature on-chain
     */
    function settle(
        uint256 marketId,
        bool result,
        bytes memory proofData
    ) external {
        Market storage market = markets[marketId];
        if (block.timestamp < market.deadline) revert BettingStillOpen();
        if (market.settled) revert MarketAlreadySettled();
        
        // TODO: Verify Sigstore attestation on-chain
        // For now: trust the first settler (assumes honest GitHub workflow)
        
        market.settled = true;
        market.result = result;
        
        emit MarketSettled(marketId, result);
    }
    
    /**
     * @notice Claim winnings (parimutuel payout)
     * @param marketId ID of the market
     * 
     * Payout formula:
     * payout = (your winning shares / total winning shares) × (total pot)
     */
    function claim(uint256 marketId) external {
        Market storage market = markets[marketId];
        if (!market.settled) revert MarketAlreadySettled();
        
        Bet storage userBet = bets[marketId][msg.sender];
        if (userBet.claimed) revert AlreadyClaimed();
        
        uint256 winningShares = market.result ? userBet.yesShares : userBet.noShares;
        if (winningShares == 0) revert NoWinningBet();
        
        userBet.claimed = true;
        
        // Parimutuel payout calculation
        uint256 totalPot = market.yesPool + market.noPool;
        uint256 totalWinningShares = market.result ? market.totalYesShares : market.totalNoShares;
        
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
     * @notice Get current odds (implied probability from pool sizes)
     * @return yesOdds Implied YES probability (basis points, 10000 = 100%)
     * @return noOdds Implied NO probability (basis points)
     */
    function getOdds(uint256 marketId) external view returns (uint256 yesOdds, uint256 noOdds) {
        Market storage market = markets[marketId];
        uint256 total = market.yesPool + market.noPool;
        
        if (total == 0) {
            return (5000, 5000); // 50/50 if no bets yet
        }
        
        yesOdds = (market.yesPool * 10000) / total;
        noOdds = (market.noPool * 10000) / total;
    }
    
    /**
     * @notice Get your bet details
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
     * @notice Calculate potential payout for a bettor
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
