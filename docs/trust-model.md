# Trust Model

This document explains what the ZK proof guarantees and what it doesn't.

## The Certificate Chain

```
Sigstore Root CA
    │ (offline, 10-year validity)
    ▼
Fulcio Intermediate CA  ← HARDCODED IN CIRCUIT (P-384)
    │ (online, signs leaf certs)
    ▼
Leaf Certificate        ← VERIFIED IN CIRCUIT (P-256)
    │ (ephemeral, ~10 minute validity)
    │ Contains: repo, commit, workflow info (OIDC claims)
    ▼
Attestation Signature   ← VERIFIED IN CIRCUIT
    │
    ▼
Artifact Hash           ← EXTRACTED AS PUBLIC INPUT
```

## What the Proof Guarantees

### ✅ Cryptographic Guarantees

1. **Valid Sigstore Attestation**
   - The attestation was signed by a valid Fulcio leaf certificate
   - The leaf certificate was signed by the Fulcio intermediate CA
   - The intermediate CA's public key matches the hardcoded value

2. **Correct Claim Extraction**
   - `repoHash` comes from the certificate's OIDC extension (OID 1.3.6.1.4.1.57264.1.5)
   - `commitSha` comes from the certificate's OIDC extension (OID 1.3.6.1.4.1.57264.1.3)
   - `artifactHash` comes from the DSSE envelope payload

3. **Immutable Binding**
   - These three values are cryptographically bound together
   - You cannot mix-and-match claims from different attestations

### ❌ What the Proof Does NOT Guarantee

1. **Workflow Behavior**
   - The proof doesn't say what the workflow did
   - It only says *which* workflow (repo + commit) ran

2. **Artifact Interpretation**
   - The proof doesn't say what the artifact *means*
   - Just its hash

3. **Repo Integrity**
   - The proof doesn't guarantee the repo hasn't been compromised
   - The prover controls their repo

## Trust Assumptions

### You Trust: Sigstore Infrastructure

The circuit hardcodes the Fulcio intermediate CA public key:
- **Key**: P-384 ECDSA
- **Validity**: April 2022 - October 2031
- **Source**: [Sigstore TUF root](https://tuf-repo-cdn.sigstore.dev/)

If Sigstore is compromised, proofs become meaningless. This is the root of trust.

### You Trust: GitHub OIDC

Fulcio issues certificates based on GitHub's OIDC tokens. You trust:
- GitHub correctly identifies the repo/commit in OIDC tokens
- GitHub Actions runs the workflow at that commit

### You Trust: The Circuit

The circuit code extracts claims correctly. This is auditable:
- `circuits/src/main.nr` - Main circuit logic
- Uses well-audited libraries (zkpassport's ecdsa, bignum)

### You Evaluate: The Workflow

This is the verifier's responsibility:
- Does the workflow do what the prover claims?
- Could the prover manipulate the artifact?
- Are dependencies pinned?

## Attack Scenarios

### Malicious Prover

A prover could:
- Write a workflow that produces fake artifacts ✓ (verifier must audit)
- Modify their workflow after getting a proof ✗ (commit is pinned)
- Claim someone else's repo ✗ (they can't get Sigstore to sign it)
- Create a proof with fake claims ✗ (cryptographic verification)

### Compromised Repo

If a prover's repo is compromised:
- Attacker could run a malicious workflow
- Proof would be valid for the malicious commit
- Verifier should check commit history / timing

### Sigstore Compromise

If Fulcio is compromised:
- Attacker could get certs for any repo/commit
- All proofs become untrustworthy
- This is the weakest link (but Sigstore has strong security practices)

## Privacy Considerations

### What's Public (in the proof)

- `artifactHash` - Always revealed
- `repoHash` - Hash is revealed, but not the repo name directly
- `commitSha` - Always revealed

### What's Private

- Actual repo name (unless prover discloses)
- Full certificate contents
- Attestation payload details

### Prover Privacy

A prover can:
- Keep their repo private (verifier sees only the hash)
- Disclose repo name only to verifiers who need to audit
- Use a dedicated repo for sensitive proofs

## Future Considerations

### Circuit Updates

The Fulcio intermediate CA expires in 2031. Before then:
- New circuit with updated key
- New verifier contract deployment
- Migration path for existing integrations

### Selective Disclosure

Future versions could allow:
- Proving only specific claims
- Multiple workflows in one proof
- Recursive proofs for workflow composition
