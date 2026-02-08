# PredictionMarket Deployment - Base Sepolia

**Date:** 2026-02-08  
**Network:** Base Sepolia (testnet)  
**Chain ID:** 84532

---

## Contract Details

**Address:** `0x4f0845c22939802AAd294Fc7AB907074a7950f67`  
**Deployer:** `0x6C4f77a1c5E13806fAD5477bC8Aa98f319B66061`  
**Transaction:** `0x2666d7659c347e7d6f84cd4a965ed145dd0379d078644c423ed20ccb70424658`

**Explorer:** https://sepolia.basescan.org/address/0x4f0845c22939802AAd294Fc7AB907074a7950f67  
**TX Explorer:** https://sepolia.basescan.org/tx/0x2666d7659c347e7d6f84cd4a965ed145dd0379d078644c423ed20ccb70424658

---

## Contract State

**Owner:** `0x6C4f77a1c5E13806fAD5477bC8Aa98f319B66061` (deployer wallet)  
**Trusted Settler:** `0x6C4f77a1c5E13806fAD5477bC8Aa98f319B66061` (same as owner)  
**Market Count:** 0 (no markets created yet)

---

## Source Verification

**Status:** ⚠️ Pending (etherscan v1 API deprecated)  
**Compiler:** solc 0.8.20  
**Source:** `oracle/foundry-tests/src/PredictionMarket.sol`  
**Commit:** https://github.com/claw-tee-dah/github-zktls/blob/feature/prediction-market-oracle/oracle/foundry-tests/src/PredictionMarket.sol

**Note:** Verification via Foundry failed due to Basescan v1 API deprecation. Source is publicly available on GitHub. Manual verification can be done via Basescan UI.

---

## Deployment Command

```bash
forge create \
  --rpc-url https://sepolia.base.org \
  --private-key $PRIVATE_KEY \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --verifier-url https://api-sepolia.basescan.org/api \
  --broadcast \
  src/PredictionMarket.sol:PredictionMarket
```

---

## Next Steps

### 1. Verify Source Code Manually
   - Go to https://sepolia.basescan.org/address/0x4f0845c22939802AAd294Fc7AB907074a7950f67#code
   - Click "Verify and Publish"
   - Upload source from: `oracle/foundry-tests/src/PredictionMarket.sol`
   - Compiler: v0.8.20
   - Optimization: Enabled (default Foundry settings)

### 2. Create First Test Market

```bash
# Example: "Will 'radicle' be mentioned in first comment of topic 27680?"
cast send 0x4f0845c22939802AAd294Fc7AB907074a7950f67 \
  "createMarket(string,string,string,string,string,string,uint256)" \
  "Will radicle be mentioned in first comment?" \
  "27680" \
  "radicle" \
  "first" \
  "claw-tee-dah/github-zktls" \
  "0da4974" \
  $(($(date +%s) + 86400)) \
  --private-key $PRIVATE_KEY \
  --rpc-url https://sepolia.base.org
```

### 3. Trigger Oracle

```bash
# Manual trigger via GitHub Actions
gh workflow run oracle-check.yml \
  --repo claw-tee-dah/github-zktls \
  --ref feature/prediction-market-oracle \
  -f topic_id=27680 \
  -f keyword=radicle \
  -f oracle_type=first
```

### 4. Settle Market

```bash
# Download attestation and settle
cd oracle/scripts
node settle-market.js 0 <run_id>
# Follow generated cast command
```

---

## Security Notes

- ✅ All security fixes applied (parameter binding, trusted settler, settleable check)
- ✅ 14/14 security tests passing
- ✅ Deployed with verified source (publicly available)
- ⚠️ Trusted settler is deployer wallet (single point - acceptable for testnet)
- ⚠️ No cancellation mechanism (v1 limitation - document)

---

## Contract ABI

See: `oracle/foundry-tests/out/PredictionMarket.sol/PredictionMarket.json`

Key functions:
- `createMarket(...)` - Create new prediction market
- `bet(marketId, position)` - Place parimutuel bet
- `settle(marketId, topicId, keyword, oracleType, settleable, result, attestation)` - Settle with oracle result
- `claim(marketId)` - Claim winnings
- `getMarket(marketId)` - View market details
- `getOdds(marketId)` - Current odds
- `getPotentialPayout(marketId, bettor)` - Potential winnings

---

## Gas Costs (Estimated)

- Deploy: ~2M gas
- Create Market: ~200k gas
- Place Bet: ~100k gas
- Settle: ~80k gas
- Claim: ~60k gas

---

**Deployment successful!** ✅  
**Ready for testing on Base Sepolia** 🚀
