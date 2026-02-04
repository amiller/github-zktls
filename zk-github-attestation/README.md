# ZK GitHub Attestation Verifier

Verify GitHub Actions Sigstore attestations in zero-knowledge, enabling trustless on-chain verification.

## Architecture

```
┌─────────────────────┐
│  Sigstore Bundle    │  (from GitHub Actions attest-build-provenance)
│  - DSSE envelope    │
│  - X.509 certificate│
│  - ECDSA signature  │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  Witness Generator  │  js/src/index.ts
│  - Parse bundle     │
│  - Compute PAE      │
│  - Extract pubkey   │
│  - Format for Noir  │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  Noir Circuit       │  circuits/src/main.nr
│  - Verify ECDSA sig │
│  - Verify cert chain│
│  - Extract claims   │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  On-Chain Verifier  │  (Groth16/UltraPlonk)
│  - Verify ZK proof  │
│  - Mint NFT / etc   │
└─────────────────────┘
```

## Components

### 1. Witness Generator (`js/`)

TypeScript library that parses Sigstore bundles and generates circuit inputs.

```typescript
import { generateCircuitInputs, toProverToml } from './src/index.js'

const bundle = JSON.parse(fs.readFileSync('attestation-bundle.json'))
const inputs = generateCircuitInputs(bundle)
fs.writeFileSync('Prover.toml', toProverToml(inputs))
```

**Input:** Sigstore bundle JSON (from `gh api /repos/.../attestations/...`)

**Output:**
- `pae_message`: DSSE Pre-Authentication Encoding, padded to 2048 bytes
- `pae_message_len`: Actual length of PAE message
- `signature`: ECDSA signature (64 bytes, r||s concatenated)
- `leaf_pubkey_x`, `leaf_pubkey_y`: Leaf certificate P-256 public key
- `artifact_hash`: SHA-256 of attested artifact (public)
- `repo_hash`: SHA-256 of repository name (public)
- `commit_sha`: Git commit (20 bytes, public)

### 2. Noir Circuit (`circuits/`)

ZK circuit that verifies attestation validity.

**Verification Steps:**
1. **Leaf Signature (P-256)**: Verify DSSE envelope signature using leaf cert pubkey
2. **Certificate Chain (P-384)**: Verify leaf cert signed by Fulcio intermediate CA
3. **Claim Extraction**: Parse X.509 extensions to get OIDC claims
4. **Public Input Binding**: Ensure extracted claims match public inputs

**Public Inputs (revealed on-chain):**
- `artifact_hash`: The artifact that was attested
- `repo_hash`: Which repository produced it
- `commit_sha`: Which commit it was built from

### 3. Trust Chain

```
Sigstore Root CA (offline)
    └── Fulcio Intermediate CA (P-384, hardcoded)
            └── Leaf Certificate (P-256, 10-min validity)
                    └── Signs DSSE Envelope
```

Fulcio intermediate public key is hardcoded in the circuit:
- See `docs/fulcio-intermediate-ca.md` for key details
- Valid: Apr 2022 - Oct 2031

## Usage

### Generate Witness

```bash
cd js
npm install
npm run build

# Generate inputs from attestation bundle
node -e "
const { generateCircuitInputs, toProverToml } = require('./dist/index.js')
const bundle = require('../docs/examples/sample-attestation-bundle.json')
const inputs = generateCircuitInputs(bundle)
console.log(toProverToml(inputs))
" > circuits/Prover.toml
```

### Compile & Prove

```bash
cd circuits
nargo compile
nargo prove
```

### Verify

```bash
nargo verify
```

## Dependencies

### Witness Generator
- `@noble/curves` - ECDSA signature verification (for testing)
- Node.js 18+

### Noir Circuit
- Noir 1.0.0-beta.5+
- `noir-lang/sha256` v0.1.2 (variable-length SHA-256)
- For P-384 cert chain: `zkpassport/noir-ecdsa`, `zkpassport/noir-bignum`

## File Structure

```
zk-github-attestation/
├── README.md
├── js/                          # Witness generator
│   ├── package.json
│   ├── tsconfig.json
│   └── src/
│       ├── index.ts             # Main library
│       └── test.ts              # Test with sample bundle
├── circuits/                    # Noir circuit
│   ├── Nargo.toml
│   └── src/
│       └── main.nr              # Main circuit
└── docs/
    ├── fulcio-intermediate-ca.md
    └── examples/
        ├── sample-attestation-bundle.json
        └── attestation-analysis.md
```

## Security Considerations

### What We Trust
1. **Fulcio CA** - Issues certificates honestly based on OIDC
2. **GitHub OIDC** - Issues tokens honestly for workflow runs
3. **ZK Proof System** - Cryptographically sound

### What We Don't Trust
- GitHub API at verification time (we verify signatures cryptographically)
- Any oracle or off-chain service
- The prover (they can't forge proofs)

## TODO

- [ ] Full certificate chain verification (P-384)
- [ ] X.509 extension parsing in circuit
- [ ] PAE payload parsing to verify artifact hash
- [ ] Solidity verifier contract
- [ ] Gas optimization

## References

- [Sigstore Bundle Spec](https://github.com/sigstore/protobuf-specs)
- [Fulcio Certificate Spec](https://github.com/sigstore/fulcio/blob/main/docs/certificate-specification.md)
- [DSSE Spec](https://github.com/secure-systems-lab/dsse)
- [zkEmail Noir](https://github.com/zkemail/zk-email-verify)
- [zkPassport Circuits](https://github.com/zkpassport/circuits)
