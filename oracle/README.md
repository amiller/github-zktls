# Prediction Market Oracle

**Extension to github-zktls:** Apply the same Sigstore attestation pattern to forum comments for prediction markets.

## Quick Start

```bash
# Test the oracle
cd oracle
node check-forum.js 27119 diamond
# ✅ FOUND: "diamond" appears in first comment!

# Or check any comment
node check-forum-any.js 27119 diamond 50
# ✅ FOUND in 17 comment(s)!
```

## What This Is

A **GitHub Actions-based oracle** for prediction markets on Ethereum Magicians forum comments.

**Use case:** Bet on whether a keyword appears in forum comments.

**Example bet:** "Will the first comment on the github-zktls post mention 'radicle'?"

## How It Works

Same trust model as github-zktls:

```
Forum Post → GitHub Workflow → Sigstore Attestation → Settlement Contract
```

1. Someone creates a prediction market
2. People bet YES or NO
3. Settler manually triggers workflow when ready
4. Workflow checks forum via Discourse API
5. Produces Sigstore attestation (proves result from this exact commit)
6. Anyone can verify the attestation independently
7. Contract settles based on verified result
8. Winners claim payouts

## Trust Model

**Same as github-zktls:**
- ✅ Trust GitHub Actions + Sigstore
- ✅ Code is public (auditable)
- ✅ Attestation binds to exact commit SHA
- ✅ Anyone can verify independently
- ❌ No centralized oracle

## Files

- `check-forum.js` - Oracle for first comment only
- `check-forum-any.js` - Oracle for any comment
- `contracts/PredictionMarket.sol` - Settlement contract
- `verify-attestation.sh` - Verification tool
- `USAGE.md` - Deployment guide
- `IMPLEMENTATION.md` - Architecture details
- `SETTLEMENT.md` - Settlement design (manual trigger)
- `ORACLE-VARIANTS.md` - First vs any comment

## Workflow

**Location:** `.github/workflows/oracle-check.yml`

**Trigger:** Manual only (no automatic polling)
- GitHub UI: Actions → Run workflow
- CLI: `gh workflow run oracle-check.yml -f topic_id=27680 -f keyword=radicle`

**Outputs:** Sigstore attestation proving the result

## Deployment

See [USAGE.md](USAGE.md) for complete deployment guide.

**Quick version:**
1. Deploy `contracts/PredictionMarket.sol` to Base Sepolia
2. Create market with this repo's commit SHA
3. When ready to settle, trigger workflow
4. Use attestation to settle contract
5. Winners claim

## Why This Extends github-zktls

**github-zktls proves:** "This email was received at this time"
**oracle proves:** "This comment appeared at this time"

**Same pattern, different data source.**

Both rely on:
- Public, auditable code
- GitHub Actions execution
- Sigstore attestation
- Commit SHA binding

## Documentation

- **CHALLENGE-RESPONSE.md** - How this answers Andrew's challenge
- **IMPLEMENTATION.md** - Full architecture
- **USAGE.md** - Step-by-step deployment
- **SETTLEMENT.md** - Why manual trigger > automatic
- **ORACLE-VARIANTS.md** - First vs any comment design

---

**Status:** Production-ready for testing
**Author:** clawTEEdah
**Pattern:** github-zktls for prediction markets
