# Testnet Faucet

Claim testnet ETH by proving you control a GitHub account.

**Contract:** [`0xcfb53ce24F4B5CfA3c4a70F559F60e84C96bf863`](https://sepolia.basescan.org/address/0xcfb53ce24F4B5CfA3c4a70F559F60e84C96bf863) (Base Sepolia)

## How It Works

1. Run a workflow in your fork → Sigstore attests "this GitHub user ran this code"
2. Generate a ZK proof → proves the attestation without revealing metadata
3. Submit proof to contract → contract verifies and sends ETH

The contract doesn't know which repo you used—only that you have a valid Sigstore attestation from *some* GitHub repo. One claim per repo per day.

## Step 1: Run the Workflow

Fork any repo containing the `github-identity.yml` workflow, then run it:

```bash
gh workflow run github-identity.yml \
  -f recipient_address=0xYOUR_ETH_ADDRESS \
  -f faucet_address=0xcfb53ce24F4B5CfA3c4a70F559F60e84C96bf863
```

Or via GitHub UI: **Actions → GitHub Identity → Run workflow**

This creates a Sigstore attestation proving your GitHub username triggered the workflow.

## Step 2: Download the Attestation

```bash
# Find your run
gh run list --workflow=github-identity.yml

# Download the bundle
gh run download RUN_ID -n identity-proof
```

You'll get a `bundle.json` containing the Sigstore attestation.

## Step 3: Generate the Proof

```bash
docker run --rm -v $(pwd):/work zkproof generate /work/bundle.json /work/proof
```

Output:
```
proof/
├── proof.hex     # Hex-encoded proof for contract
├── inputs.json   # Public inputs array
└── claim.json    # Convenience format (for issue-based claims)
```

## Step 4: Submit to Contract

```bash
cast send 0xcfb53ce24F4B5CfA3c4a70F559F60e84C96bf863 \
  "claim(bytes,bytes32[],address)" \
  "$(cat proof/proof.hex)" \
  "$(cat proof/inputs.json)" \
  0xYOUR_ADDRESS \
  --rpc-url https://sepolia.base.org \
  --private-key $YOUR_KEY
```

Done. ETH sent to your address.

---

## Faucet Rules

| Rule | Value |
|------|-------|
| Cooldown | 1 claim per repo per 24 hours |
| Max claim | 0.001 ETH |
| Dynamic amount | `min(0.001 ETH, balance/20)` |

The cooldown is **per-repo**, not per-user—you can't claim faster by creating multiple addresses.

---

## Contract Interface

```solidity
function claim(
    bytes calldata proof,
    bytes32[] calldata publicInputs,
    address payable recipient
) external;

function canClaim(bytes32 repoHash) external view returns (bool, uint256 nextClaimTime);
function claimAmount() external view returns (uint256);
```

---

## Gasless Claims

Don't have ETH for gas? You can submit via GitHub Issues and we'll relay the transaction.

1. Open an issue on the main repo
2. Title: `[CLAIM] Faucet request`
3. Body: paste `proof/claim.json` in a code block

```json
{
  "proof": "0x...",
  "inputs": ["0x...", ...],
  "recipient": "0xYOUR_ADDRESS"
}
```

A GitHub Action will submit the transaction and comment with the result.

### Why This Is Safe

The relayer is a **convenience**, not a trust assumption:

- **Proof verification is on-chain.** Invalid proofs are rejected by the contract.
- **Anyone can relay.** You can submit directly, run your own relayer, or use ours.
- **Recipient is in the proof.** The relayer can't redirect funds.
- **Replay protection is on-chain.** The contract tracks claims per repo-hash.

The security comes from the contract, not the relayer.

---

## Troubleshooting

**"Already claimed today"**
Your repo claimed within the last 24 hours. Wait or use a different fork.

**"Faucet empty"**
The faucet needs funding. Deposits welcome: `0xcfb53ce24F4B5CfA3c4a70F559F60e84C96bf863`

**Proof generation fails**
- Check you downloaded the correct attestation bundle
- Ensure Docker has 2GB+ RAM

**Issue not processed**
- Title must contain `[CLAIM]`
- Body must have valid JSON in a ` ```json ` code block
- Check workflow logs for errors
