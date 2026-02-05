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
5. **Fetch authenticated data** over TLS inside the runner
6. **Attest the response** — GitHub signs what the API returned

This is "GitHub as zkTLS"—prove what an API said without revealing your session.

For on-chain verification, attestations are too verbose. Enter ZK:

7. **Generate a ZK proof** that verifies the Sigstore certificate chain
8. **Verify on-chain** with a single contract call (~300k gas)
9. **Extract claims** — repo, commit, artifact hash — without the full certificate

---

## Try It: Testnet Faucet

Claim testnet ETH by proving you have a GitHub account.

**How it works:** The workflow outputs a `certificate.json` containing your GitHub username. The contract verifies:
1. The ZK proof is valid (Sigstore signed this attestation)
2. `sha256(certificate) == artifactHash` (certificate wasn't tampered)
3. Your username appears in the certificate
4. You haven't claimed in the last 24 hours

```bash
# 1. Fork this repo
gh repo fork

# 2. Run the identity workflow
gh workflow run github-identity.yml -f recipient_address=0xYOUR_ADDRESS

# 3. Download the attestation bundle + certificate
gh run download $(gh run list -L1 --json databaseId -q '.[0].databaseId') -n identity-proof

# 4. Generate ZK proof
docker run --rm -v $(pwd):/work zkproof generate /work/bundle.json /work/proof

# 5. Submit to contract (note: includes certificate + username)
cast send 0xDd29de730b99b876f21f3AB5DAfBA6711fF2c6AC \
  "claim(bytes,bytes32[],bytes,string,address)" \
  "$(cat proof/proof.hex)" "$(cat proof/inputs.json)" \
  "$(cat identity-proof/certificate.json)" "YOUR_GITHUB_USERNAME" 0xYOUR_ADDRESS \
  --rpc-url https://sepolia.base.org --private-key $YOUR_KEY
```

No ETH for gas? [Open an issue](docs/faucet.md#gasless-claims) titled `[CLAIM]` with your proof—we'll relay it.

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

### Workflow Templates

| Template | Proves | Secrets |
|----------|--------|---------|
| `github-identity.yml` | You control a GitHub account | None |
| `tweet-capture.yml` | You authored a tweet | `TWITTER_SESSION` |
| `file-hash.yml` | File contents at a commit | None |

See [`workflow-templates/`](workflow-templates/) for ready-to-use workflows.

---

## GitHub as zkTLS

Traditional zkTLS requires MPC ceremonies or specialized notary servers. GitHub gives you this for free:

| Step | What Happens |
|------|--------------|
| **1. Store credentials** | Add session cookies/tokens as GitHub Secrets |
| **2. Run workflow** | Headless browser fetches authenticated data |
| **3. TLS terminates in runner** | GitHub's isolated VM sees the plaintext |
| **4. Output becomes artifact** | Tweet content, API response, account data |
| **5. Sigstore attests** | Proof that *this workflow* produced *this output* |

The trust model: GitHub sees your session, but only runs the code you committed. Anyone can audit the workflow. The attestation binds the result to the exact code version.

### Example: Prove Tweet Authorship

```yaml
# .github/workflows/tweet-capture.yml
- name: Fetch tweet as logged-in user
  env:
    TWITTER_SESSION: ${{ secrets.TWITTER_SESSION }}
  run: |
    # Browser fetches tweet, verifies you're the author
    node capture-tweet.js $TWEET_ID > tweet.json
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

**Base Sepolia:** [`0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725`](https://sepolia.basescan.org/address/0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725)

```solidity
import {ISigstoreVerifier} from "./ISigstoreVerifier.sol";

contract MyApp {
    ISigstoreVerifier verifier = ISigstoreVerifier(0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725);

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
├── contracts/                # On-chain verification
│   ├── src/
│   │   ├── ISigstoreVerifier.sol   # Interface
│   │   ├── SigstoreVerifier.sol    # Implementation
│   │   └── HonkVerifier.sol        # Generated verifier
│   └── examples/
│       ├── GitHubFaucet.sol        # Faucet demo
│       └── SimpleEscrow.sol        # Bounty pattern
│
├── workflow-templates/       # Ready-to-fork workflows
│   ├── github-identity.yml   # Prove GitHub account
│   ├── tweet-capture.yml     # Prove tweet authorship
│   └── file-hash.yml         # Prove file contents
│
├── browser-container/        # Headless Chrome for login proofs
│
└── docs/
    ├── faucet.md             # Faucet demo walkthrough
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
# 1. Run workflow in your fork
gh workflow run github-identity.yml -f recipient_address=0xYOUR_ADDRESS

# 2. Download attestation
gh run download RUN_ID -n identity-proof

# 3. Generate proof
docker run --rm -v $(pwd):/work zkproof generate /work/bundle.json /work/proof
```

### Verify On-Chain

```bash
cast call 0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725 \
  "verifyAndDecode(bytes,bytes32[])" \
  "$(cat proof/proof.hex)" "$(cat proof/inputs.json)" \
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
- [Trust Model](docs/trust-model.md) — Security guarantees
- [Auditing Workflows](docs/auditing-workflows.md) — For verifiers
- [Sigstore](https://sigstore.dev/) — Attestation infrastructure
- [Noir](https://noir-lang.org/) — ZK circuit language
