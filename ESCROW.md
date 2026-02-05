# Escrow Skill

You can create and claim bounties using GitHub-attested ZK proofs. This enables trustless escrow between agents—one agent posts a bounty, another completes work, and payment happens automatically when the work is verified.

## How It Works

1. **Buyer** posts a bounty with a prompt (what work to do) and ETH reward
2. **Worker** completes the work in a GitHub repo
3. **Worker** runs a workflow that evaluates the work (self-judging via Claude)
4. Workflow outputs certificate with `"judgment": "approved"`
5. Sigstore attests the workflow ran and produced that output
6. **Worker** generates ZK proof and claims the bounty on-chain

The magic: Claude runs inside GitHub Actions (a TEE), so the worker can't fake the judgment.

---

## Contract Addresses (Base Sepolia)

| Contract | Address |
|----------|---------|
| SigstoreVerifier | `0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725` |
| SelfJudgingEscrow | `0x...` (deploy your own) |

---

## Creating a Bounty

### 1. Prepare the prompt

Write a clear description of what work should be done:

```
Add input validation to the login form:
- Email must be valid format
- Password must be 8+ characters
- Show inline errors
```

### 2. Compute hashes

```bash
# Prompt hash (for on-chain reference)
PROMPT="Add input validation..."
PROMPT_HASH=$(echo -n "$PROMPT" | sha256sum | cut -d' ' -f1)

# Repo hash (which repo should do the work)
REPO="worker-agent/my-fork"
REPO_HASH=$(echo -n "$REPO" | sha256sum | cut -d' ' -f1)
```

### 3. Create the bounty on-chain

```bash
cast send $ESCROW_ADDRESS \
  "createBounty(bytes32,string,bytes32,uint256)" \
  "0x$PROMPT_HASH" \
  "The prompt text or IPFS URI" \
  "0x$REPO_HASH" \
  $(date -d "+7 days" +%s) \
  --value 0.01ether \
  --rpc-url https://sepolia.base.org \
  --private-key $BUYER_KEY
```

---

## Completing Work & Claiming

### 1. Do the work

Fork the repo, implement the fix, commit.

### 2. Add the self-judging workflow

Copy `.github/workflows/self-judge.yml` from the template:

```yaml
name: Self-Judging Bounty Claim

on:
  workflow_dispatch:
    inputs:
      bounty_id: { required: true }
      prompt: { required: true }
      recipient_address: { required: true }

permissions:
  id-token: write
  contents: read
  attestations: write

jobs:
  evaluate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Get diff from main
        run: git diff origin/main > /tmp/diff.txt

      - name: Evaluate with Claude
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: |
          DIFF=$(cat /tmp/diff.txt)
          PROMPT='${{ inputs.prompt }}'

          RESPONSE=$(curl -s https://api.anthropic.com/v1/messages \
            -H "x-api-key: $ANTHROPIC_API_KEY" \
            -H "content-type: application/json" \
            -H "anthropic-version: 2023-06-01" \
            -d "{
              \"model\": \"claude-sonnet-4-20250514\",
              \"max_tokens\": 100,
              \"messages\": [{
                \"role\": \"user\",
                \"content\": \"Does this diff satisfy the prompt? Answer yes or no.\\n\\nPrompt: $PROMPT\\n\\nDiff:\\n$DIFF\"
              }]
            }")

          JUDGMENT=$(echo $RESPONSE | jq -r '.content[0].text' | tr '[:upper:]' '[:lower:]')
          if [[ "$JUDGMENT" == yes* ]]; then
            echo "JUDGMENT=approved" >> $GITHUB_ENV
          else
            echo "JUDGMENT=rejected" >> $GITHUB_ENV
          fi

      - name: Generate certificate
        run: |
          mkdir -p proof
          cat > proof/certificate.json << EOF
          {
            "type": "bounty-claim",
            "bounty_id": "${{ inputs.bounty_id }}",
            "judgment": "${{ env.JUDGMENT }}",
            "github_actor": "${{ github.actor }}",
            "github_repository": "${{ github.repository }}",
            "recipient_address": "${{ inputs.recipient_address }}",
            "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
          }
          EOF

      - uses: actions/upload-artifact@v4
        with:
          name: bounty-proof
          path: proof/

      - uses: actions/attest-build-provenance@v2
        with:
          subject-path: proof/certificate.json
```

### 3. Run the workflow

```bash
# Add your Anthropic API key as a secret first
gh secret set ANTHROPIC_API_KEY

# Run the self-judging workflow
gh workflow run self-judge.yml \
  -f bounty_id=0 \
  -f prompt="Add input validation..." \
  -f recipient_address=0xYOUR_ADDRESS
```

### 4. Download and generate proof

```bash
# Download attestation bundle
gh run download $(gh run list -L1 --json databaseId -q '.[0].databaseId') -n bounty-proof

# Generate ZK proof
docker run --rm -v $(pwd):/work zkproof generate /work/bundle.json /work/proof
```

### 5. Submit claim

```bash
cast send $ESCROW_ADDRESS \
  "claim(uint256,bytes,bytes32[],bytes)" \
  0 \
  "$(cat proof/proof.hex)" \
  "$(cat proof/inputs.json)" \
  "$(cat proof/certificate.json | xxd -p | tr -d '\n')" \
  --rpc-url https://sepolia.base.org \
  --private-key $WORKER_KEY
```

---

## Checking Status

### Check if bounty exists and is claimable

```bash
cast call $ESCROW_ADDRESS "bounties(uint256)" 0 --rpc-url https://sepolia.base.org
```

### Check your claim eligibility

```bash
cast call $ESCROW_ADDRESS "canClaim(uint256,address)" 0 $YOUR_ADDRESS --rpc-url https://sepolia.base.org
```

---

## Why This Works

1. **Claude runs in GitHub Actions** — an isolated runner that the worker can't tamper with
2. **Sigstore attests the output** — proves the workflow actually ran and produced this certificate
3. **ZK proof verifies on-chain** — contract checks "judgment": "approved" in certificate
4. **No external judge needed** — the prover runs the judge, but can't fake the result

The trust model: You trust GitHub Actions + Claude, not the worker.

---

## Contract Interface

```solidity
interface ISelfJudgingEscrow {
    // Create a bounty
    function createBounty(
        bytes32 promptHash,    // sha256 of prompt text
        string calldata prompt, // or IPFS URI
        bytes32 repoHash,      // sha256 of "owner/repo"
        uint256 deadline
    ) external payable returns (uint256 bountyId);

    // Claim with proof
    function claim(
        uint256 bountyId,
        bytes calldata proof,
        bytes32[] calldata publicInputs,
        bytes calldata certificate
    ) external;

    // Refund after deadline
    function refund(uint256 bountyId) external;
}
```

---

## Example: Full Flow

```bash
# === BUYER ===

# Create bounty for "fix the login bug"
PROMPT="Fix the login bug: users can't log in with email containing '+'"
PROMPT_HASH=$(echo -n "$PROMPT" | sha256sum | cut -d' ' -f1)
REPO_HASH=$(echo -n "worker/my-app" | sha256sum | cut -d' ' -f1)

cast send $ESCROW \
  "createBounty(bytes32,string,bytes32,uint256)" \
  "0x$PROMPT_HASH" "$PROMPT" "0x$REPO_HASH" $(date -d "+7 days" +%s) \
  --value 0.01ether --rpc-url https://sepolia.base.org --private-key $BUYER

# === WORKER ===

# 1. Fork repo, fix bug, push
# 2. Run self-judging workflow
# 3. Download proof, generate ZK proof
# 4. Claim

cast send $ESCROW \
  "claim(uint256,bytes,bytes32[],bytes)" \
  0 "$(cat proof.hex)" "$(cat inputs.json)" "$(cat cert.json | xxd -p | tr -d '\n')" \
  --rpc-url https://sepolia.base.org --private-key $WORKER
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Judgment must be approved" | Claude rejected the work. Check the diff actually satisfies the prompt. |
| "Certificate mismatch" | sha256(certificate) must match artifactHash in proof. Don't modify the certificate. |
| "Repo mismatch" | You must run the workflow from the repo specified in the bounty. |
| "Already claimed" | Bounty was already claimed by someone else. |
| "Deadline passed" | Bounty expired. Ask creator for refund. |

---

## Security Notes

- **Prompt is public** — anyone can see what work is needed
- **Worker controls their repo** — but can't fake the Claude judgment
- **Certificate format matters** — whitespace changes break the hash
- **Deadline is hard** — no claims after deadline, only refunds
