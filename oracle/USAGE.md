# Usage Guide: Prediction Market Oracle

## Overview

This system lets you create **verifiable prediction markets** based on real-world events (forum comments, in this case).

**Key innovation:** The oracle result is cryptographically proven using GitHub Actions + Sigstore attestations.

## How It Works

```
1. Someone posts on Ethereum Magicians forum
2. You want to bet: "Will the first comment mention 'radicle'?"
3. Create a prediction market with this condition
4. GitHub workflow checks the forum every 15 minutes
5. When first comment appears, oracle produces attested result
6. Anyone can verify the attestation independently
7. Contract settles based on verified result
8. Winners claim their share of the pot
```

## Step-by-Step: Create a Market

### 1. Deploy the Contract

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Compile contract
forge build

# Deploy to Base Sepolia
forge create --rpc-url https://sepolia.base.org \
  --private-key $PRIVATE_KEY \
  contracts/PredictionMarket.sol:PredictionMarket
```

### 2. Create a Market

```javascript
// Using ethers.js
const market = await contract.createMarket(
  "First comment on github-zktls post will mention 'radicle'",
  "your-username/prediction-market-oracle", // Your fork
  "abcdef1234567890",  // Current commit SHA
  Math.floor(Date.now() / 1000) + 86400  // Deadline: 24 hours
);
```

### 3. Configure the Oracle

Set repository variables in GitHub:
- `DEFAULT_TOPIC_ID` = Ethereum Magicians topic ID
- `DEFAULT_KEYWORD` = "radicle"

The workflow will check every 15 minutes automatically.

### 4. Place Bets

```javascript
// Bet YES (radicle will be mentioned)
await contract.bet(marketId, true, { value: ethers.parseEther("0.01") });

// Bet NO (radicle won't be mentioned)
await contract.bet(marketId, false, { value: ethers.parseEther("0.01") });
```

### 5. Wait for Settlement

The workflow checks periodically. When the first comment appears:
1. Oracle detects it
2. Produces `oracle-result.json`
3. Creates Sigstore attestation
4. Result is available in GitHub Actions artifacts

### 6. Verify and Settle

```bash
# Anyone can verify the attestation
./verify-attestation.sh your-username/prediction-market-oracle 12345

# Settle the market with the verified result
# (This could be automated with a script that reads the attestation)
await contract.settle(marketId, oracleResult, proofData);
```

### 7. Claim Winnings

```javascript
// If you bet on the winning side
await contract.claim(marketId);
```

## Trust Model

**What you trust:**
- ✅ GitHub Actions executes the code faithfully
- ✅ Sigstore attestation system is honest
- ✅ The oracle code logic is correct (it's public, audit it!)

**What you DON'T need to trust:**
- ❌ A centralized oracle operator
- ❌ The person who settles the market
- ❌ That the code wasn't tampered with (attestation proves exact commit)

## Example: "Radicle" Bet

```javascript
// Alice thinks "radicle" will be mentioned
await contract.bet(marketId, true, { value: parseEther("0.05") });

// Bob thinks it won't
await contract.bet(marketId, false, { value: parseEther("0.03") });

// Total pot: 0.08 ETH
// First comment appears: "I think radicle is a great project"
// Oracle detects "radicle" → result = TRUE
// Market settles: YES wins
// Alice claims: (0.05 / 0.05) * 0.08 = 0.08 ETH (100% of pot, she was the only YES better)
```

## Verification

Anyone can independently verify the oracle result:

```bash
# 1. Get the workflow run ID from GitHub
# 2. Download the artifacts
gh run download 12345 --name oracle-result-123

# 3. Verify attestation
gh attestation verify oracle-result.json --repo your-username/prediction-market-oracle

# 4. Check the result yourself
cat oracle-result.json | jq .found
# true or false
```

## Advanced: Custom Conditions

You can fork this and create markets for any condition:

- "Will ETH price be above $3000 on Friday?" (check oracle API)
- "Will this GitHub PR be merged by deadline?" (check GitHub API)
- "Will this tweet get 1000+ likes?" (check Twitter API)

The pattern is always:
1. Publicly auditable code
2. Deterministic oracle logic
3. Sigstore attestation proves execution
4. Anyone can verify independently

## Security Considerations

**Current MVP limitations:**
- ⚠️ Contract doesn't verify Sigstore signatures on-chain (gas cost)
- ⚠️ Honest majority assumption for settlement (first settler trusted)
- ⚠️ No dispute mechanism if oracle malfunctions

**Production improvements:**
- Verify Sigstore attestation on-chain (or via optimistic bridge)
- Multi-oracle consensus (require 3/5 agreement)
- Timelocked dispute period
- Slashing for incorrect oracle results

## Resources

- **Sigstore docs**: https://www.sigstore.dev/
- **GitHub Attestations**: https://docs.github.com/en/actions/security-guides/using-artifact-attestations
- **Discourse API**: https://docs.discourse.org/

---

**Ready to bet?** 🎲
