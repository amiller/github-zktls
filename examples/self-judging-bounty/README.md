# Self-Judging Bounty Example

Trustless bounties where Claude evaluates the work—inside GitHub Actions.

## The Pattern

```
1. Buyer posts bounty: "Fix bug X" + promptHash + 0.01 ETH
2. Worker completes work in their fork
3. Worker runs self-judging workflow:
   - Gets diff from main
   - Calls Claude: "Does this diff satisfy the prompt?"
   - Outputs: { "judgment": "approved" }
   - Sigstore attests
4. Worker generates ZK proof
5. Contract verifies "judgment": "approved" → pays out
```

**Why it's trustless:** Claude runs inside GitHub Actions (a TEE). The worker triggers it but can't fake the response. Sigstore proves what the workflow outputted.

---

## Setup

### 1. Deploy the contract (or use existing)

```bash
cd contracts
forge script script/DeploySelfJudgingEscrow.s.sol --rpc-url https://sepolia.base.org --broadcast
```

### 2. Fork the repo where work will happen

```bash
gh repo fork target-org/target-repo
cd target-repo
```

### 3. Add the workflow

Copy `workflow.yml` to `.github/workflows/self-judge.yml` in your fork.

### 4. Add your Anthropic API key

```bash
gh secret set ANTHROPIC_API_KEY
```

---

## Creating a Bounty (Buyer)

```bash
# Define the work
PROMPT="Add input validation to login form: email format, 8+ char password, inline errors"
PROMPT_HASH=$(echo -n "$PROMPT" | sha256sum | cut -d' ' -f1)

# Which repo should do the work
REPO="worker/my-fork"
REPO_HASH=$(echo -n "$REPO" | sha256sum | cut -d' ' -f1)

# Deadline: 7 days from now
DEADLINE=$(date -d "+7 days" +%s)

# Create bounty
cast send $ESCROW_ADDRESS \
  "createBounty(bytes32,string,bytes32,uint256)" \
  "0x$PROMPT_HASH" \
  "$PROMPT" \
  "0x$REPO_HASH" \
  $DEADLINE \
  --value 0.01ether \
  --rpc-url https://sepolia.base.org \
  --private-key $BUYER_KEY

# Note the bounty ID from the BountyCreated event
```

---

## Claiming a Bounty (Worker)

### 1. Do the work

```bash
# Make your changes
git checkout -b fix-login-validation
# ... implement the fix ...
git add -A && git commit -m "Add login validation"
git push origin fix-login-validation
```

### 2. Run the self-judging workflow

```bash
gh workflow run self-judge.yml \
  -f bounty_id=0 \
  -f prompt="Add input validation to login form: email format, 8+ char password, inline errors" \
  -f recipient_address=0xYOUR_ADDRESS \
  -f escrow_address=$ESCROW_ADDRESS
```

### 3. Check the result

Wait for the workflow to complete, then check if Claude approved:

```bash
gh run view $(gh run list -L1 --json databaseId -q '.[0].databaseId')
```

Look for "Bounty Claim Approved" in the summary.

### 4. Download the attestation

```bash
gh run download $(gh run list -L1 --json databaseId -q '.[0].databaseId') -n bounty-proof
```

### 5. Generate ZK proof

```bash
docker run --rm -v $(pwd):/work zkproof generate /work/bundle.json /work/proof
```

### 6. Submit the claim

```bash
cast send $ESCROW_ADDRESS \
  "claim(uint256,bytes,bytes32[],bytes)" \
  0 \
  "$(cat proof/proof.hex)" \
  "$(cat proof/inputs.json)" \
  "$(cat bounty-proof/certificate.json | xxd -p | tr -d '\n')" \
  --rpc-url https://sepolia.base.org \
  --private-key $WORKER_KEY
```

---

## How Claude Judges

The workflow sends Claude:

```
You are judging whether code changes satisfy a bounty prompt.

PROMPT:
Add input validation to login form: email format, 8+ char password, inline errors

DIFF:
[your git diff here]

Does this diff adequately satisfy the prompt? Answer with just 'yes' or 'no' on the first line, then a brief reason.
```

Claude responds with either:
- `yes` → certificate gets `"judgment": "approved"`
- `no` → certificate gets `"judgment": "rejected"` (claim will fail)

---

## Security Model

| Component | Trust |
|-----------|-------|
| GitHub Actions | TEE - isolated runner, can't tamper |
| Sigstore | Attests workflow output, publicly auditable |
| Claude API | Called from inside Actions, response is attested |
| ZK Proof | Verifies Sigstore certificate chain on-chain |
| Contract | Only pays if `"judgment": "approved"` in certificate |

**What the worker controls:**
- Which diff to evaluate
- When to run the workflow
- Nothing else

**What the worker CAN'T fake:**
- Claude's response
- The attestation
- The ZK proof

---

## Troubleshooting

### "JudgmentNotApproved"

Claude said no. Check:
- Does the diff actually satisfy the prompt?
- Is the diff too small to evaluate?
- Run locally first: `git diff origin/main`

### "CertificateMismatch"

The certificate was modified after attestation. Don't edit `certificate.json`.

### "RepoMismatch"

You ran the workflow from a different repo than specified in the bounty. Fork the correct repo.

### "Expired"

Bounty deadline passed. Only the creator can refund now.

---

## Contract Interface

```solidity
// Create bounty
function createBounty(
    bytes32 promptHash,    // sha256(prompt)
    string calldata prompt,
    bytes32 repoHash,      // sha256("owner/repo")
    uint256 deadline
) external payable returns (uint256 bountyId);

// Claim with proof (must have "judgment": "approved")
function claim(
    uint256 bountyId,
    bytes calldata proof,
    bytes32[] calldata publicInputs,
    bytes calldata certificate
) external;

// Refund after deadline (creator only)
function refund(uint256 bountyId) external;
```

---

## Files

```
examples/self-judging-bounty/
├── README.md        # This file
├── workflow.yml     # Copy to .github/workflows/
└── prompt.md        # Example bounty prompt
```
