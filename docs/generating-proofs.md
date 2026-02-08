# Generating Proofs

This guide walks through generating a ZK proof of a Sigstore attestation.

> **Easiest path**: The GitHub Identity and Email Identity workflows generate proofs
> automatically using the Docker prover. You only need this guide if you're generating
> proofs locally or building a custom workflow. See [developer-guide.md](developer-guide.md)
> for the Docker prover architecture.

## Docker Prover (Recommended)

```bash
# One command — generates witness, compiles, proves
docker run --rm -v $(pwd):/work ghcr.io/amiller/zkproof generate /work/bundle.json /work
```

Output: `proof.bin`, `inputs.bin`, `claim.json` in your working directory.

## Manual Steps (Reference)

The steps below document the manual process. Most users won't need this.

### Prerequisites

- A GitHub repository you control
- Node.js 18+
- Docker (for proof generation)
- `nargo` 1.0.0-beta.17+ (Noir compiler)

### Step 1: Set Up Your Workflow

### Option A: Fork This Repo

```bash
# Fork on GitHub, then clone
git clone https://github.com/YOUR_USERNAME/zk-sigstore-attestation
cd zk-sigstore-attestation
```

### Option B: Copy a Template

Copy a workflow template to your existing repo:

```bash
mkdir -p .github/workflows
cp templates/tweet-capture.yml .github/workflows/
```

### Configure Secrets

Go to your repo's Settings → Secrets and add any required secrets for your workflow.

## Step 2: Run the Workflow

Push a commit to trigger the workflow:

```bash
git commit --allow-empty -m "Trigger attestation"
git push
```

Or trigger manually via GitHub Actions UI if the workflow supports `workflow_dispatch`.

## Step 3: Download the Attestation Bundle

After the workflow completes:

```bash
# Find the attestation
gh attestation list --repo YOUR_USERNAME/YOUR_REPO

# Download it (replace DIGEST with the actual digest)
gh api /repos/YOUR_USERNAME/YOUR_REPO/attestations/sha256:DIGEST \
  | jq '.attestations[0]' > bundle.json
```

Or download from the GitHub UI: Actions → Your Run → Attestations.

## Step 4: Generate Witness

```bash
cd js
npm install
npx tsx src/index.ts witness ../bundle.json
```

This creates `circuits/Prover.toml` with the circuit inputs.

## Step 5: Compile and Execute Circuit

```bash
cd ../circuits
nargo compile
nargo execute
```

This creates:
- `target/zk_github_attestation.json` - Compiled circuit
- `target/zk_github_attestation.gz` - Witness

## Step 6: Generate Verification Key

```bash
# Build bb Docker image (first time only)
docker build -f ../Dockerfile.bb -t bb:3.0.3 --build-arg BB_VERSION=v3.0.3 .

# Generate VK
docker run --rm -v $(pwd)/target:/circuit bb:3.0.3 \
  write_vk -b /circuit/zk_github_attestation.json -o /circuit/vk -t evm
```

## Step 7: Generate Proof

```bash
docker run --rm -v $(pwd)/target:/circuit bb:3.0.3 \
  prove \
  -b /circuit/zk_github_attestation.json \
  -w /circuit/zk_github_attestation.gz \
  -k /circuit/vk/vk \
  -o /circuit/proof \
  -t evm
```

This creates:
- `target/proof/proof` - The ZK proof
- `target/proof/public_inputs` - Public inputs (artifactHash, repoHash, commitSha)

## Step 8: Verify Locally (Optional)

```bash
docker run --rm -v $(pwd)/target:/circuit bb:3.0.3 \
  verify \
  -k /circuit/vk/vk \
  -p /circuit/proof/proof \
  -i /circuit/proof/public_inputs \
  -t evm
```

Should output: `Proof verified successfully`

## Step 9: Submit to Verifier

You now have:
- `target/proof/proof` - Raw proof bytes
- `target/proof/public_inputs` - 84 field elements (bytes32[])

Format for on-chain submission:

```javascript
const proof = fs.readFileSync('target/proof/proof');
const inputsRaw = fs.readFileSync('target/proof/public_inputs');

// Convert inputs to bytes32 array
const publicInputs = [];
for (let i = 0; i < inputsRaw.length; i += 32) {
  publicInputs.push('0x' + inputsRaw.slice(i, i + 32).toString('hex'));
}

// Call verifier contract
await verifier.verify(proof, publicInputs);
```

## Explaining Your Workflow to Verifiers

When submitting a proof, include:

1. **Repo name** - So verifier can audit if they want
2. **What the artifact represents** - E.g., "SHA-256 of tweet content"
3. **Why they should trust it** - Template used, what secrets do, etc.

If using a custom workflow, be prepared to walk through the YAML.

## Troubleshooting

### "witness generation failed"
- Check your bundle.json is valid
- Ensure it's a Sigstore bundle (not just any attestation)

### "proof generation failed"
- Ensure bb Docker image is built
- Check you have enough memory (needs ~2GB)

### "proof verification failed on-chain"
- Verify locally first
- Check proof/inputs encoding matches contract expectations
