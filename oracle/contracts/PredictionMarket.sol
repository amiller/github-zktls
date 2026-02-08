// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PredictionMarket
 * @notice Simple prediction market settlement based on GitHub Actions oracle
 * 
 * Trust Model:
 * - Bettors trust that the oracle code is correct (public, auditable)
 * - Sigstore attestation proves which commit SHA produced the result
 * - Anyone can verify the attestation independently
 * 
 * Flow:
 * 1. Users bet YES or NO on a condition
 * 2. Oracle (GitHub workflow) checks the condition
 * 3. Oracle result is attested via Sigstore
 * 4. Anyone submits the attested result to settle
 * 5. Winners claim their share of the pot
 */

contract PredictionMarket {
    struct Market {
        string description;
        string oracleRepo;      // e.g., "username/prediction-market-oracle"
        string oracleCommitSHA; // Commit SHA that oracle must run from
        uint256 deadline;       // Timestamp when betting closes
        bool settled;
        bool result;            // true = YES wins, false = NO wins
        uint256 yesPool;
        uint256 noPool;
    }
    
    struct Bet {
        uint256 amount;
        bool position;  // true = YES, false = NO
        bool claimed;
    }
    
    mapping(uint256 => Market) public markets;
    mapping(uint256 => mapping(address => Bet)) public bets;
    uint256 public marketCount;
    
    event MarketCreated(uint256 indexed marketId, string description);
    event BetPlaced(uint256 indexed marketId, address indexed bettor, bool position, uint256 amount);
    event MarketSettled(uint256 indexed marketId, bool result);
    event WinningsClaimed(uint256 indexed marketId, address indexed winner, uint256 amount);
    
    /**
     * @notice Create a new prediction market
     * @param description Human-readable description of the bet
     * @param oracleRepo GitHub repository running the oracle (e.g., "user/repo")
     * @param oracleCommitSHA Exact commit SHA the oracle must run from
     * @param deadline Timestamp when betting closes
     */
    function createMarket(
        string memory description,
        string memory oracleRepo,
        string memory oracleCommitSHA,
        uint256 deadline
    ) external returns (uint256) {
        require(deadline > block.timestamp, "Deadline must be in future");
        
        uint256 marketId = marketCount++;
        markets[marketId] = Market({
            description: description,
            oracleRepo: oracleRepo,
            oracleCommitSHA: oracleCommitSHA,
            deadline: deadline,
            settled: false,
            result: false,
            yesPool: 0,
            noPool: 0
        });
        
        emit MarketCreated(marketId, description);
        return marketId;
    }
    
    /**
     * @notice Place a bet on a market
     * @param marketId ID of the market
     * @param position true for YES, false for NO
     */
    function bet(uint256 marketId, bool position) external payable {
        Market storage market = markets[marketId];
        require(block.timestamp < market.deadline, "Betting closed");
        require(!market.settled, "Market already settled");
        require(msg.value > 0, "Must bet something");
        
        Bet storage userBet = bets[marketId][msg.sender];
        require(userBet.amount == 0, "Already bet on this market");
        
        userBet.amount = msg.value;
        userBet.position = position;
        
        if (position) {
            market.yesPool += msg.value;
        } else {
            market.noPool += msg.value;
        }
        
        emit BetPlaced(marketId, msg.sender, position, msg.value);
    }
    
    /**
     * @notice Settle a market with oracle result
     * @param marketId ID of the market
     * @param result The oracle result (true = condition met, false = not met)
     * @param proofData Attestation proof (for now, simplified - could verify Sigstore sig)
     * 
     * NOTE: In production, this would verify the Sigstore attestation on-chain
     * For MVP, we trust the first settler after deadline (can be improved)
     */
    function settle(
        uint256 marketId,
        bool result,
        bytes memory proofData
    ) external {
        Market storage market = markets[marketId];
        require(block.timestamp >= market.deadline, "Betting still open");
        require(!market.settled, "Already settled");
        
        // TODO: Verify Sigstore attestation here
        // For MVP: anyone can settle after deadline (honest majority assumption)
        // Production: verify cryptographic proof that result came from correct commit
        
        market.settled = true;
        market.result = result;
        
        emit MarketSettled(marketId, result);
    }
    
    /**
     * @notice Claim winnings if you bet on the winning side
     * @param marketId ID of the market
     */
    function claim(uint256 marketId) external {
        Market storage market = markets[marketId];
        require(market.settled, "Market not settled");
        
        Bet storage userBet = bets[marketId][msg.sender];
        require(userBet.amount > 0, "No bet placed");
        require(!userBet.claimed, "Already claimed");
        require(userBet.position == market.result, "You lost");
        
        userBet.claimed = true;
        
        // Calculate winnings: your share of total pot
        uint256 totalPot = market.yesPool + market.noPool;
        uint256 winningPool = market.result ? market.yesPool : market.noPool;
        
        uint256 payout = (userBet.amount * totalPot) / winningPool;
        
        emit WinningsClaimed(marketId, msg.sender, payout);
        
        (bool success, ) = msg.sender.call{value: payout}("");
        require(success, "Transfer failed");
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
     * @notice Get your bet details
     */
    function getBet(uint256 marketId, address bettor) external view returns (
        uint256 amount,
        bool position,
        bool claimed
    ) {
        Bet storage userBet = bets[marketId][bettor];
        return (userBet.amount, userBet.position, userBet.claimed);
    }
}
