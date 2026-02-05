# Security Audit: GitHubFaucet

**Status:** Fixed
**Circuit changes required:** None

---

## Issues Found and Fixed

### 1. setRequirements Had No Access Control
**Severity:** CRITICAL → **FIXED**

Added `onlyOwner` modifier. Only deployer can change commit requirements.

### 2. Recipient Not Validated Against Certificate
**Severity:** HIGH → **FIXED**

Added `containsBytes` check for `recipient_address` pattern. Front-running no longer possible.

### 3. Case-Sensitive Cooldown Bypass
**Severity:** MEDIUM → **FIXED**

Added `toLower()` normalization before hashing username.

### 4. Username Injection via containsBytes
**Severity:** MEDIUM → **MITIGATED**

With commit pinning and access control, attacker cannot use modified workflow from their fork.

---

## Deployment

```bash
cd contracts

# Get current commit SHA (first 20 bytes)
COMMIT=$(git rev-parse HEAD | cut -c1-40)

# Deploy with pinned commit
forge script script/DeployFaucet.s.sol \
  --rpc-url https://sepolia.base.org \
  --broadcast \
  --private-key $KEY \
  -vvvv \
  --env COMMIT_SHA=0x$COMMIT
```

---

## Test Coverage

```
forge test --match-contract GitHubFaucetTest -v
```

| Test | Status |
|------|--------|
| test_SetRequirements_RequiresOwner | PASS |
| test_SetRequirements_OwnerCanSet | PASS |
| test_RecipientMustMatchCertificate | PASS |
| test_CaseInsensitiveCooldown | PASS |
| test_CommitRequirementEnforced | PASS |
| test_LegitimateClaimSucceeds | PASS |
| test_ClaimWithPinnedCommit | PASS |
