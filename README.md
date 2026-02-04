# ZK Sigstore Attestation

**Prove you ran code on GitHub. Verify on-chain. Get paid.**

## Try It: Testnet Faucet

Get testnet ETH by proving you have a GitHub account.

```bash
# 1. Fork this repo and run the GitHub Identity workflow
gh workflow run github-identity.yml -f recipient_address=0xYOUR_ADDRESS

# 2. Download attestation bundle
gh run download $(gh run list -L1 --json databaseId -q '.[0].databaseId') -n identity-proof

# 3. Generate proof (Docker only)
docker run --rm -v $(pwd):/work -e RECIPIENT=0xYOUR_ADDRESS \
  ghcr.io/amiller/zkproof generate /work/bundle.json /work/proof

# 4. Claim via GitHub Issue (no ETH needed!)
#    Open issue at this repo titled "[CLAIM] Faucet request"
#    Paste contents of proof/claim.json
```

**Or submit directly** if you have gas:
```bash
cast send 0xcfb53ce24F4B5CfA3c4a70F559F60e84C96bf863 \
  "claim(bytes,bytes32[],address)" \
  $(cat proof/proof.hex) "$(cat proof/inputs.json)" 0xYOUR_ADDRESS \
  --rpc-url https://sepolia.base.org --private-key $KEY
```

**Requirements:** Docker. That's it.

---

## What Is This?

GitHub Actions creates signed attestations (via Sigstore) proving what code ran. This repo provides:

1. **ZK Circuit** - Verifies Sigstore attestations, extracts claims
2. **On-Chain Verifier** - Solidity contract for trustless verification
3. **Workflow Templates** - Ready-to-use proofs for common claims
4. **Docker Prover** - One command to generate proofs

```
You                         GitHub Actions                    Contract
 │                                │                               │
 ├── run workflow ───────────────>│                               │
 │                                ├── execute code                │
 │                                ├── Sigstore signs attestation  │
 │                                │                               │
 ├── download attestation         │                               │
 ├── docker run zkproof ──────────────────────────────────────────>│
 │                                │                     verify(proof)
 │                                │                               │
 │                                │    ✓ proven: repo X, commit Y, artifact Z
```

## Use Cases

| Proof | What It Proves | Example Use |
|-------|----------------|-------------|
| **GitHub Identity** | You control a GitHub account | Faucets, airdrops, Sybil resistance |
| **Tweet Ownership** | You authored a tweet | Bounties, reputation |
| **API Access** | You have valid credentials | Service verification |
| **Computation** | Code produced specific output | Verifiable compute |

## Quick Start

### Requirements

- GitHub account
- Docker ([install](https://docs.docker.com/get-docker/))
- ~2GB RAM, ~1GB disk for proof generation

### As a Prover

**Step 1: Fork and run a workflow**

Fork this repo, then trigger a workflow:

```bash
# Simple identity proof
gh workflow run github-identity.yml -f address=0xYOUR_ETH_ADDRESS

# Or tweet ownership proof (requires TWITTER_SESSION secret)
gh workflow run tweet-capture.yml \
  -f tweet_url=https://x.com/you/status/123 \
  -f address=0xYOUR_ETH_ADDRESS
```

**Step 2: Download the attestation**

```bash
# Find your run
gh run list --workflow=github-identity.yml

# Download attestation bundle
gh run download RUN_ID -n attestation-bundle
```

**Step 3: Generate proof**

```bash
docker run --rm -v $(pwd):/work zkproof generate /work/bundle.json /work/proof

# Outputs:
#   proof/proof.bin   - ZK proof (10KB)
#   proof/inputs.bin  - Public inputs
#   proof/proof.hex   - Hex-encoded for contracts
```

**Step 4: Submit on-chain**

```bash
# Using cast (foundry)
cast send $VERIFIER_ADDRESS "verify(bytes,bytes32[])" \
  $(cat proof/proof.hex) $(cat proof/inputs.hex) \
  --rpc-url https://sepolia.base.org
```

### As a Verifier

**On-chain:**

```solidity
import {ISigstoreVerifier} from "./ISigstoreVerifier.sol";

contract MyApp {
    ISigstoreVerifier verifier = ISigstoreVerifier(0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725);

    function doSomething(bytes calldata proof, bytes32[] calldata inputs) external {
        ISigstoreVerifier.Attestation memory att = verifier.verifyAndDecode(proof, inputs);

        // att.artifactHash - hash of the workflow output
        // att.repoHash     - hash of the repo name
        // att.commitSha    - git commit that ran

        // Your logic here...
    }
}
```

**Deployed on Base Sepolia:** [`0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725`](https://sepolia.basescan.org/address/0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725)

## Workflow Templates

Copy these to your `.github/workflows/`:

| Template | Purpose | Secrets Needed |
|----------|---------|----------------|
| `github-identity.yml` | Prove GitHub account ownership | None |
| `tweet-capture.yml` | Prove tweet authorship | `TWITTER_SESSION` |
| `file-hash.yml` | Prove file contents at commit | None |

See `workflow-templates/` for all templates.

## Generate Proofs in CI

Don't want to run Docker locally? Add proof generation to your workflow:

```yaml
- name: Build prover
  run: cd zk-proof && docker build -t zkproof .

- name: Generate ZK proof
  run: |
    docker run --rm -v ${{ github.workspace }}:/work zkproof \
      generate /work/bundle.json /work/proof

- uses: actions/upload-artifact@v4
  with:
    name: zk-proof
    path: proof/
```

## Repository Structure

```
├── zk-proof/              # Prover tooling
│   ├── circuits/          # Noir ZK circuit
│   ├── js/                # Witness generator
│   └── Dockerfile.bb      # Barretenberg prover
├── contracts/             # On-chain verification
│   ├── src/               # ISigstoreVerifier interface + implementation
│   └── examples/          # Faucet, escrow patterns
├── workflow-templates/    # Ready-to-use workflows
├── browser-container/     # Browser automation for login proofs
└── examples/              # Demo applications
```

## Trust Model

**What the proof guarantees:**
- ✓ Valid Sigstore attestation (certificate chain verified in ZK)
- ✓ Correct claim extraction (artifactHash, repoHash, commitSha)
- ✓ Immutable binding between repo, commit, and artifact

**What YOU must verify:**
- The workflow code does what it claims (fetch at commitSha and audit)
- The artifact interpretation matches your expectations

**Note on the Issue-based relayer:** The GitHub Issues claim flow is a convenience for the faucet demo—it lets users claim without holding ETH for gas. This relayer is *not* part of the trust model. Anyone can run their own relayer, or submit transactions directly. The security guarantee comes entirely from the on-chain ZK verification, not from who submits the transaction.

See [docs/trust-model.md](docs/trust-model.md) for details.

## System Requirements

| Component | CPU | RAM | Disk | Time |
|-----------|-----|-----|------|------|
| Proof generation | 2+ cores | 2GB | 1GB | ~2 min |
| GitHub Actions runner | (standard) | (standard) | (standard) | ~3 min |

## Development

```bash
# Run contract tests
cd contracts && forge test -vv

# Build prover Docker image
cd zk-proof && docker build -f Dockerfile.bb -t zkproof .

# Compile circuit (requires nargo)
cd zk-proof/circuits && nargo compile
```

## Links

- [Trust Model](docs/trust-model.md) - What proofs guarantee
- [Generating Proofs](docs/generating-proofs.md) - Detailed guide
- [Auditing Workflows](docs/auditing-workflows.md) - For verifiers
- [Sigstore](https://sigstore.dev/) - Attestation infrastructure
- [Noir](https://noir-lang.org/) - ZK language
