# GitHub as TEE + ZKP

**Use GitHub Actions as a trusted execution environment. Verify the results on-chain with zero-knowledge proofs.**

## The Idea

Two parties who don't trust each other can both trust GitHub. When you run a workflow:

1. **GitHub executes your code** in an isolated runner
2. **Sigstore signs an attestation** binding repo + commit + output
3. **Anyone can verify** the attestation came from GitHub

This is "GitHub as TEE"—a transparent, auditable trusted execution environment.

But what can you prove? Anything the workflow can observe:

4. **Inject credentials** as GitHub Secrets (encrypted, never logged)
5. **Run a browser** with your session cookies inside the runner
6. **Capture authenticated content** — screenshots, page data, API responses
7. **Attest the result** — GitHub signs what the browser saw

This is "GitHub as zkTLS"—prove what a website showed you without revealing your session.

The **browser container** is key: a headless Chromium that runs inside GitHub Actions, injected with your session cookies. It captures proof artifacts (screenshots, DOM data) that get attested by Sigstore. Your credentials never leave the runner.

For on-chain verification, attestations are too verbose. Enter ZK:

7. **Generate a ZK proof** that verifies the Sigstore certificate chain
8. **Verify on-chain** with a single contract call (~300k gas)
9. **Extract claims** — repo, commit, artifact hash — without the full certificate

---

## Try It: Base Sepolia Faucet

![Claims](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Familler%2Fgithub-zktls%2Fmaster%2Fexamples%2Fleaderboard%2Fclaims.json&query=%24.stats.totalClaims&label=Claims&color=blue)
![Users](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Familler%2Fgithub-zktls%2Fmaster%2Fexamples%2Fleaderboard%2Fclaims.json&query=%24.stats.uniqueUsers&label=Users&color=green)
![ETH](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Familler%2Fgithub-zktls%2Fmaster%2Fexamples%2Fleaderboard%2Fclaims.json&query=%24.stats.totalEth&label=Base%20Sepolia%20ETH&color=purple)

Claim Base Sepolia testnet ETH by proving you have a GitHub account.

### Option A: GitHub Web UI (easiest)

1. **Fork this repo** — Click "Fork" at the top of this page
   - **Important:** Uncheck "Copy the master branch only" to include tags
2. **Switch to the release tag** — In your fork, click the branch dropdown → "Tags" → select `v1.0.1`
3. **Go to Actions** — Click the "Actions" tab
4. **Run the workflow** — Click "GitHub Identity" → "Run workflow"
   - **Important:** Select `v1.0.1` tag from the "Use workflow from" dropdown
   - Enter your ETH address (see below if you need one)
   - Leave "Generate ZK proof" checked (default)
   - Click "Run workflow" — takes ~5 min
5. **Download the artifact** — Click the completed run → download `identity-proof`
6. **Claim your ETH:**
   - **No gas?** [Open an issue](https://github.com/amiller/github-zktls/issues/new) titled `[CLAIM]` and paste the contents of `claim.json` in a ```json code block. We'll relay it for you.
   - **Have gas?** Submit directly with `cast send` (see below)

> **Why the tag?** The faucet contract verifies the exact commit SHA that produced your proof. Running from `v1.0.1` ensures your proof matches the expected commit.

### Option B: Command Line

```bash
# Fork and clone
gh repo fork amiller/github-zktls --clone
cd github-zktls

# Switch to the release tag
git checkout v1.0.1

# Run the workflow from the tag (proof generated in Actions)
gh workflow run github-identity.yml --ref v1.0.1 -f recipient_address=0xYOUR_ADDRESS

# Wait for completion, then download
gh run watch
gh run download -n identity-proof
```

**Submit your claim** (pick one):

```bash
cd identity-proof

# Option 1: Submit directly with cast (no relay needed)
CERT_HEX=0x$(xxd -p claim.json | tr -d '\n')  # NOTE: use xxd directly, not $(cat) — Bash strips trailing newlines
cast send 0x72cd70d28284dD215257f73e1C5aD8e28847215B \
  "claim(bytes,bytes32[],bytes,string,address)" \
  "$(jq -r .proof claim.json)" \
  "[$(jq -r '.inputs | join(",")' claim.json)]" \
  "0x$(printf '%s' "$(jq -r .certificate claim.json)" | xxd -p | tr -d '\n')" \
  "$(jq -r .username claim.json)" \
  "$(jq -r .recipient claim.json)" \
  --rpc-url https://sepolia.base.org --private-key $YOUR_KEY

# Option 2: Gasless relay — open an issue titled [CLAIM] and paste claim.json
```

**Prefer local proof generation?** Uncheck "Generate ZK proof" when running the workflow, then:

```bash
gh run download -n identity-proof
cd identity-proof
gh attestation download certificate.json -o .
mv *.jsonl bundle.json
docker run --rm -v $(pwd):/work ghcr.io/amiller/zkproof generate /work/bundle.json /work
# claim.json now has everything — submit with cast send as above
```

### Need an ETH address?

Install [Rabby](https://rabby.io/) or [Rainbow](https://rainbow.me/) wallet. They'll generate an address for you and keep your keys safe. For testnet, any address works—you just need somewhere to receive the ETH.

---

## Try It: Email Identity NFT

Prove you own an email address — no GitHub account, no wallet signing, no Docker needed. A notary sends you a challenge code by email; you share it back; an NFT gets minted.

**EmailNFT:** [`0x720000d8999423e3c47d9dd0c22f33ab3a93534b`](https://base-sepolia.blockscout.com/token/0x720000d8999423e3c47d9dd0c22f33ab3a93534b) (Base Sepolia) — [view all minted NFTs](https://base-sepolia.blockscout.com/token/0x720000d8999423e3c47d9dd0c22f33ab3a93534b)

### How to claim

1. [Open an issue](https://github.com/amiller/github-zktls/issues/new) with title `[EMAIL] claim NFT` and body:
   ```
   email: your@email.com
   recipient: 0xYourEthAddress
   ```
2. Check your email for a 64-character hex code
3. Comment the code on the issue (anyone can do this — the claimer doesn't need a GitHub account)

The workflow verifies the code, generates a ZK proof, and mints an ERC-721 with an on-chain SVG showing the verified email. One NFT per email, fully on-chain.

**Anyone can run their own notary** — just fork this repo and add AWS SES credentials. See [docs/email-login.md](docs/email-login.md) for the full walkthrough and trust model.

---

## GitHub as TEE

GitHub Actions provides:

| Property | How |
|----------|-----|
| **Isolation** | Fresh VM per run, no persistent state |
| **Transparency** | Workflow code visible at commit SHA |
| **Attestation** | Sigstore signs what ran (OIDC-based) |
| **Immutability** | Commit SHA = merkle root of repo |

The attestation binds three things:
- **Repository** — which repo triggered the workflow
- **Commit** — exact code version that ran
- **Artifact** — hash of the workflow output

Fetching the workflow at that commit SHA tells you exactly what executed. No ceremony needed.

**Trust vs convenience:** The TEE property comes from runner isolation + Sigstore attestations. Some examples also use GitHub issues, comments, and labels — those are application UX, not part of the trust model. A verifier checking a ZK proof on-chain only sees `artifactHash`, `repoHash`, `commitSha`. See [trust model](docs/trust-model.md#what-github-provides-trust-vs-convenience) for details.

### Workflow Templates

| Template | Proves | Uses Browser |
|----------|--------|--------------|
| `github-identity.yml` | GitHub account ownership | No |
| `email-challenge.yml` + `email-verify.yml` | Email ownership | No |
| `tweet-capture.yml` | Tweet authorship | Yes |
| `file-hash.yml` | File contents at commit | No |
| `sealed-box.yml` | Multi-attestation sealed box | No |

See [`workflow-templates/`](workflow-templates/) for ready-to-use templates and [`examples/workflows/`](examples/workflows/) for more examples including Twitter profile, GitHub contributions, and PayPal balance proofs.

---

## Try It: Sealed Box

Demonstrates **multiple attestations in a single workflow run** — proving an ephemeral keypair's entire lifecycle happened in one execution. The runner generates an RSA keypair, attests the public key, accepts encrypted submissions, decrypts them, and attests the results. Both attestations share the same `run_id`.

```bash
# One command: dispatch, encrypt, submit, verify
./examples/sealed-box/sealed-box.sh "my secret message"
```

No external binaries — uses `openssl` for RSA-OAEP encryption. See [docs/sealed-box.md](docs/sealed-box.md) for the pattern and trust model.

---

## GitHub as zkTLS

Traditional zkTLS requires MPC ceremonies or specialized notary servers. GitHub gives you this for free:

| Step | What Happens |
|------|--------------|
| **1. Store credentials** | Add session cookies as GitHub Secrets |
| **2. Run browser container** | Headless Chromium starts in the runner |
| **3. Inject session** | Cookies injected via Chrome extension bridge |
| **4. Capture proof** | Screenshot + page data extracted |
| **5. Sigstore attests** | Proof that *this workflow* produced *this output* |

The trust model: GitHub sees your session, but only runs the code you committed. Anyone can audit the workflow. The attestation binds the result to the exact code version.

### Browser Container

The [`browser-container/`](browser-container/) runs headless Chromium with a bridge API:

```bash
# Inject session cookies
curl -X POST http://localhost:3000/session \
  -d '{"cookies": [{"name": "auth_token", "value": "...", "domain": ".twitter.com"}]}'

# Navigate and capture
curl -X POST http://localhost:3000/navigate -d '{"url": "https://twitter.com/home"}'
curl -X POST http://localhost:3000/capture

# Get artifacts (screenshot + page data)
curl http://localhost:3000/artifacts
```

A Chrome extension inside the container handles cookie injection and page capture. The bridge API lets workflows orchestrate the browser without touching credentials directly.

### Example: Prove Twitter Identity

```yaml
# .github/workflows/twitter-proof.yml
- name: Start browser container
  run: docker compose up -d browser

- name: Inject session and capture profile
  env:
    TWITTER_SESSION: ${{ secrets.TWITTER_SESSION }}
  run: |
    # Inject cookies (parsed from session string)
    curl -X POST http://localhost:3000/session -d "$TWITTER_SESSION"

    # Get logged-in username
    USERNAME=$(curl -s http://localhost:3000/twitter/me | jq -r .username)

    # Generate certificate
    echo '{"twitter_username": "'$USERNAME'"}' > certificate.json
```

The artifact contains the tweet content + proof you authored it. No one else can see your session cookies.

---

## Gas-Efficient On-Chain Verification

Raw Sigstore attestations are ~4KB of JSON + certificates. Verifying on-chain would cost millions of gas. The ZK circuit compresses this:

The circuit verifies:

1. **Certificate chain** — Sigstore intermediate CA signed the leaf cert (P-384 ECDSA)
2. **Attestation signature** — Leaf cert signed the DSSE envelope (P-256 ECDSA)
3. **Claim extraction** — Extracts repo hash, commit SHA, artifact hash

The proof is ~10KB. Verification is a single contract call.

```solidity
ISigstoreVerifier.Attestation memory att = verifier.verifyAndDecode(proof, inputs);
// att.repoHash   — SHA-256 of "owner/repo"
// att.commitSha  — 20-byte git commit
// att.artifactHash — SHA-256 of workflow output
```

### On-Chain Verifier

**Base Sepolia:** [`0xbD08fd15E893094Ad3191fdA0276Ac880d0FA3e1`](https://sepolia.basescan.org/address/0xbD08fd15E893094Ad3191fdA0276Ac880d0FA3e1)

```solidity
import {ISigstoreVerifier} from "./ISigstoreVerifier.sol";

contract MyApp {
    ISigstoreVerifier verifier = ISigstoreVerifier(0xbD08fd15E893094Ad3191fdA0276Ac880d0FA3e1);

    function claimReward(bytes calldata proof, bytes32[] calldata inputs) external {
        ISigstoreVerifier.Attestation memory att = verifier.verifyAndDecode(proof, inputs);
        require(att.repoHash == EXPECTED_REPO, "Wrong repo");
        // ... your logic
    }
}
```

---

## Repository Structure

```
├── zk-proof/                 # ZK proving system
│   ├── circuits/             # Noir circuit (P-256 + P-384 verification)
│   ├── js/                   # Witness generator
│   └── Dockerfile            # One-command proof generation
│
├── browser-container/        # Headless browser for authenticated proofs
│   ├── bridge.js             # HTTP API for browser control
│   ├── proof-extension/      # Chrome extension for capture
│   └── docker-compose.yml    # Container orchestration
│
├── contracts/                # On-chain verification
│   ├── src/
│   │   ├── ISigstoreVerifier.sol   # Interface
│   │   ├── SigstoreVerifier.sol    # Implementation
│   │   └── HonkVerifier.sol        # Generated verifier
│   └── examples/
│       ├── GitHubFaucet.sol        # Faucet demo
│       ├── EmailNFT.sol            # Email identity NFT
│       ├── SimpleEscrow.sol        # Basic bounty
│       └── SelfJudgingEscrow.sol   # AI-judged bounty
│
├── examples/sealed-box/         # Multi-attestation sealed box
│   ├── sealed-box.sh            # Full CLI orchestration
│   ├── submit.sh                # Standalone submit helper
│   └── verify-linkage.sh        # Verify attestation linkage
│
├── workflow-templates/       # Ready-to-fork workflows
│   ├── github-identity.yml   # Prove GitHub account
│   ├── tweet-capture.yml     # Prove tweet authorship
│   └── file-hash.yml         # Prove file contents
│
└── docs/
    ├── faucet.md             # Faucet demo walkthrough
    ├── email-login.md        # Email NFT walkthrough
    ├── trust-model.md        # What the proof guarantees
    └── auditing-workflows.md # Guide for verifiers
```

---

## Trust Model

**What the proof guarantees:**
- ✓ Valid Sigstore certificate chain (hardcoded intermediate CA)
- ✓ Correct signature verification (P-256 + P-384 ECDSA in-circuit)
- ✓ Immutable binding: repo × commit × artifact

**What contracts can verify:**
- `sha256(certificate) == artifactHash` — the certificate wasn't tampered with
- Certificate contents — extract claims like `github_actor` for per-user logic
- `commitSha` — optionally pin to a specific workflow version

**The pattern:** The workflow outputs a structured certificate. The contract verifies the certificate matches the attested artifact hash, then parses it to extract claims. No circuit changes needed for new claim types.

See [docs/trust-model.md](docs/trust-model.md) for details.

---

## Quick Start

### Generate a Proof

```bash
# Run workflow in your fork (proof generated automatically)
gh workflow run github-identity.yml -f recipient_address=0xYOUR_ADDRESS

# Wait and download
gh run watch && gh run download -n identity-proof
```

The artifact contains `claim.json` ready for submission.

### Verify On-Chain

```bash
cast call 0xbD08fd15E893094Ad3191fdA0276Ac880d0FA3e1 \
  "verifyAndDecode(bytes,bytes32[])" \
  "$(cat identity-proof/proof.hex)" "$(cat identity-proof/inputs.json)" \
  --rpc-url https://sepolia.base.org
```

### Build Your Own App

```solidity
ISigstoreVerifier.Attestation memory att = verifier.verifyAndDecode(proof, inputs);
// Use att.repoHash, att.commitSha, att.artifactHash
```

---

---

## For Agents

**Trustless escrow between agents.** Post a bounty, get verifiable work, pay automatically.

The pattern: One agent posts a bounty with a prompt. Another agent forks the repo, does the work, runs a self-judging workflow where Claude evaluates the diff, and claims the bounty with a ZK proof.

```bash
# Worker claims bounty after Claude approves their diff
cast send $ESCROW "claim(uint256,bytes,bytes32[],bytes)" ...
```

**No external judge needed.** Claude runs inside GitHub Actions—the worker triggers it but can't fake the response.

See [ESCROW.md](ESCROW.md) for the full skill file, or [examples/self-judging-bounty/](examples/self-judging-bounty/) for a worked example.

---

## Links

- [ESCROW.md](ESCROW.md) — Agent escrow skill file
- [Faucet Demo](docs/faucet.md) — Try it yourself
- [Email Identity NFT](docs/email-login.md) — Email verification walkthrough
- [Sealed Box](docs/sealed-box.md) — Multi-attestation pattern
- [Trust Model](docs/trust-model.md) — Security guarantees
- [Auditing Workflows](docs/auditing-workflows.md) — For verifiers
- [Sigstore](https://sigstore.dev/) — Attestation infrastructure
- [Noir](https://noir-lang.org/) — ZK circuit language
