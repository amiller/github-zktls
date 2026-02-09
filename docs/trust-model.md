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
   - `commitSha` comes from the certificate's OIDC extension (OID 1.3.6.1.4.1.57264.1.3) — **primary**: pins immutable, auditable code
   - `artifactHash` comes from the DSSE envelope payload
   - `repoHash` comes from the certificate's OIDC extension (OID 1.3.6.1.4.1.57264.1.5) — **informational**: the prover controls their repo, so this is a convenience filter, not a security boundary

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

## Two Ways to Get an Attestation

There are two paths to a Sigstore attestation. They produce the same bundle format and the ZK circuit can't tell them apart.

### Path 1: `actions/attest-build-provenance` (inside GitHub Actions)

The workflow calls the action with a file path. Under the hood:
1. GitHub's OIDC provider issues a token proving "I am repo X at commit Y in run Z"
2. Fulcio exchanges the token for a short-lived leaf certificate with those claims as X.509 extensions
3. The action signs the file, logs the signature to Rekor (Sigstore's transparency log)
4. Result: a Sigstore bundle (DSSE envelope + certificate + Rekor inclusion proof)

This only works inside a GitHub Actions run — that's where the OIDC token comes from.

### Path 2: Direct Sigstore interaction (cosign, sigstore-js, etc.)

Anyone can get a Sigstore certificate. Fulcio supports multiple OIDC providers (GitHub, Google, Microsoft, etc.):
1. Authenticate with `cosign sign-blob` or the Sigstore libraries
2. Fulcio issues a cert based on whatever OIDC identity you present
3. You sign your artifact, it goes to Rekor
4. Result: same format Sigstore bundle

The certificate contains different OIDC claims depending on the provider. A Google-authenticated cert has an email; a GitHub Actions cert has repo, commit, run_id.

Path 1 is just a convenience wrapper around Path 2. Same Sigstore infrastructure, same Fulcio CA, same bundle format.

## What GitHub Provides: Trust vs Convenience

GitHub serves two roles in this system. Conflating them makes the trust model look more GitHub-dependent than it is.

### Trust layer (load-bearing)

These are what the ZK proof actually depends on:

| Component | What it provides | Could be replaced? |
|-----------|-----------------|-------------------|
| **OIDC tokens** | Identity claims (repo, commit, run_id) baked into Fulcio certs | Only by another Sigstore OIDC provider |
| **Runner isolation** | Ephemeral VM — secrets stay in memory, can't be exfiltrated | By any TEE (SGX, Nitro, etc.) |
| **Workflow code at commit** | Auditable execution — verifier reads the YAML at that SHA | By any reproducible build system |

The ZK circuit only touches the Sigstore certificate chain. It verifies that Fulcio signed a cert containing certain claims, and that cert signed a DSSE envelope containing an artifact hash. Nothing else.

### Convenience layer (not load-bearing)

These are useful but invisible to the proof:

| Feature | How we use it | Trust role |
|---------|--------------|------------|
| **Issues** | Trigger workflows, collect user input, display results | None — just UX |
| **Comments** | Message passing (email codes, encrypted submissions) | Transport only — could be any channel |
| **Labels** | Track state (pending, claimed) | None — bookkeeping |
| **`attest-build-provenance` action** | One-line attestation | Convenience wrapper around Sigstore APIs |
| **Artifacts** | Download proofs and bundles | File hosting — could be any storage |

A verifier checking a ZK proof on-chain never sees issues, comments, or labels. They see: `commitSha` (primary — pins auditable code), `artifactHash`, and `repoHash` (informational). Everything else is scaffolding.

### Why this matters

If you're auditing a workflow's trust model, focus on:
1. What OIDC claims end up in the Sigstore certificate?
2. What does the workflow code at that commit actually do?
3. What artifact gets attested?

Ignore: issue formatting, comment templates, label management, notification UX. Those are application code, not trust code.

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

- `commitSha` - Always revealed (primary: pins the exact code that ran)
- `artifactHash` - Always revealed
- `repoHash` - Hash is revealed, but not the repo name directly (informational only)

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
