# Lessons Learned - Prediction Market Implementation

## What Went Wrong

### Timeline of Mistakes

1. **Initial approach (V1)** - Built prediction market in `oracle/` folder
   - Added `trustedSettler` modifier
   - Ignored `ISigstoreVerifier` completely
   - Used `bytes attestation` parameter but never touched it
   - **Why:** Didn't look at `contracts/examples/` first

2. **Second attempt (V2)** - Removed `trustedSettler`
   - Attempted "trustless" by removing authorization
   - Still ignored `ISigstoreVerifier`
   - Created "social consensus" model (weak)
   - **Why:** Tried to fix trust issues without understanding the crypto

3. **Third attempt (V3)** - Added `ISigstoreVerifier`
   - Finally imported the interface
   - But added `repoHash` check (anti-pattern)
   - Over-constrained compared to `GitHubFaucet`
   - **Why:** Still not carefully reading the reference implementation

### Root Cause: Didn't Read The Examples First

**The repo structure was screaming at me:**

```
contracts/
  examples/
    GitHubFaucet.sol       ← 100 lines, perfect reference
    SimpleEscrow.sol       ← Same pattern
    AgentEscrow.sol        ← Same pattern
    SelfJudgingEscrow.sol  ← Same pattern
  src/
    ISigstoreVerifier.sol  ← The core interface
    SigstoreVerifier.sol   ← The implementation
```

**What I should have done:**
1. Read `GitHubFaucet.sol` line by line
2. Understand the pattern: proof → verifyAndDecode → extract attestation → verify hash → parse certificate
3. Copy the pattern exactly
4. Only then adapt it to prediction markets

**What I actually did:**
1. Think "I need a prediction market"
2. Build from scratch
3. Add features that sounded smart (`trustedSettler`, `repoHash`)
4. Ignore the entire infrastructure the repo is built around

## The GitHubFaucet Pattern (Correct)

```solidity
constructor(address _verifier, bytes20 _requiredCommitSha) {
    verifier = ISigstoreVerifier(_verifier);
    requiredCommitSha = _requiredCommitSha;
}

function claim(
    bytes calldata proof,
    bytes32[] calldata publicInputs,
    bytes calldata certificate,
    ...
) external {
    // 1. Verify proof
    ISigstoreVerifier.Attestation memory att = 
        verifier.verifyAndDecode(proof, publicInputs);
    
    // 2. Verify certificate hash
    if (sha256(certificate) != att.artifactHash) 
        revert CertificateMismatch();
    
    // 3. Verify commit (ONLY commit, not repo!)
    if (requiredCommitSha != bytes20(0) && att.commitSha != requiredCommitSha) 
        revert WrongCommit();
    
    // 4. Parse certificate
    // 5. Execute action
}
```

**Key insights:**
- ✅ Only check `commitSha` (globally unique)
- ✅ Use `sha256(certificate)` not `keccak256`
- ✅ Certificate is the JSON artifact
- ✅ Anyone can call (trustless)
- ❌ No `repoHash` check
- ❌ No trusted settler
- ❌ No social consensus

## What Would Have Helped

### Documentation is actually fine

`GitHubFaucet.sol` is crystal clear. The problem wasn't documentation - it was me not reading it.

**What I needed:** Discipline to:
1. Study existing examples BEFORE coding
2. Copy patterns exactly BEFORE innovating
3. Ask "why does GitHubFaucet do it this way?" BEFORE adding features

### Better mental model

**Wrong model:** "I'm building a prediction market that uses Sigstore"
**Right model:** "I'm adapting GitHubFaucet's pattern to prediction market use case"

The second model would have kept me anchored to the proven pattern.

## Specific Mistakes

### 1. repoHash Anti-Pattern

**Why it's wrong:**
- Commit SHA is globally unique across all repos
- Prevents legitimate forks from settling (same code, same security)
- Adds constraint without adding security
- Not in `GitHubFaucet.sol` for good reason

**How I should have noticed:**
- GitHubFaucet only checks `commitSha`
- No other example checks `repoHash`
- If it was important, all examples would do it

### 2. Storing oracleRepo as string

**Wrong:**
```solidity
string oracleRepo;
bytes32 repoHash = keccak256(bytes(oracleRepo));
```

**Right (from GitHubFaucet):**
```solidity
bytes20 requiredCommitSha;
// That's it. No repo storage needed.
```

### 3. Over-engineering settlement

**V1 approach:** Add `trustedSettler` to prevent griefing
**V2 approach:** Remove settler, rely on "social consensus"
**V3 approach:** Add `repoHash` verification

**Correct approach (GitHubFaucet):** 
- Just verify the proof
- Invalid proofs get rejected by verifier
- Valid proofs mean valid data
- No additional constraints needed

## Testing Mistakes

**I wrote tests for the wrong patterns:**
- V1 tests: Tested `onlyTrustedSettler` modifier
- V2 tests: None (knew it was broken)
- V3 tests: Tested `repoHash` verification

**Should have:**
- Started with `GitHubFaucet.t.sol`
- Copied test structure
- Adapted to prediction market domain
- Tested ONLY what GitHubFaucet tests (proof verification, certificate matching, commit checking)

## Deployment Mistakes (Anticipated)

**What I might do wrong:**
- Deploy to wrong network
- Forget to deploy/configure SigstoreVerifier first
- Use wrong verifier address
- Not test with real oracle output
- Not verify contract source code

**What I should do:**
1. Check what network GitHubFaucet is deployed on
2. Use the SAME SigstoreVerifier address
3. Test locally with real oracle-result.json first
4. Verify source on Basescan
5. Create a market that's ALREADY settleable (so I can test immediately)

## Key Takeaways

1. **Read the examples first** - Don't build from scratch when patterns exist
2. **Copy, then adapt** - Don't innovate on trust model when crypto does it better
3. **Question your assumptions** - If your code looks different from examples, you're probably wrong
4. **Simpler is better** - Every feature I added (trustedSettler, repoHash) was a mistake
5. **Trust the crypto** - SigstoreVerifier already prevents all the attacks I tried to prevent manually

## Going Forward

**Before writing any contract:**
1. Find the most similar example
2. Read it completely
3. Copy the structure
4. Only change what's domain-specific
5. If tempted to add security features, STOP and ask why the example doesn't have them

**For this prediction market:**
- Remove `repoHash` completely
- Remove `oracleRepo` string storage
- Match `GitHubFaucet.sol` structure exactly
- Only prediction-market-specific code: betting, pools, payouts
- Everything else: copy GitHubFaucet

---

**Bottom line:** The problem wasn't unclear docs. The problem was me not reading the docs that were already clear.
