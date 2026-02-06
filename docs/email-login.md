# Login with Email

Prove you own an email address and mint an on-chain NFT — no wallet signing, no Docker, no AWS account needed.

A **notary** (anyone running this repo with AWS SES credentials) sends you a challenge code via email. You prove you received it by sharing the code back. An NFT with your email rendered as an on-chain SVG gets minted to your address.

## How It Works

```
You                          Notary Repo                    Chain
 │                               │                            │
 ├─ Open issue ─────────────────►│                            │
 │  [EMAIL] claim NFT            │                            │
 │  email: me@example.com        │                            │
 │  recipient: 0xABC...          │                            │
 │                                ├─ Generate 32-byte token    │
 │                                ├─ Send via AWS SES          │
 │◄─── Email with hex code ─────┤                            │
 │                                ├─ Comment challenge_hash    │
 │                                │                            │
 │  (share code via any channel)  │                            │
 │                                │                            │
 ├─ Someone comments code ──────►│                            │
 │                                ├─ Verify sha256(code)       │
 │                                ├─ Sigstore attest           │
 │                                ├─ Generate ZK proof         │
 │                                ├─ Submit claim tx ─────────►│
 │                                │                            ├─ Verify proof
 │                                │                            ├─ Mint NFT
 │◄── Comment: ✅ NFT minted! ──┤                            │
```

The claimer **does not need a GitHub account**. They receive the code by email and can share it with anyone (the notary, a friend, a Telegram bot) who comments it on the issue.

## Claim an Email NFT

### 1. Open an issue

Go to the notary's repo and [open a new issue](https://github.com/amiller/github-zktls/issues/new):

- **Title:** `[EMAIL] claim NFT`
- **Body:**
  ```
  email: your@email.com
  recipient: 0xYourEthAddress
  ```

### 2. Check your email

You'll receive an email with a 64-character hex verification code.

### 3. Comment the code on the issue

Anyone can post the code as a comment — the email recipient, the notary, a friend, or a bot. Just paste the hex code:

```
6b288af8ccf580767da0ee1f7083ba44c5a1f33b5eec420a9a807f22d540da89
```

The workflow automatically:
1. Verifies `sha256(code) == challenge_hash`
2. Checks the code hasn't expired (1 hour window)
3. Cross-references the Phase 1 workflow run
4. Generates a Sigstore-attested certificate
5. Generates a ZK proof via Docker prover
6. Submits the claim transaction to mint the NFT
7. Comments the transaction link and closes the issue

## Deployed Instance

| | Address |
|---|---|
| **EmailNFT** | [`0x720000d8999423e3c47d9dd0c22f33ab3a93534b`](https://sepolia.basescan.org/address/0x720000d8999423e3c47d9dd0c22f33ab3a93534b) |
| **SigstoreVerifier** | [`0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725`](https://sepolia.basescan.org/address/0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725) |
| **Chain** | Base Sepolia (84532) |

## Trust Model

### What the notary can't do

- **See the challenge code** — SES sends the email; the code only exists in the ephemeral runner and your inbox
- **Fake a verification** — Workflow code is public and pinned by Sigstore attestation
- **Redirect your NFT** — The recipient address is in the attested certificate

### What you trust

1. **GitHub Actions isolation** — The runner is sandboxed
2. **Sigstore attestation** — Binds certificate to exact workflow code + commit
3. **The workflow code** — It's public. The commit SHA is in the attestation.
4. **AWS SES** — Doesn't store email bodies by default

### Compared to Privy

| | Privy | Email NFT |
|---|---|---|
| Trust | Privy's servers | Auditable workflow code |
| Transparency | Closed source | Open source + attested |
| Result | Session token | On-chain NFT (ERC-721) |
| Decentralized | No | Yes — anyone can be a notary |

## NFT Details

Each NFT has an **on-chain SVG** rendered as a dark gradient card showing the verified email address. The SVG is fully on-chain — no IPFS, no external URLs.

- One NFT per email address (case-insensitive dedup)
- Token ID = `keccak256(toLower(email))`
- Standard ERC-721 (transferable)
- `tokenURI()` returns a base64 data URI with the SVG

## Run Your Own Notary

Anyone with a GitHub repo and AWS account can be a notary.

### 1. Fork this repo

### 2. Set up AWS SES

- Create an IAM user with `ses:SendRawEmail` permission
- Verify a sender email address (or domain) in SES
- If in SES sandbox mode, also verify recipient emails

### 3. Add GitHub secrets

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM access key |
| `AWS_SECRET_ACCESS_KEY` | IAM secret key |
| `AWS_REGION` | SES region (e.g. `us-east-2`) |
| `SES_FROM_EMAIL` | Verified sender email |
| `RELAYER_PRIVATE_KEY` | Funded wallet for gas on Base Sepolia |

### 4. Add GitHub variables

| Variable | Description |
|----------|-------------|
| `EMAIL_NFT_ADDRESS` | Deployed EmailNFT contract address |
| `PROVER_REGISTRY` | (Optional) Docker registry for prover image. Default: `ghcr.io/amiller/zkproof` |

### 5. Deploy the contract

```bash
cd contracts
VERIFIER=0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725
cast send --create $(forge inspect examples/EmailNFT.sol:EmailNFT bytecode) \
  $(cast abi-encode "constructor(address,bytes20)" $VERIFIER 0x0000000000000000000000000000000000000000) \
  --private-key $YOUR_KEY --rpc-url https://sepolia.base.org
```

### 6. Test it

Open an issue with `[EMAIL]` in the title and your email + recipient address. Check your email, comment the code, and verify the NFT mints.

## Architecture

### Two-Phase Workflow

**Phase 1: `email-challenge.yml`** — Triggers on issue opened with `[EMAIL]` in title
- Parses email + recipient from issue body
- Generates 32-byte random token, computes `challenge_hash = sha256(token)`
- Sends HTML email via AWS SES with token displayed
- Comments challenge metadata on issue (hash, email, recipient, timestamp, run ID)

**Phase 2: `email-verify.yml`** — Triggers on `issue_comment` on `[EMAIL]` issues
- Smart filter: skips comments that aren't valid hex tokens (≥32 chars)
- Cross-references Phase 1 bot comment for challenge metadata
- Verifies Phase 1 workflow run (correct workflow file + same commit SHA)
- Checks token expiry (1 hour)
- Generates certificate → Sigstore attests → ZK proof via Docker → submits claim tx
- Comments result and closes issue

### Docker Prover Image

The ZK proof is generated by a Docker image containing nargo + barretenberg. The image is pinned by SHA256 digest (trust anchor) but the registry source is overridable:

```yaml
env:
  PROVER_DIGEST: sha256:8425820d13dfa3d7e268412cce15ddf198798bee969afc40b048eeafe6fa37e7
run: |
  REGISTRY="${{ vars.PROVER_REGISTRY || 'ghcr.io/amiller/zkproof' }}"
  docker run "${REGISTRY}@${PROVER_DIGEST}" generate /work/bundle.json /work
```

The digest is rigid — it can only change by editing the workflow source (which is Sigstore-attested). The registry can be overridden so anyone can host a mirror.

### Contract: EmailNFT.sol

- ERC-721 with on-chain SVG `tokenURI()`
- Verifies ZK proof via `SigstoreVerifier`
- Checks `sha256(certificate) == artifactHash`
- Pattern-matches certificate for email and recipient
- One mint per email (case-insensitive dedup)
- Same ZK circuit as GitHub identity proofs
