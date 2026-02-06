# Testnet Faucet

Claim testnet ETH by proving you control a GitHub account.

**Contract:** [`0x72cd70d28284dD215257f73e1C5aD8e28847215B`](https://sepolia.basescan.org/address/0x72cd70d28284dD215257f73e1C5aD8e28847215B) (Base Sepolia)

## How It Works

1. Fork the repo and run the identity workflow
2. The workflow outputs a certificate with your GitHub username
3. Sigstore attests: "this workflow produced this certificate"
4. Generate a ZK proof of the attestation (outputs `claim.json` with everything bundled)
5. Submit claim to contract (or open an issue for gasless relay)
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
  -f faucet_address=0x72cd70d28284dD215257f73e1C5aD8e28847215B
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

**Option A: Gasless (via GitHub Issue)**

Open an [issue](https://github.com/amiller/github-zktls/issues/new) with title `[CLAIM]` and paste your `claim.json` in a ```json code block. A relayer will submit for you.

**Option B: Direct submission**

```bash
CLAIM=$(cat proof/claim.json)
cast send 0x72cd70d28284dD215257f73e1C5aD8e28847215B \
  "claim(bytes,bytes32[],bytes,string,address)" \
  $(echo "$CLAIM" | jq -r '.proof') \
  $(echo "$CLAIM" | jq -c '.inputs') \
  $(echo "$CLAIM" | jq -r '.certificate | @json') \
  $(echo "$CLAIM" | jq -r '.username') \
  $(echo "$CLAIM" | jq -r '.recipient') \
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
    bytes calldata certificate,    // raw certificate bytes (with trailing newline)
    string calldata username,      // GitHub username
    address payable recipient
) external;

function canClaim(string calldata username) external view returns (bool, uint256 nextClaimTime);
function claimAmount() external view returns (uint256);
```

---

## Gasless Claims

Don't have ETH for gas? You can submit via GitHub Issues and we'll relay the transaction.

1. Open an [issue](https://github.com/amiller/github-zktls/issues/new) on the main repo
2. Title: `[CLAIM]`
3. Body: paste the contents of `claim.json` in a ```json code block

The prover generates `claim.json` with all required fields:
- `proof` - hex-encoded ZK proof
- `inputs` - array of bytes32 public inputs
- `certificate` - raw certificate string (with trailing newline preserved)
- `username` - GitHub username from certificate
- `recipient` - ETH address from certificate
- `faucet` - faucet contract address

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
The certificate hash doesn't match the attested artifact hash. This usually means the certificate was modified or the trailing newline was lost. Use the `claim.json` generated by the prover, which preserves exact formatting.

**"UsernameMismatch"**
The username you provided doesn't appear in the certificate. Check that you're using your exact GitHub username (case-sensitive).

**"AlreadyClaimedToday"**
Your GitHub username has already claimed in the last 24 hours. Wait and try again tomorrow.

**"Faucet empty"**
The faucet needs funding. Deposits welcome: `0x72cd70d28284dD215257f73e1C5aD8e28847215B`

**Proof generation fails**
- Check you downloaded the correct attestation bundle
- Ensure Docker has 2GB+ RAM

**Issue not processed**
- Title must contain `[CLAIM]`
- Body must have valid JSON in a ` ```json ` code block
- Check workflow logs for errors
