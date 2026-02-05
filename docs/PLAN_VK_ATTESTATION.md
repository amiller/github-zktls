# Plan: Attested VK Generation

## Status: ABANDONED

**Reason**: UltraHonk uses a universal trusted setup (Powers of Tau), not per-circuit ceremonies. VK generation is **deterministic** - same circuit + tooling = same VK.

Sigstore attestation adds no value here. Verification is simply: recompile with same versions, compare output.

---

## Original Goal (for reference)

Make the trusted setup (VK generation) auditable via GitHub Actions + Sigstore attestation. Anyone can verify that the on-chain verifier was generated from a specific circuit at a specific commit.

## Why This Was Unnecessary

1. VK generation is deterministic, not a "trusted setup"
2. Anyone can verify by recompiling: `nargo compile && bb write_vk && bb write_solidity_verifier`
3. Reproducibility IS the trust model - no attestation needed

## Simpler Verification Story

```bash
# Clone repo, install nargo 1.0.0-beta.17 and bb v3.0.3
cd zk-proof/circuits
nargo compile
bb write_vk -b target/zk_github_attestation.json -o target/vk -t evm
bb write_solidity_verifier -k target/vk/vk -o HonkVerifier.sol -t evm
# Compare HonkVerifier.sol to deployed contract source
```

---

## Original Proposed Solution (archived)

### GitHub Action: `generate-vk.yml`

Triggers:
- Manual dispatch
- Changes to `zk-proof/circuits/`

Steps:
1. **Compile circuit**: `nargo compile`
2. **Generate VK**: `bb write_vk -b target/circuit.json -o vk`
3. **Generate Solidity verifier**: `bb write_contract -k vk -o HonkVerifier.sol`
4. **Create attestation subject**: JSON with circuit hash, VK hash, commit SHA
5. **Attest with Sigstore**: `gh attestation create` on the subject JSON
6. **Upload artifacts**: VK, HonkVerifier.sol, attestation bundle

### Attestation Subject

```json
{
  "type": "zk-trusted-setup",
  "circuit_hash": "<sha256 of compiled circuit JSON>",
  "vk_hash": "<sha256 of verification key>",
  "verifier_hash": "<sha256 of HonkVerifier.sol>",
  "nargo_version": "1.0.0-beta.17",
  "bb_version": "v3.0.3",
  "commit": "<git SHA>"
}
```

### Verification Flow

Anyone can verify:
1. Fetch attestation from GitHub
2. Check Sigstore signature (proves GitHub Actions ran this)
3. Recompile circuit locally, compare hashes
4. Verify deployed contract matches attested HonkVerifier.sol

### On-Chain Trust Anchor (Optional)

Could store `vk_hash` on-chain in the verifier contract:
```solidity
bytes32 public constant VK_HASH = 0x...;
```

This creates a binding: anyone can verify the contract code matches the attested VK.

## Implementation Steps

1. [x] Create `generate-vk.yml` workflow
2. [x] Add `bb write_solidity_verifier` to generate Solidity
3. [x] Create attestation subject JSON
4. [x] Test attestation flow - https://github.com/amiller/github-zktls/attestations/18208021
5. [ ] Update README with verification instructions
6. [ ] (Optional) Add VK_HASH constant to contract

## Benefits

- **Transparency**: Anyone can see exactly how VK was generated
- **Reproducibility**: Same circuit → same VK (deterministic)
- **Auditability**: Sigstore provides tamper-proof log
- **Trust minimization**: Don't trust us, verify the attestation

## Questions to Resolve

1. Should we attest the Docker image too? (for prover reproducibility)
2. Store VK in repo or just as workflow artifact?
3. How to handle circuit upgrades? (version the attestation subject)
