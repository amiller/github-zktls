# Testnet Faucet Demo

Claim testnet ETH by proving you have a GitHub account. No ETH needed—submit your proof via GitHub Issues and we'll relay it for you.

**Contract:** [`0xcfb53ce24F4B5CfA3c4a70F559F60e84C96bf863`](https://sepolia.basescan.org/address/0xcfb53ce24F4B5CfA3c4a70F559F60e84C96bf863) (Base Sepolia)

## How It Works

```
You                        GitHub Actions                 This Repo                  Contract
 │                              │                              │                          │
 ├── fork & run workflow ──────>│                              │                          │
 │                              ├── Sigstore attestation       │                          │
 │                              │                              │                          │
 ├── download bundle            │                              │                          │
 ├── docker: generate proof     │                              │                          │
 │                              │                              │                          │
 ├── open [CLAIM] issue ───────────────────────────────────────>│                          │
 │                              │                              ├── relay tx ─────────────>│
 │                              │                              │                  verify proof
 │                              │                              │                  send ETH
 │                              │                              │<─────────────────────────┤
 │<─────────────────────────────────────────── comment result ─┤                          │
```

## Step-by-Step

### 1. Fork This Repo

Click "Fork" on GitHub. You need your own copy to run workflows.

### 2. Run the GitHub Identity Workflow

```bash
# Via CLI
gh workflow run github-identity.yml \
  -f recipient_address=0xYOUR_ETH_ADDRESS \
  -f faucet_address=0xcfb53ce24F4B5CfA3c4a70F559F60e84C96bf863

# Or via GitHub UI:
# Actions → GitHub Identity → Run workflow → Enter your ETH address
```

This creates a Sigstore-attested certificate proving:
- Your GitHub username (`github.actor`)
- Which repo ran the workflow
- The exact commit SHA

### 3. Download the Attestation Bundle

```bash
# Find your run ID
gh run list --workflow=github-identity.yml

# Download the bundle
gh run download RUN_ID -n identity-proof

# You should have: bundle.json (or similar)
```

### 4. Generate the ZK Proof

```bash
# Using our Docker image (recommended)
docker run --rm \
  -v $(pwd):/work \
  -e RECIPIENT=0xYOUR_ETH_ADDRESS \
  ghcr.io/amiller/zkproof generate /work/bundle.json /work/proof

# Or build locally
cd zk-proof && docker build -t zkproof .
docker run --rm -v $(pwd):/work -e RECIPIENT=0xYOUR_ADDRESS \
  zkproof generate /work/bundle.json /work/proof
```

**Output:**
```
proof/
├── proof.bin      # Raw proof (10KB)
├── proof.hex      # Hex-encoded for contracts
├── inputs.json    # Public inputs array
└── claim.json     # Ready to paste in issue
```

### 5. Submit Your Claim

**Option A: Via GitHub Issue (no ETH needed)**

1. Open a new issue on this repo
2. Title: `[CLAIM] Faucet request`
3. Paste the contents of `proof/claim.json` in a code block:

```json
{
  "proof": "0x...",
  "inputs": ["0x...", ...],
  "recipient": "0xYOUR_ADDRESS"
}
```

A GitHub Action will:
- Parse your proof
- Submit the transaction (we pay gas)
- Comment with the result
- Close the issue

**Option B: Submit Directly (if you have ETH)**

```bash
cast send 0xcfb53ce24F4B5CfA3c4a70F559F60e84C96bf863 \
  "claim(bytes,bytes32[],address)" \
  "$(cat proof/proof.hex)" \
  "$(cat proof/inputs.json)" \
  0xYOUR_ADDRESS \
  --rpc-url https://sepolia.base.org \
  --private-key $YOUR_KEY
```

## Faucet Rules

| Rule | Value |
|------|-------|
| **Cooldown** | 1 claim per repo per 24 hours |
| **Max claim** | 0.001 ETH |
| **Dynamic amount** | `min(0.001 ETH, balance/20)` |

The cooldown is per-repo, not per-user. This provides Sybil resistance—you can't claim faster by creating multiple addresses.

## Troubleshooting

**"Already claimed today"**
Your repo already claimed within the last 24 hours. Wait or use a different fork.

**"Faucet empty"**
The faucet needs funding. Try again later or fund it yourself (it accepts ETH deposits).

**Proof generation fails**
- Ensure you downloaded the correct attestation bundle
- Check Docker has enough memory (2GB recommended)

**Issue not processed**
- Title must contain `[CLAIM]`
- Body must have valid JSON in a code block
- Check the workflow run logs for errors

## Trust Model

The issue-based relayer is a **convenience**, not a trust assumption. Here's why:

1. **Proof verification is on-chain.** The smart contract verifies the ZK proof. Invalid proofs are rejected regardless of who submits them.

2. **Anyone can relay.** You can submit transactions directly, run your own relayer, or use ours. The prover doesn't need to trust the relayer.

3. **Funds go to your address.** The `recipient` is specified in the proof inputs. The relayer can't redirect funds.

4. **Replay protection is on-chain.** The contract tracks claims per repo-hash. Double-claims are rejected by the contract, not the relayer.

The relayer just pays gas on your behalf. It has no special permissions.

## Contract Interface

```solidity
interface IGitHubFaucet {
    function claim(
        bytes calldata proof,
        bytes32[] calldata publicInputs,
        address payable recipient
    ) external;

    function canClaim(bytes32 repoHash) external view returns (bool, uint256 nextClaimTime);
    function claimAmount() external view returns (uint256);
}
```

## Run Your Own Relayer

Want to run your own gasless claim flow? The pattern is simple:

1. Accept signed proofs (via API, GitHub Issues, Telegram, etc.)
2. Parse and validate format
3. Call `claim()` with a funded wallet
4. Report result to user

See `.github/workflows/process-claim.yml` for our implementation.
