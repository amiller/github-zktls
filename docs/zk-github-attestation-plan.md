# ZK GitHub Attestation Verifier

## Goal
Verify GitHub Actions attestations on-chain via ZK proof, enabling trustless NFT issuance for proofs like "user has X GitHub followers" or "user's PayPal balance is Y".

## Architecture Overview

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  GitHub Actions │────▶│  Sigstore Bundle │────▶│   ZK Prover     │
│  (proof workflow)│     │  (attestation)   │     │   (Noir/Circom) │
└─────────────────┘     └──────────────────┘     └────────┬────────┘
                                                          │
                                                          ▼
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  NFT Contract   │◀────│  Groth16 Proof   │◀────│  ZK Circuit     │
│  (mint on verify)│     │  (~200k gas)     │     │                 │
└─────────────────┘     └──────────────────┘     └─────────────────┘
```

## Sigstore Bundle Contents

When you run `actions/attest-build-provenance`, GitHub produces a bundle containing:

1. **DSSE Envelope** - Dead Simple Signing Envelope
   - `payloadType`: `application/vnd.in-toto+json`
   - `payload`: base64-encoded in-toto statement
   - `signatures`: array of {keyid, sig}

2. **In-Toto Statement**
   - `subject`: [{name, digest: {sha256}}] - the artifact(s)
   - `predicateType`: `https://slsa.dev/provenance/v1`
   - `predicate`: SLSA provenance with builder, source, build metadata

3. **Verification Material**
   - `certificate`: X.509 cert (PEM) with OIDC claims in extensions
   - `transparencyLogEntries`: Rekor inclusion proof

4. **Certificate OIDC Extensions** (OID 1.3.6.1.4.1.57264.1.*)
   - `.1` - OIDC Issuer (https://token.actions.githubusercontent.com)
   - `.2` - GitHub Workflow Trigger
   - `.3` - GitHub Workflow SHA
   - `.4` - GitHub Workflow Name
   - `.5` - GitHub Workflow Repository
   - `.6` - GitHub Workflow Ref

## What We Need to Prove in ZK

### Public Inputs (revealed on-chain)
- `artifactHash`: sha256 of the proof artifact
- `repoHash`: hash of expected repository (e.g., "amiller/github-zktls")
- `workflowHash`: hash of expected workflow path
- `commitSha`: the git commit (20 bytes)
- `timestamp`: attestation time (for freshness)

### Private Inputs (witness)
- Full Sigstore bundle JSON
- Certificate chain (leaf + intermediate)
- ECDSA signatures

### Circuit Logic
1. Parse DSSE envelope, extract payload and signature
2. Verify ECDSA P-256 signature over payload
3. Parse X.509 certificate, extract public key and OIDC extensions
4. Verify certificate signature against Fulcio intermediate CA
5. Check intermediate CA against hardcoded root public key
6. Extract and verify: repo, workflow, commit SHA match public inputs
7. Verify artifact hash in in-toto statement matches public input

## Reference: zkEmail Architecture

zkEmail verifies DKIM signatures on emails. Similar structure:

| zkEmail | Our Project |
|---------|-------------|
| Email headers | DSSE envelope |
| DKIM signature (RSA) | Sigstore signature (ECDSA P-256) |
| DNS public key | Fulcio certificate chain |
| Email body hash | Artifact hash |
| Selector/domain | Repository/workflow |

Key zkEmail components to reference:
- `packages/circuits/` - Circom circuits
- `packages/helpers/` - TypeScript for parsing emails
- `packages/contracts/` - Solidity verifiers

## Implementation Phases

### Phase 1: Collect Sample Data
- [ ] Add `actions/attest-build-provenance` to a workflow
- [ ] Download and inspect the bundle format
- [ ] Document exact byte layout of certificate extensions
- [ ] Identify Fulcio root/intermediate public keys

### Phase 2: TypeScript Helpers
- [ ] Bundle parser (extract DSSE, certs, signatures)
- [ ] Certificate parser (extract OIDC claims)
- [ ] Witness generator for ZK circuit

### Phase 3: ZK Circuit (Noir preferred)
- [ ] ECDSA P-256 signature verification (use stdlib)
- [ ] X.509 certificate parsing (custom)
- [ ] OIDC extension extraction
- [ ] Public input computation

### Phase 4: Solidity Verifier
- [ ] Deploy Noir/Groth16 verifier
- [ ] GitHubProofNFT contract
- [ ] Integration tests on testnet

## Technical Decisions

### Noir vs Circom
**Recommendation: Noir**
- Native ECDSA P-256 support (`ecdsa_secp256r1::verify_signature`)
- Cleaner syntax, better developer experience
- Good tooling (nargo, bb)
- Barretenberg backend is production-ready

### Certificate Chain Depth
Options:
1. **Verify full chain** - Most secure, more constraints
2. **Hardcode intermediate** - Simpler, but intermediate rotates
3. **Verify to intermediate only** - Good balance

**Recommendation:** Verify to intermediate, hardcode intermediate public key with governance for rotation.

### Artifact Hash Commitment
Options:
1. **Hash entire artifact** - Simple but proves less
2. **Structured extraction** - Parse certificate.json, prove specific claims
3. **Merkle tree** - Prove specific fields without revealing all

**Recommendation:** Start with (1), evolve to (3) for privacy.

## Trust Assumptions

What we're trusting:
1. **Fulcio CA** - Issues certificates honestly based on OIDC
2. **GitHub OIDC** - Issues tokens honestly for workflow runs
3. **Rekor** - Transparency log is append-only (optional to verify)
4. **ZK proof system** - Cryptographically sound

What we're NOT trusting:
- GitHub API at verification time
- Any oracle or off-chain service
- The prover (they can't forge proofs)

## Open Questions

1. **Certificate rotation** - How often do Fulcio intermediates rotate? Need governance mechanism.

2. **Timestamp verification** - Should we verify Rekor timestamp or just certificate validity period?

3. **Workflow pinning** - Do we verify workflow content hash, or just path? (Path can change between commits)

4. **Privacy** - Should repo/workflow be public inputs or derived privately?

5. **Gas optimization** - Groth16 vs UltraPlonk? L1 vs L2 deployment?

## Resources

- [Sigstore Bundle Spec](https://github.com/sigstore/protobuf-specs)
- [Fulcio Certificate Spec](https://github.com/sigstore/fulcio/blob/main/docs/certificate-specification.md)
- [zkEmail Circuits](https://github.com/zkemail/zk-email-verify)
- [Noir ECDSA](https://noir-lang.org/docs/noir/standard_library/cryptographic_primitives/ecdsa_sig_verification)
- [GitHub Artifact Attestations](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations)
- [In-Toto Attestation Spec](https://github.com/in-toto/attestation)
