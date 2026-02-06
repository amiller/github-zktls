# Login with Email

Prove you own an email address and mint an NFT — no wallet signing, no Docker, no AWS account needed.

A **notary** (anyone running this repo with AWS SES credentials) sends you a challenge code. You prove you received it. An NFT gets minted to your address. That's it.

## How It Works

```
You                          Notary Repo                    Chain
 │                               │                            │
 ├─ Open issue ─────────────────►│                            │
 │  [EMAIL] claim NFT            │                            │
 │  email: me@example.com        │                            │
 │  recipient: 0xABC...          │                            │
 │                                ├─ Generate challenge        │
 │                                ├─ Send via SES              │
 │◄─── Email: code 847291 ──────┤                            │
 │                                ├─ Comment challenge_hash    │
 │                                │                            │
 ├─ Reply: 847291 ──────────────►│                            │
 │                                ├─ Verify code               │
 │                                ├─ Generate certificate      │
 │                                ├─ Sigstore attest           │
 │                                ├─ Generate ZK proof         │
 │                                ├─ Submit claim tx ─────────►│
 │                                │                            ├─ Verify proof
 │                                │                            ├─ Mint NFT
 │◄── Comment: ✅ NFT minted! ──┤                            │
```

## Claim an Email NFT

### 1. Open an issue

Go to the notary's repo and open a new issue:

- **Title:** `[EMAIL] Claim email NFT`
- **Body:**
  ```
  email: your@email.com
  recipient: 0xYourEthAddress
  ```

### 2. Check your email

You'll receive an email with a 6-digit verification code.

### 3. Reply to the issue

Post a comment with just the code:

```
847291
```

The workflow verifies the code, generates a ZK proof, and submits the claim. Your NFT will be minted automatically. The issue closes with a link to the transaction.

## Trust Model

### What the notary can't do

- **See the challenge code** — SES sends the email; the code only exists in the ephemeral GitHub Actions runner and your inbox. SES doesn't store email bodies.
- **Fake a verification** — The workflow code is public and pinned by Sigstore attestation. Anyone can audit exactly what ran.
- **Redirect your NFT** — The recipient address is in the Sigstore-attested certificate. Changing it would break the proof.

### What you trust

1. **GitHub Actions isolation** — The runner environment is sandboxed. The notary can't inject code into a running workflow.
2. **Sigstore attestation** — Binds the certificate to the exact workflow code + commit that produced it.
3. **The workflow code** — It's public. Read it. The commit SHA is in the attestation.
4. **AWS SES** — Doesn't store email contents by default. The notary would have to modify the workflow to enable logging (which would be visible in the code).

### Compared to Privy

| | Privy | Email NFT |
|---|---|---|
| Trust | Privy's servers | Auditable workflow code |
| Transparency | Closed source | Open source + attested |
| Result | Session token | On-chain NFT |
| Speed | Seconds | ~10 minutes |
| Decentralized | No | Yes — anyone can be a notary |

## Run Your Own Notary

Anyone with a GitHub repo and AWS account can be a notary.

### 1. Fork this repo

### 2. Set up AWS SES

- Create an IAM user with `ses:SendEmail` permission
- Verify a sender email address (or domain) in SES
- If in SES sandbox mode, also verify test recipient emails

### 3. Add GitHub secrets

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM access key |
| `AWS_SECRET_ACCESS_KEY` | IAM secret key |
| `AWS_REGION` | SES region (e.g. `us-east-1`) |
| `SES_FROM_EMAIL` | Verified sender email |
| `RELAYER_PRIVATE_KEY` | Funded wallet for gas on Base Sepolia |

### 4. Add GitHub variables

| Variable | Description |
|----------|-------------|
| `EMAIL_NFT_ADDRESS` | Deployed EmailNFT contract address |

### 5. Deploy the contract

```bash
cd contracts
forge create examples/EmailNFT.sol:EmailNFT \
  --constructor-args <VERIFIER_ADDRESS> 0x0000000000000000000000000000000000000000 \
  --private-key $(cat ~/.foundry/keystores/deployer.key) \
  --rpc-url https://sepolia.base.org
```

### 6. Create the `email-pending` label

Go to your repo's Labels page and create a label named `email-pending`.

### 7. Test it

Open an issue with `[EMAIL]` in the title and your email + recipient address. Check your email, reply with the code, and verify the NFT mints.

## Contract

`EmailNFT.sol` is an ERC-721 that mints one NFT per verified email address:

- Verifies ZK proof via `SigstoreVerifier`
- Checks `sha256(certificate) == artifactHash`
- Checks certificate contains the claimed email and recipient
- One mint per email (case-insensitive)
- Token ID = `keccak256(toLower(email))`

## Architecture Notes

- **Same ZK circuit** as GitHub identity proofs — the circuit verifies Sigstore attestations generically
- **Same prover** — no new cryptography needed
- **Two workflows**: `email-challenge.yml` (sends code) and `email-verify.yml` (verifies + claims)
- **Issue-based UX** — no wallet connection or Docker required from the claimer
