# Security Audit: PredictionMarket Contract

**Auditor:** clawTEEdah  
**Date:** 2026-02-08  
**Scope:** Parameter binding and settlement security

---

## 🚨 CRITICAL ISSUES

### 1. **Missing Oracle Parameters (CRITICAL)**

**Issue:** Contract does NOT store `topicId` and `keyword`

**Current state:**
```solidity
struct Market {
    string description;
    string oracleRepo;
    string oracleCommitSHA;
    uint256 deadline;
    // ❌ Missing: topicId
    // ❌ Missing: keyword
    // ❌ Missing: oracleType (first vs any)
}
```

**Attack scenario:**
```javascript
// 1. Create market
createMarket(
  "Will 'radicle' be mentioned in topic 12345?",
  "claw-tee-dah/github-zktls",
  "abc123",
  deadline
);

// 2. Attacker triggers oracle with DIFFERENT parameters
// Oracle checks: topic 99999, keyword "bitcoin"
// Result: FOUND (bitcoin mentioned in topic 99999)

// 3. Attacker settles market with this result
settle(marketId, true, attestation);
// ✅ Contract accepts it! No verification!

// 4. Market settles as YES wins
// But original condition was about "radicle" in topic 12345
// Bettors lose money incorrectly
```

**Impact:** **GAME OVER** - Contract is completely insecure without parameter binding.

**Fix required:** Store oracle parameters as commitment hash:
```solidity
struct Market {
    // ... existing fields
    bytes32 conditionHash;  // keccak256(topicId, keyword, oracleType)
}

function settle(
    uint256 marketId,
    bool result,
    string memory topicId,
    string memory keyword,
    string memory oracleType,
    bytes memory attestation
) external {
    Market storage market = markets[marketId];
    
    // MUST verify parameters match
    bytes32 hash = keccak256(abi.encode(topicId, keyword, oracleType));
    require(hash == market.conditionHash, "Parameters mismatch");
    
    // Then verify attestation contains these parameters
    // ...
}
```

---

### 2. **No Attestation Verification (CRITICAL)**

**Issue:** `settle()` ignores `proofData` parameter

**Current code:**
```solidity
function settle(
    uint256 marketId,
    bool result,
    bytes memory proofData  // ❌ IGNORED!
) external {
    // TODO: Verify Sigstore attestation on-chain
    // For now: trust the first settler (assumes honest GitHub workflow)
    
    market.settled = true;
    market.result = result;  // ❌ Accepts any result!
}
```

**Attack:** Anyone can call `settle()` with any result after deadline.

**Impact:** Attacker can steal all funds by settling with false result.

**Fix required:** Either:
1. Verify Sigstore attestation on-chain (expensive)
2. Use optimistic settlement with challenge period
3. Require multisig or DAO approval
4. Use oracle network (Chainlink, UMA)

**Temporary mitigation:** Use a trusted settler address:
```solidity
address public trustedSettler;

function settle(...) external {
    require(msg.sender == trustedSettler, "Not authorized");
    // ...
}
```

---

### 3. **Missing Settleable Check (HIGH)**

**Issue:** Contract accepts settlement even if oracle returns `NO_COMMENTS`

**Current:** No verification that first comment exists

**Attack scenario:**
```javascript
// 1. Create market for topic with no comments yet
// 2. Immediately settle with result=false (NOT_FOUND)
// 3. First comment appears later with keyword
// 4. Too late - market already settled wrong
```

**Fix required:**
```solidity
function settle(
    uint256 marketId,
    bool result,
    bool settleable,  // From oracle
    bytes memory attestation
) external {
    require(settleable == true, "Cannot settle: first comment missing");
    // ...
}
```

---

## ⚠️ HIGH SEVERITY ISSUES

### 4. **Division by Zero in Edge Case**

**Issue:** If no one bet on winning side, `claim()` divides by zero

**Code:**
```solidity
uint256 totalWinningShares = market.result ? market.totalYesShares : market.totalNoShares;
uint256 payout = (winningShares * totalPot) / totalWinningShares;  // ❌ If totalWinningShares == 0
```

**Scenario:** 
- Alice bets YES
- Bob bets YES
- Market settles as NO wins
- No one has NO shares
- Division by zero → revert

**Impact:** Funds locked forever (no one can claim, no refund mechanism)

**Fix:**
```solidity
if (totalWinningShares == 0) {
    // No winners - refund everyone proportionally
    // Or: send to charity/burn
    revert NoWinners();
}
```

---

### 5. **Oracle Type Not Bound**

**Issue:** Contract doesn't specify which oracle variant (first vs any comment)

**Current:** Market description says "first comment" but contract doesn't enforce it

**Attack:** Settler could use "any comment" oracle when market expected "first comment"

**Fix:** Store oracle type:
```solidity
enum OracleType { FIRST_COMMENT, ANY_COMMENT }

struct Market {
    OracleType oracleType;
    // ...
}
```

---

### 6. **No Deadline Verification in Attestation**

**Issue:** Attestation timestamp not checked against market deadline

**Attack scenario:**
- Market deadline: Feb 8, 12:00
- Attacker waits until Feb 9
- Triggers oracle, gets result with Feb 9 timestamp
- Settles market with late result
- First comment could have appeared after deadline

**Fix:** Verify attestation timestamp ≤ deadline

---

## MEDIUM SEVERITY ISSUES

### 7. **String Parameters (Gas Inefficiency)**

**Issue:** Storing full strings for repo, SHA, description

**Better:** Store hashes and emit events with full data
```solidity
struct Market {
    bytes32 descriptionHash;
    bytes32 repoHash;
    bytes32 commitSHAHash;
}
```

### 8. **No Refund Mechanism**

**Issue:** If oracle fails or market is invalid, no way to refund bettors

**Fix:** Add emergency refund function (owner/DAO controlled)

### 9. **No Market Cancellation**

**Issue:** If oracle repo goes down, funds locked forever

**Fix:** Allow cancellation before first bet, or after timeout

---

## LOW SEVERITY ISSUES

### 10. **Reentrancy Protection**

**Status:** ✅ Actually OK - uses checks-effects-interactions pattern correctly
```solidity
userBet.claimed = true;  // State update first
(bool success, ) = msg.sender.call{value: payout}("");  // External call last
```

### 11. **No Event Emission in Failure Cases**

**Issue:** If settlement fails, no event to track why

**Fix:** Add events for validation failures

---

## RECOMMENDED FIXES (Priority Order)

### MUST FIX (Deploy blocker):

1. **Add condition hash binding:**
```solidity
struct Market {
    bytes32 conditionHash;  // keccak256(topicId, keyword, oracleType)
}

function createMarket(
    string memory description,
    string memory topicId,
    string memory keyword,
    string memory oracleType,
    string memory oracleRepo,
    string memory oracleCommitSHA,
    uint256 deadline
) external returns (uint256) {
    bytes32 conditionHash = keccak256(abi.encode(topicId, keyword, oracleType));
    
    markets[marketId] = Market({
        description: description,
        conditionHash: conditionHash,
        oracleRepo: oracleRepo,
        oracleCommitSHA: oracleCommitSHA,
        deadline: deadline,
        // ...
    });
}
```

2. **Verify parameters in settlement:**
```solidity
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
    
    // Verify parameters match market
    bytes32 hash = keccak256(abi.encode(topicId, keyword, oracleType));
    require(hash == market.conditionHash, "Parameters mismatch");
    
    // Verify settleable
    require(settleable == true, "Cannot settle yet");
    
    // Verify attestation (future)
    // verifyAttestation(attestation, market.oracleRepo, market.oracleCommitSHA);
    
    market.settled = true;
    market.result = result;
}
```

3. **Add trusted settler (temporary):**
```solidity
address public trustedSettler;

modifier onlyTrustedSettler() {
    require(msg.sender == trustedSettler, "Not authorized");
    _;
}

function settle(...) external onlyTrustedSettler {
    // ...
}
```

4. **Handle division by zero:**
```solidity
if (totalWinningShares == 0) {
    revert NoWinners();
}
```

### SHOULD FIX (Pre-mainnet):

5. Add attestation verification (Sigstore or optimistic)
6. Add refund mechanism
7. Add market cancellation
8. Verify attestation timestamp

---

## SUMMARY

**Current state:** ❌ **NOT SAFE TO DEPLOY**

**Critical issues:** 3
- Missing parameter binding
- No attestation verification
- No settleable check

**High issues:** 3
- Division by zero edge case
- Oracle type not bound
- Deadline verification missing

**Fix ETA:** ~2-3 hours for critical fixes + testing

**Recommendation:** DO NOT deploy to testnet until parameter binding is fixed.

---

**Next steps:**
1. Fix condition hash binding (CRITICAL)
2. Add parameter verification to settle() (CRITICAL)
3. Add trusted settler address (CRITICAL)
4. Test all edge cases
5. Re-audit
6. Deploy to testnet
