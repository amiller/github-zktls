# PredictionMarket V3 - Tests

## Test Suite Overview

### Unit Tests (`test/PredictionMarketV3.t.sol`)

Comprehensive unit tests covering all V3 functionality:

**Market Creation (2 tests)**
- ✅ `testCreateMarket` - Market creation with proper parameter binding
- ✅ `testCreateMarketRevertsIfDeadlineInPast` - Deadline validation

**Betting (4 tests)**
- ✅ `testBetYes` - Bet on YES position
- ✅ `testBetNo` - Bet on NO position
- ✅ `testBetRevertsIfZero` - Zero bet rejection
- ✅ `testBetRevertsAfterDeadline` - Post-deadline bet rejection

**Settlement - ISigstoreVerifier Integration (9 tests)**
- ✅ `testSettleWithValidProof` - Happy path with valid proof
- ✅ `testSettleRevertsIfInvalidProof` - Verifier.verifyAndDecode() reversion
- ✅ `testSettleRevertsIfCertificateHashMismatch` - att.artifactHash != sha256(certificate)
- ✅ `testSettleRevertsIfWrongCommit` - att.commitSha != market.oracleCommitSha
- ✅ `testSettleRevertsIfWrongRepo` - att.repoHash != market.repoHash
- ✅ `testSettleRevertsIfParameterMismatch` - topic/keyword/oracleType mismatch
- ✅ `testSettleRevertsIfNotSettleable` - settleable=false (NO_COMMENTS)
- ✅ `testSettleYesWins` - found=true → YES wins
- ✅ `testSettleNoWins` - found=false → NO wins

**Claims (3 tests)**
- ✅ `testClaimWinnings` - Winner claims full pot
- ✅ `testClaimProportionalPayout` - Multiple winners split proportionally
- ✅ `testClaimRevertsIfNoWinningBet` - Loser cannot claim
- ✅ `testClaimRevertsIfAlreadyClaimed` - Double claim prevention

**View Functions (2 tests)**
- ✅ `testGetOdds` - Odds calculation
- ✅ `testGetPotentialPayout` - Payout estimation

**Security (2 tests)**
- ✅ `testAnyoneCanSettle` - Permissionless settlement
- ✅ `testCannotSettleWithoutValidProof` - Proof verification enforced

**Total: 22 unit tests**

### Integration Test (`test-anvil-v3.sh`)

End-to-end Anvil test simulating full workflow:

1. **Deploy** - MockSigstoreVerifier + PredictionMarket
2. **Create Market** - Topic 12345, keyword "radicle", first comment oracle
3. **Place Bets** - Alice 3 ETH YES, Bob 1 ETH NO
4. **Advance Time** - Past deadline
5. **Prepare Certificate** - Create oracle-result.json
6. **Configure Mock** - Set attestation (certificate hash, repo hash, commit SHA)
7. **Settle** - Trustless settlement with certificate verification
8. **Claim** - Winner claims proportional payout
9. **Verify** - Check payout matches expected amount

## Running Tests

### Unit Tests (Foundry)

```bash
cd oracle/foundry-tests
forge test --match-contract PredictionMarketV3Test -vv
```

**Expected output:**
```
Running 22 tests for test/PredictionMarketV3.t.sol:PredictionMarketV3Test
[PASS] testBetNo() (gas: ...)
[PASS] testBetRevertsAfterDeadline() (gas: ...)
[PASS] testBetRevertsIfZero() (gas: ...)
[PASS] testBetYes() (gas: ...)
[PASS] testClaimProportionalPayout() (gas: ...)
[PASS] testClaimRevertsIfAlreadyClaimed() (gas: ...)
[PASS] testClaimRevertsIfNoWinningBet() (gas: ...)
[PASS] testClaimWinnings() (gas: ...)
[PASS] testCreateMarket() (gas: ...)
[PASS] testCreateMarketRevertsIfDeadlineInPast() (gas: ...)
[PASS] testGetOdds() (gas: ...)
[PASS] testGetPotentialPayout() (gas: ...)
[PASS] testSettleRevertsIfCertificateHashMismatch() (gas: ...)
[PASS] testSettleRevertsIfInvalidProof() (gas: ...)
[PASS] testSettleRevertsIfNotSettleable() (gas: ...)
[PASS] testSettleRevertsIfParameterMismatch() (gas: ...)
[PASS] testSettleRevertsIfWrongCommit() (gas: ...)
[PASS] testSettleRevertsIfWrongRepo() (gas: ...)
[PASS] testSettleWithValidProof() (gas: ...)
[PASS] testSettleYesWins() (gas: ...)
[PASS] testSettleNoWins() (gas: ...)
[PASS] testAnyoneCanSettle() (gas: ...)
[PASS] testCannotSettleWithoutValidProof() (gas: ...)
Test result: ok. 22 passed; 0 failed; finished in ...
```

### Anvil Integration Test

**Terminal 1:** Start Anvil
```bash
anvil
```

**Terminal 2:** Run test
```bash
cd oracle
./test-anvil-v3.sh
```

**Expected output:**
```
🧪 PredictionMarket V3 - Anvil Integration Test
================================================

✅ Anvil is running

📦 Step 1: Deploy MockSigstoreVerifier
✅ MockSigstoreVerifier deployed at: 0x...

📦 Step 2: Deploy PredictionMarket V3
✅ PredictionMarket deployed at: 0x...

📝 Step 3: Create prediction market
  Topic: 12345
  Keyword: radicle
  Oracle: first comment
  Deadline: ...
✅ Market created! ID: 0

💰 Step 4: Place bets
  Alice bets 3 ETH on YES
  Bob (address[1]) bets 1 ETH on NO
✅ Bets placed!

  YES pool: 3.0 ETH
  NO pool: 1.0 ETH

  Current odds:
    YES: 75%
    NO: 25%

⏭️  Step 5: Fast forward past deadline
✅ Time advanced

🔮 Step 6: Prepare oracle certificate
  Certificate hash: 0x...
  Repo hash: 0x...

🔧 Step 7: Configure MockSigstoreVerifier
✅ Mock verifier configured

⚖️  Step 8: Settle market
✅ Market settled!

  Settled: true
  Result: true (true = YES wins)

💸 Step 9: Claim winnings
  Alice claims (she bet YES and won)
✅ Alice claimed: 4.0000 ETH

========================================
🎉 All tests passed!
========================================

Summary:
  ✅ MockSigstoreVerifier deployed
  ✅ PredictionMarket V3 deployed
  ✅ Market created with parameters
  ✅ Bets placed (3 ETH YES, 1 ETH NO)
  ✅ Time advanced past deadline
  ✅ Oracle certificate prepared
  ✅ Settlement succeeded (YES wins)
  ✅ Winner claimed payout

🔑 Key V3 Features Tested:
  ✅ ISigstoreVerifier integration
  ✅ Certificate hash verification
  ✅ Repo hash verification
  ✅ Commit SHA verification
  ✅ Parameter binding (topic/keyword/oracle_type)
  ✅ Settleable flag enforcement
  ✅ Trustless settlement (anyone can call)
```

## What V3 Tests Verify

### Core Security Properties

1. **Trustless Settlement**
   - Anyone can call settle() (no authorization)
   - Invalid proofs are rejected
   - Security comes from cryptography, not access control

2. **ISigstoreVerifier Integration**
   - Proof verification via verifyAndDecode()
   - Certificate hash must match attestation
   - Repo hash must match attestation
   - Commit SHA must match attestation

3. **Parameter Binding**
   - conditionHash binds market to (topic_id, keyword, oracle_type)
   - Cannot settle with wrong oracle data
   - Certificate must contain matching parameters

4. **Commit Pinning**
   - Oracle must run from specific commit SHA
   - Prevents oracle code changes after market creation
   - Attestation proves exact code version

5. **Certificate Parsing**
   - Extract settleable flag (NO_COMMENTS check)
   - Extract found field (YES/NO determination)
   - Verify all parameters in JSON match market

6. **Parimutuel Mechanics**
   - Proportional payout calculation
   - Division by zero protection
   - Double claim prevention

## Comparison to V1/V2

| Feature | V1 | V2 | V3 |
|---------|----|----|-----|
| **Settlement** | trustedSettler only | Anyone | Anyone |
| **Proof Verification** | ❌ None | ❌ None | ✅ ISigstoreVerifier |
| **Trust Model** | Trust human | Social consensus | **Cryptographic** |
| **Repo Check** | String compare | String compare | **Hash in attestation** |
| **Commit Check** | String compare | String compare | **SHA in attestation** |
| **Griefing Resistance** | ✅ Trusted | ❌ No protection | ✅ **Proof required** |
| **Tests** | 14 (wrong model) | 0 | **22 unit + integration** |

## Next Steps

After tests pass:
1. Deploy V3 to Base Sepolia with real SigstoreVerifier
2. Update settlement scripts to generate ZK proofs
3. Document proof generation workflow
4. Archive V1/V2 contracts
5. Update all documentation to reference V3

---

**Status:** Tests written, ready to run in Foundry environment.
