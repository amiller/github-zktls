# GitHub as TEE + ZKP

**Use GitHub Actions as a trusted execution environment. Verify the results on-chain with zero-knowledge proofs.**

## The Idea

Two parties who don't trust each other can both trust GitHub. When you run a workflow:

1. **GitHub executes your code** in an isolated runner
2. **Sigstore signs an attestation** binding repo + commit + output
3. **Anyone can verify** the attestation came from GitHub

This is "GitHub as TEE"—a transparent, auditable trusted execution environment.

But attestations are verbose and leak metadata. Enter ZK:

4. **Generate a ZK proof** that verifies the Sigstore attestation
5. **Verify on-chain** with a single contract call
6. **Claim extraction** proves specific facts without revealing the full certificate

This is "GitHub as ZKP"—prove you ran code on GitHub without exposing what or where.

---

## Try It: Testnet Faucet

Claim testnet ETH by proving you have a GitHub account.

```bash
# 1. Fork this repo, run the identity workflow
gh workflow run github-identity.yml -f recipient_address=0xYOUR_ADDRESS

# 2. Download the attestation bundle
gh run download $(gh run list -L1 --json databaseId -q '.[0].databaseId') -n identity-proof

# 3. Generate ZK proof (Docker only)
docker run --rm -v $(pwd):/work zkproof generate /work/bundle.json /work/proof

# 4. Submit to contract
cast send 0xcfb53ce24F4B5CfA3c4a70F559F60e84C96bf863 \
  "claim(bytes,bytes32[],address)" \
  "$(cat proof/proof.hex)" "$(cat proof/inputs.json)" 0xYOUR_ADDRESS \
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

## GitHub as ZKP

The ZK circuit verifies:

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

**What you must verify:**
- The workflow code does what you expect (fetch at commitSha, audit it)
- The artifact hash matches your expected computation

The ZK proof guarantees cryptographic validity. You decide whether to trust the workflow logic.

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

## Links

- [Faucet Demo](docs/faucet.md) — Try it yourself
- [Trust Model](docs/trust-model.md) — Security guarantees
- [Auditing Workflows](docs/auditing-workflows.md) — For verifiers
- [Sigstore](https://sigstore.dev/) — Attestation infrastructure
- [Noir](https://noir-lang.org/) — ZK circuit language
