# Developer Guide

How the pieces fit together and what to do when things change.

## Architecture: The Three-Piece Chain

```
Circuit (Noir)  →  Docker Prover  →  On-Chain Verifier
   main.nr          zkproof:tag      HonkVerifier.sol
                                          ↓
                                     GitHubFaucet / EmailNFT
                                     (calls verifier)
```

**All three must use the same verification key (VK).** The VK is derived deterministically from the compiled circuit. If any piece is out of sync, proofs will fail with `SumcheckFailed()`.

## Updating the Circuit

If you change `zk-proof/circuits/src/main.nr`, you must update the entire chain:

### 1. Build and test locally

```bash
cd zk-proof/circuits
nargo compile
nargo execute    # with a valid Prover.toml
```

### 2. Rebuild the Docker prover

```bash
cd zk-proof
docker build -t zkproof .

# Verify it works
docker run --rm -v /path/to/test/proof:/work zkproof generate /work/bundle.json /work
```

### 3. Extract the new VK and regenerate HonkVerifier.sol

The Docker build pre-generates the VK. To get the Solidity verifier:

```bash
# Run bb inside the container to write the solidity verifier
docker run --rm -v $(pwd)/output:/out zkproof sh -c \
  'bb write_solidity_verifier -b /app/circuits/target/zk_github_attestation.json \
   -k /app/circuits/target/vk/vk -o /out/HonkVerifier.sol -t evm'
```

Copy the output to `contracts/src/HonkVerifier.sol`. Note the `VK_HASH` constant — it must match what the prover generates.

### 4. Run contract tests

```bash
cd contracts
forge test
```

### 5. Push the new Docker image

```bash
docker tag zkproof ghcr.io/amiller/zkproof:latest
docker push ghcr.io/amiller/zkproof:latest
# Record the sha256 digest from the push output
```

### 6. Update workflow files with new PROVER_DIGEST

Update the `PROVER_DIGEST` env var in:
- `.github/workflows/github-identity.yml`
- `.github/workflows/email-verify.yml`

### 7. Deploy new verifier (if VK changed)

```bash
cd contracts
forge script script/DeployFaucet.s.sol --broadcast --rpc-url https://sepolia.base.org
```

Or if only the verifier needs updating (faucet can stay):

```bash
# Deploy just the verifier
cast send --create $(forge inspect HonkVerifier bytecode) \
  --rpc-url https://sepolia.base.org --private-key $KEY
```

### 8. Tag a new release and update faucet

```bash
git tag v1.0.X
git push origin v1.0.X

# Update faucet's required commit (owner only)
COMMIT_SHA=$(git rev-parse v1.0.X | head -c 40)
cast send $FAUCET_ADDRESS "setRequirements(bytes20)" "0x${COMMIT_SHA}" \
  --rpc-url https://sepolia.base.org --private-key $KEY
```

### 9. Verify end-to-end

Trigger the `github-identity.yml` workflow, download the proof artifact, and submit a claim.

## Deployed Addresses

Keep these in sync. The single source of truth is the workflow files.

| Contract | Address | Configured In |
|----------|---------|---------------|
| SigstoreVerifier | `0xbD08fd15E893094Ad3191fdA0276Ac880d0FA3e1` | `contracts/script/DeployFaucet.s.sol` |
| GitHubFaucet | `0x72cd70d28284dD215257f73e1C5aD8e28847215B` | `.github/workflows/github-identity.yml`, `process-claim.yml` |
| EmailNFT | `0x720000d8999423e3c47d9dd0c22f33ab3a93534b` | `README.md`, `docs/email-login.md` |

## Common Mistakes

- **Updating the circuit but not rebuilding the prover** → VK mismatch → `SumcheckFailed()`
- **Deploying a new verifier but not updating the faucet** → faucet calls old verifier
- **Forgetting to update PROVER_DIGEST** → workflows use stale prover image
- **Not tagging a release** → faucet's `requiredCommitSha` check fails

## Tooling Versions

Pinned in `zk-proof/Dockerfile`:
- nargo: 1.0.0-beta.17
- barretenberg: v3.0.3

Changing either version will change the VK (same circuit, different tooling = different VK). Treat version bumps the same as circuit changes.

## Known Build Issues

**CRS download fails in Docker**: `bb` downloads the Aztec CRS (common reference string) on first use via HTTP, but `crs.aztec.network` now redirects to HTTPS and `bb v3.0.3` doesn't follow redirects. The Dockerfile pre-downloads the CRS via curl to work around this.
