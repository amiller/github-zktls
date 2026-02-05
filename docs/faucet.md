# Testnet Faucet

Claim testnet ETH by proving you control a GitHub account.

**Contract:** [`0x5E27C06fb70e9365a6C2278298833CBd2b2d9793`](https://sepolia.basescan.org/address/0x5E27C06fb70e9365a6C2278298833CBd2b2d9793) (Base Sepolia)

## How It Works

1. Fork the repo and run the identity workflow
2. The workflow outputs `certificate.json` with your GitHub username
3. Sigstore attests: "this workflow produced this certificate"
4. Generate a ZK proof of the attestation
5. Submit proof + certificate to contract
6. Contract verifies `sha256(certificate) == artifactHash` and extracts your username

**Why this works:** The artifact hash is bound to the certificate contents. If you modify the certificate, the hash won't match. The contract parses `"github_actor": "<username>"` from the certificate and rate-limits per user.

## Step 1: Fork and Run

```bash
gh repo fork
```

This creates `yourusername/github-zktls`.

## Step 2: Run the Workflow

```bash
gh workflow run github-identity.yml \
  -f recipient_address=0xYOUR_ETH_ADDRESS \
  -f faucet_address=0x5E27C06fb70e9365a6C2278298833CBd2b2d9793
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
cast send 0x5E27C06fb70e9365a6C2278298833CBd2b2d9793 \
  "claim(bytes,bytes32[],bytes,string,address)" \
  "$(cat proof/proof.hex)" \
  "$(cat proof/inputs.json)" \
  "$(cat identity-proof/certificate.json)" \
  "YOUR_GITHUB_USERNAME" \
  0xYOUR_ADDRESS \
  --rpc-url https://sepolia.base.org \
  --private-key $YOUR_KEY
```

Done. ETH sent to your address.

---

## What the Contract Verifies

| Check | How |
|-------|-----|
| Valid attestation | ZK proof verifies Sigstore certificate chain |
| Certificate match | `sha256(certificate) == artifactHash` |
| Username in cert | `"github_actor": "<username>"` appears in certificate |
| Sybil resistance | One claim per GitHub username per day |

The contract extracts your GitHub username from the certificate and rate-limits per user—not per repo. You can't claim faster by creating multiple forks.

## Faucet Rules

| Rule | Value |
|------|-------|
| Cooldown | 1 claim per GitHub user per 24 hours |
| Max claim | 0.001 ETH |
| Dynamic amount | `min(0.001 ETH, balance/20)` |

The cooldown is **per-user**, not per-repo. Creating multiple forks doesn't help.

---

## Contract Interface

```solidity
function claim(
    bytes calldata proof,
    bytes32[] calldata publicInputs,
    bytes calldata certificate,    // raw certificate.json
    string calldata username,      // GitHub username
    address payable recipient
) external;

function canClaim(string calldata username) external view returns (bool, uint256 nextClaimTime);
function claimAmount() external view returns (uint256);
```

---

## Gasless Claims

Don't have ETH for gas? You can submit via GitHub Issues and we'll relay the transaction.

1. Open an issue on the main repo
2. Title: `[CLAIM] Faucet request`
3. Body: paste your claim data in a JSON code block

```json
{
  "proof": "0x...",
  "inputs": ["0x...", "0x...", ...],
  "certificate": {"github_actor": "yourusername", ...},
  "username": "yourusername",
  "recipient": "0xYOUR_ADDRESS"
}
```

A GitHub Action will submit the transaction and comment with the result.

### Why This Is Safe

The relayer is a **convenience**, not a trust assumption:

- **Proof verification is on-chain.** Invalid proofs are rejected by the contract.
- **Anyone can relay.** You can submit directly, run your own relayer, or use ours.
- **Recipient is in the certificate.** The relayer can't redirect funds.
- **Replay protection is on-chain.** The contract tracks claims per GitHub username.

The security comes from the contract, not the relayer.

---

## Troubleshooting

**"CertificateMismatch"**
The certificate you submitted doesn't match the attested artifact hash. Make sure you're submitting the exact `certificate.json` from your workflow run.

**"UsernameMismatch"**
The username you provided doesn't appear in the certificate. Check that you're using your exact GitHub username (case-sensitive).

**"AlreadyClaimedToday"**
Your GitHub username has already claimed in the last 24 hours. Wait and try again tomorrow.

**"Faucet empty"**
The faucet needs funding. Deposits welcome: `0x5E27C06fb70e9365a6C2278298833CBd2b2d9793`

**Proof generation fails**
- Check you downloaded the correct attestation bundle
- Ensure Docker has 2GB+ RAM

**Issue not processed**
- Title must contain `[CLAIM]`
- Body must have valid JSON in a ` ```json ` code block
- Check workflow logs for errors
