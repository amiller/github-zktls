# Gaps & Issues Found in Fresh Review

## 🔴 CRITICAL GAP: Workflow → Contract Integration

**Issue:** Workflow attestation doesn't include oracle parameters needed for settlement.

**Problem:**
```javascript
// Contract settle() requires:
settle(
    marketId,
    topicId,      // ❌ Where does settler get this?
    keyword,      // ❌ Where does settler get this?
    oracleType,   // ❌ Where does settler get this?
    settleable,
    result,
    attestation
);
```

**Current workflow metadata:**
```json
{
  "workflow": "...",
  "run_id": "...",
  "commit_sha": "...",
  "result_found": true
  // ❌ Missing: topicId, keyword, oracleType
}
```

**Impact:** Settler downloads attestation but doesn't know which topicId/keyword/oracleType to pass to contract!

**Fix Required:**
Add to metadata.json:
```json
{
  "topic_id": "$TOPIC_ID",
  "keyword": "$KEYWORD",  
  "oracle_type": "$ORACLE_TYPE",
  "settleable": "$SETTLEABLE",
  "result_found": "$FOUND"
}
```

---

## 🟡 MEDIUM: Oracle Result doesn't include oracleType

**Issue:** oracle-result.json doesn't specify which oracle type was used.

**Current:**
```json
{
  "result": "FOUND",
  "found": true,
  "settleable": true,
  "topic_id": "12345",
  "keyword": "radicle"
  // ❌ Missing: "oracle_type": "first"
}
```

**Impact:** If someone downloads oracle-result.json, they don't know if it was "first" or "any" check.

**Fix:** Add `oracle_type` field to oracle output.

---

## 🟡 MEDIUM: No clear settlement script

**Issue:** No example script showing how to:
1. Download workflow artifacts
2. Extract parameters from attestation
3. Call contract.settle() with correct parameters

**Fix:** Create `scripts/settle-market.js`

---

## 🟢 MINOR: Workflow runs on push to main

**Issue:**
```yaml
on:
  workflow_dispatch: ...
  push:
    branches: [ main ]  # ❌ Unnecessary - oracle should be manual only
```

**Impact:** Every push to main triggers oracle check (wasteful).

**Fix:** Remove push trigger (only keep workflow_dispatch).

---

## 🟢 MINOR: Oracle exits early on NO_COMMENTS

**Issue:** When NO_COMMENTS, workflow exits before attestation step.

**Current behavior:**
```bash
if settleable != true:
    exit 0  # ❌ No attestation created
```

**Question:** Is this correct? Or should we attest NO_COMMENTS as well?

**Reasoning:**
- ✅ Pro skip: Don't waste attestations on non-settleable states
- ❌ Con skip: Can't prove oracle was run (no timestamp proof)

**Recommendation:** Keep current behavior (skip attestation for NO_COMMENTS).

---

## 🟢 MINOR: contracts/ directory has old version

**Issue:** Two copies of PredictionMarket.sol:
- `oracle/contracts/PredictionMarket.sol` (old, pre-security fixes)
- `oracle/foundry-tests/src/PredictionMarket.sol` (new, secure)

**Fix:** Update or remove `oracle/contracts/PredictionMarket.sol`

---

## 🟢 DOCUMENTATION: Missing deployment guide

**Issue:** No step-by-step guide for:
1. Deploying contract to Base Sepolia
2. Creating first market
3. Running oracle when ready
4. Settling market with attestation

**Fix:** Create `DEPLOYMENT.md`

---

## 🟢 DOCUMENTATION: USAGE.md references old contract interface

**Issue:** USAGE.md shows:
```javascript
contract.createMarket(
  "description",
  "repo",
  "sha",
  deadline
);
```

But new interface requires:
```javascript
contract.createMarket(
  "description",
  "topicId",     // NEW
  "keyword",     // NEW
  "oracleType",  // NEW
  "repo",
  "sha",
  deadline
);
```

**Fix:** Update USAGE.md with correct interface.

---

## Summary

**Critical (deploy blocker):** 1
- Workflow metadata missing oracle parameters

**Medium:** 2
- Oracle output missing oracle_type field
- No settlement script/example

**Minor:** 4
- Push trigger should be removed
- Old contract file needs update
- Documentation updates needed

**Recommendation:**
Fix CRITICAL issue before considering deployment. Medium issues should be fixed for good UX.
