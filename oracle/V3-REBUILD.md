# V3 Rebuild - Proper Sigstore Integration

## What Was Wrong

### V1 and V2: Ignored ISigstoreVerifier

Both previous versions (`PredictionMarket.sol` and `PredictionMarketV2.sol`) **completely ignored** the core infrastructure of this repository:

```solidity
// V1 & V2 - WRONG
function settle(
    ...,
    bytes memory attestation  // ❌ UNUSED!
) external {
    // No verification of attestation
    // Either trusted settler (V1) or social consensus (V2)
}
```

**Problem:** The entire github-zktls repo revolves around `ISigstoreVerifier` for cryptographic proof verification. V1/V2 bypassed it entirely.

### The Pattern I Missed

Every contract in `contracts/examples/`:
- `GitHubFaucet.sol`
- `SelfJudgingEscrow.sol`
- `AgentEscrow.sol`
- `SimpleEscrow.sol`

**All use the same pattern:**

```solidity
constructor(address _verifier) {
    verifier = ISigstoreVerifier(_verifier);
}

function someAction(
    bytes calldata proof,
    bytes32[] calldata publicInputs,
    bytes calldata certificate,
    ...
) external {
    // 1. Verify proof
    ISigstoreVerifier.Attestation memory att = 
        verifier.verifyAndDecode(proof, publicInputs);
    
    // 2. Check certificate hash
    if (sha256(certificate) != att.artifactHash) revert;
    
    // 3. Check commit/repo
    if (att.commitSha != requiredCommit) revert;
    
    // 4. Parse certificate
    // 5. Execute action
}
```

**This is the github-zktls trust model.**

## V3 Changes

### Architecture

```
Market Creation:
  ↓
User bets on outcome
  ↓
Deadline passes
  ↓
Oracle runs in GitHub Actions
  ├─ check-forum.js produces oracle-result.json
  ├─ GitHub Actions creates Sigstore attestation
  └─ ZK proof generated (bb prove)
  ↓
Anyone calls settle() with:
  ├─ proof (ZK proof bytes)
  ├─ publicInputs (84 field elements)
  └─ certificate (oracle-result.json)
  ↓
Contract verifies:
  ├─ ✅ Proof valid (ISigstoreVerifier)
  ├─ ✅ Certificate hash matches
  ├─ ✅ Commit SHA matches
  ├─ ✅ Repo matches
  ├─ ✅ Parameters match (topic_id, keyword, oracle_type)
  └─ ✅ Settleable flag true
  ↓
Market settled (cryptographically verified!)
  ↓
Winners claim proportional payout
```

### Key Differences from V1/V2

| Feature | V1 | V2 | V3 (Correct) |
|---------|----|----|--------------|
| **Settler** | Trusted address | Anyone | Anyone |
| **Verification** | None (trust settler) | None (social consensus) | **ISigstoreVerifier** |
| **Attestation** | Unused parameter | Unused parameter | **Cryptographically verified** |
| **Repo check** | String comparison | String comparison | **Hash in proof** |
| **Commit check** | String comparison | String comparison | **att.commitSha from proof** |
| **Trust model** | Centralized | Weak | **Trustless (github-zktls)** |
| **Can be griefed?** | No (trusted) | Yes (no verification) | **No (proof required)** |

### Security Properties (V3)

✅ **Trustless**: No trusted settler needed
✅ **Permissionless**: Anyone can settle with valid proof  
✅ **Cryptographically secure**: Invalid proofs rejected on-chain
✅ **Parameter binding**: conditionHash + proof verification prevent wrong data
✅ **Commit pinning**: att.commitSha ensures exact oracle version
✅ **Repo verification**: att.repoHash prevents impersonation
✅ **DoS resistant**: Invalid settlement attempts fail (don't lock market)

### Certificate Parsing

Oracle produces `oracle-result.json`:

```json
{
  "settleable": true,
  "found": true,
  "result": "FOUND",
  "topic_id": "12345",
  "keyword": "radicle",
  "oracle_type": "first",
  "first_comment": {
    "id": 789,
    "username": "vitalik",
    "created_at": "2024-02-08T10:00:00Z",
    "excerpt": "I think radicle is..."
  },
  "timestamp": "2024-02-08T10:05:00Z",
  "oracle_version": "1.2.0"
}
```

Contract verifies:
1. Proof attests to this exact JSON (sha256 match)
2. Proof was created by correct repo + commit
3. JSON contains expected topic_id, keyword, oracle_type
4. `settleable: true` (first comment exists)
5. Extract `found` field → determines winner

### Why This Matches github-zktls

**Email NFT pattern:**
- User proves they received email from specific domain
- Contract verifies DKIM signature (cryptographically)
- No trusted party needed

**Prediction Market V3 pattern:**
- User proves oracle ran with specific result
- Contract verifies Sigstore attestation (cryptographically)
- No trusted party needed

**Both use cryptographic proof instead of trust in humans.**

## Migration Path

1. ✅ Deploy V3 contract (new address)
2. Mark V1/V2 as deprecated
3. Write tests for V3
4. Update documentation
5. Create example flow (oracle → proof generation → settlement)

## Next Steps

- [ ] Write comprehensive tests for V3
- [ ] Update settlement scripts to generate proofs
- [ ] Document proof generation flow
- [ ] Deploy V3 to testnet
- [ ] Archive V1/V2 contracts

---

**Lesson learned:** When working on a repo that revolves around specific infrastructure (ISigstoreVerifier), USE THAT INFRASTRUCTURE. Don't build parallel systems.
