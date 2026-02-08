# Foundry Tests for PredictionMarket

## Setup

```bash
# Install forge-std
forge install foundry-rs/forge-std

# Build
forge build

# Test
forge test -vv

# Test with Anvil (local testnet)
cd .. && ./test-anvil.sh
```

## Files

- `PredictionMarket.sol` - Main contract (parimutuel betting)
- `PredictionMarket.t.sol` - 13 comprehensive tests
- `Deploy.s.sol` - Deployment script
- `foundry.toml` - Foundry configuration

## Test Results

All 13 tests passing:
- ✅ Create market
- ✅ Bet YES/NO
- ✅ Parimutuel odds
- ✅ Proportional payouts
- ✅ Multiple bettors
- ✅ Hedging (both sides)
- ✅ Deadline enforcement
- ✅ Settlement
- ✅ Claim prevention (losers, double-claim)
- ✅ Potential payout calculation

## Anvil Integration Test

End-to-end test on local testnet:
- Deploy contract
- Create market
- Place bets (3 ETH YES, 1 ETH NO)
- Check odds (75%/25%)
- Settle market
- Claim winnings (4 ETH to winner)

All passing! ✅
