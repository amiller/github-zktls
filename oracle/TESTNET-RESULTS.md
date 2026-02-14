# PredictionMarket V3 - Testnet Deployment Results

## ✅ Deployment Success

**Network:** Base Sepolia  
**Contract:** `0x2bE419BCB663136b16cF2D163E309ECaf6B9887b`  
**Verifier:** `0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725`  
**Deployer:** `0x6C4f77a1c5E13806fAD5477bC8Aa98f319B66061`  
**Deploy TX:** `0x7f1f3d73bdeb177fdd5fed44bc372c726376a57a5e3ff70c2f767be9521a1983`

**Basescan:** https://sepolia.basescan.org/address/0x2bE419BCB663136b16cF2D163E309ECaf6B9887b

## ✅ Market Created

**Market ID:** 0  
**Description:** "Will 'security' appear in the first comment of topic 27685?"  
**Topic:** 27685 (New ERC: Facet-Based Diamonds)  
**Keyword:** "security"  
**Oracle Type:** "first"  
**Deadline:** ~1 hour from creation  

**Create TX:** `0x5b9e441959d651d815c6a751736aba42f41bfd0098d56222fd48186dc647a921`

## ✅ Bet Placed

**Amount:** 0.0001 ETH  
**Position:** YES  
**Bet TX:** `0xd12affd628a838a60ae01486adcbb6f2c6734d99271135ed6b7d5a6eedb6c7f0`

**Current Pool:**
- YES: 0.0001 ETH
- NO: 0 ETH

## ✅ Oracle Verification

**Topic checked:** 27685  
**First comment by:** radek  
**Posted:** 2026-02-08T13:48:19.976Z  
**Keyword found:** ✅ YES ("security" appears in comment)

**Oracle Result:**
```json
{
  "result": "FOUND",
  "found": true,
  "settleable": true,
  "topic_id": "27685",
  "keyword": "security",
  "oracle_type": "first"
}
```

## Next Steps for Full Settlement

To complete trustless settlement, we need:

### 1. GitHub Actions Workflow
Trigger workflow that:
- Runs `check-forum.js` with topic 27685, keyword "security"
- Generates `oracle-result.json`
- GitHub Actions creates Sigstore attestation via `actions/attest-build-provenance@v2`

### 2. Generate ZK Proof
```bash
# Download attestation bundle
gh run download <run-id> -n oracle-result-<run-number>

# Generate proof using Barretenberg
bb prove -b <circuit> -w <witness> -o proof
```

### 3. Settle Market
```javascript
await contract.settle(
  0,                    // marketId
  proof,                // ZK proof bytes
  publicInputs,         // 84 field elements
  oracleResultJSON,     // oracle-result.json as bytes
  "27685",              // topicId
  "security",           // keyword
  "first"               // oracleType
);
```

Contract will:
- ✅ Verify proof using ISigstoreVerifier
- ✅ Check certificate hash matches attestation
- ✅ Verify parameters match conditionHash
- ✅ Parse certificate JSON
- ✅ Settle as YES (keyword found)

### 4. Claim Winnings
```javascript
await contract.claim(0);
// Payout: 0.0001 ETH (100% of pool since only YES bet)
```

## What We Demonstrated

✅ **Contract deployment** - PredictionMarket V3 deployed with ISigstoreVerifier integration  
✅ **Market creation** - Created market bound to specific oracle parameters  
✅ **Betting** - Placed parimutuel bet on outcome  
✅ **Oracle execution** - Verified keyword exists in topic's first comment  
✅ **Trustless design** - No trustedSettler, anyone can settle with valid proof

## Architecture Highlights

- **Follows GitHubFaucet pattern exactly**
- **No repoHash** (commitSha is globally unique)
- **Parameter binding** (conditionHash prevents wrong oracle data)
- **Certificate verification** (sha256(oracle-result.json) must match attestation)
- **Permissionless settlement** (anyone with valid proof can settle)

## Files

- `deployment-v3.json` - Deployment info + ABI
- `market-info.json` - Market details
- `oracle-result.json` - Oracle output
- Contract source: `foundry-tests/src/PredictionMarketV3.sol`

---

**Status:** Deployed and tested (oracle verified). Awaiting proof generation infrastructure for full trustless settlement.
