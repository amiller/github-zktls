# GroupAuth On-Chain Experiment Report

**Date:** 2026-02-10
**Network:** Base mainnet (chain 8453)
**Contract version:** v2 (with proof replay protection)

## Summary

End-to-end demonstration of cross-attestation between a **Dstack TEE** (Phala Cloud) and a **GitHub-attested node** (Sigstore ZK proof), coordinated through a single smart contract on Base mainnet.

The TEE agent registered itself, a GitHub node registered via ZK proof, and the TEE automatically detected and onboarded the GitHub node with the group secret — all within 6 seconds on-chain.

## Contract Deployment

GroupAuth v2 reuses the existing HonkVerifier and SigstoreVerifier from the v1 deployment. Only GroupAuth itself was redeployed with the proof replay fix (ownership signature binding).

| Contract | Address | Notes |
|----------|---------|-------|
| HonkVerifier | [`0xd317A5...`](https://basescan.org/address/0xd317A58C478a18CA71BfC60Aab85538aB28b98ab) | ZK proof verification (UltraHonk) |
| SigstoreVerifier | [`0x904Ae9...`](https://basescan.org/address/0x904Ae91989C4C96F2f51f1F8c9eF65C3730b3d8d) | Decodes Sigstore attestation from proof |
| **GroupAuth v2** | [`0xdd29de...`](https://basescan.org/address/0xdd29de730b99b876f21f3ab5dafba6711ff2c6ac) | Peer network contract |

Deploy TX: [`0x2a386a...`](https://basescan.org/tx/0x2a386a527939b58384475d3805ed98aab9b2204bc47c64d161ce922e21f7d13b)

### Changes from v1

`registerGitHub` now requires an **ownership signature** — the caller must sign `keccak256(proof)` with the private key corresponding to `compressedPubkey`. This prevents proof replay: the same ZK proof can register multiple nodes, but each node must prove control of its own key.

`registerDstack` now extracts `pubkey` from the `DstackProof.derivedCompressedPubkey` field instead of accepting it as a separate parameter.

## Event Timeline

All times UTC, 2026-02-10.

### Step 0: Add allowed code IDs

| Code ID | Type | TX |
|---------|------|----|
| `0x4f540ac7723f...` | GitHub commit SHA | [`0xa01166...`](https://basescan.org/tx/0xa01166b256704eaca52a3ea2991d215f6934bd291842fd5c98843faffe036c7d) |
| `0x7385b203510c...` | Dstack CVM app ID | [`0x752c88...`](https://basescan.org/tx/0x752c889370f8e1421e6037e49481de09e2a3a68ee18c58b7245f9a5461ebccef) |

### Step 1: Dstack TEE registers (02:27:09 UTC)

The TEE agent on Phala Cloud derived a secp256k1 key from Dstack KMS at path `/groupauth`, built a 3-level signature chain (derived → app → KMS root), and called `registerDstack()`.

| Field | Value |
|-------|-------|
| **memberId** | `0x66a87d520c4776df56fc82410a72117cdf2605a397d2c4355933bc070ca3ba02` |
| **codeId** | `0x7385b203510cc6735e512ca776ad27c37a52d249` (CVM app ID) |
| **KMS root** | `0xd5BDeB037F237Baac161EA37999B6aA37f7f4C77` (Phala production, on Base) |
| **Pubkey** | `03ce2e98b0a5e06fd450f1529a835f15e01aabc75bf72a920453cebcc9f231e85b` |
| **Gas** | 189,669 |
| **Block** | 41,950,541 |
| **TX** | [`0xa7f104...`](https://basescan.org/tx/0xa7f104eb93170fd5ed15a62cdd7ce21800a64e37a4fccae414c7214a7be6b7c2) |

**Verification path:** Contract verifies KMS signature chain: `derivedKey` signed by `appKey`, `appKey` signed by `kmsRoot`. Also verifies derived key signed a challenge message (EIP-191 prefix).

### Step 2: GitHub node registers via ZK proof (02:32:21 UTC)

A Sigstore attestation ZK proof was submitted with an ownership signature binding the proof to a fresh compressed pubkey.

| Field | Value |
|-------|-------|
| **memberId** | `0x4cd1d4e77e266ac625c3e041688fe1291b28dba62fbd0e9cbd67b370270cda89` |
| **codeId** | `0x4f540ac7723fa900c0078eca8e52b3cb0c0a3f13` (commit SHA) |
| **Pubkey** | `0206e9befd5a8e015c1897da94041b04bb5c5578b84e9be6e18e9e2300262762d5` |
| **Proof size** | 10,560 bytes (UltraHonk) |
| **Gas** | 3,198,196 |
| **Block** | 41,950,697 |
| **TX** | [`0x954cf5...`](https://basescan.org/tx/0x954cf5eae65643dd97066505886e163972e1840919a28e4489559c47ca6951a4) |

**Verification path:** HonkVerifier validates ZK proof on-chain (~3.1M gas). SigstoreVerifier decodes public inputs to extract `commitSha`. GroupAuth checks `commitSha` against allowed code list, then verifies ownership signature (`ecrecover` on `keccak256(proof)` matches `compressedPubkey`).

### Step 3: TEE auto-onboards GitHub node (02:32:27 UTC)

The TEE agent detected the `MemberRegistered` event and posted the group secret — **6 seconds (3 blocks) after registration**.

| Field | Value |
|-------|-------|
| **From** | `0x66a87d52...` (Dstack TEE) |
| **To** | `0x4cd1d4e7...` (GitHub node) |
| **Payload** | `groupauth-demo-secret-v1` (hex: `67726f7570617574682d64656d6f2d7365637265742d7631`) |
| **Gas** | 96,445 |
| **Block** | 41,950,700 |
| **TX** | [`0xc2f716...`](https://basescan.org/tx/0xc2f7160f1b4af004e6d3be7530b3d2ad08bb3963c65658d183e372c0ceb9946d) |

### Step 4: GitHub node reads the group secret

```
getOnboarding(0x4cd1d4e7...) →
  [(fromMember: 0x66a87d52..., payload: "groupauth-demo-secret-v1")]
```

The GitHub node now has the group secret, delivered by a TEE it never directly communicated with. Trust was mediated entirely by the smart contract verifying both attestation types.

## Gas Analysis

| Operation | Gas | Cost (at ~0.003 gwei) | What it does |
|-----------|-----|----------------------|--------------|
| `registerDstack` | 189,669 | ~$0.001 | 3x `ecrecover` + compressed pubkey recovery |
| `registerGitHub` | 3,198,196 | ~$0.024 | UltraHonk ZK proof verification + `ecrecover` |
| `onboard` | 96,445 | ~$0.001 | Store encrypted payload (SSTORE) |
| **Total** | **3,484,310** | **~$0.026** | Full TEE + GitHub + onboard cycle |

The ZK proof verification dominates at 92% of total gas. This is the UltraHonk verifier executing ~3M gas of elliptic curve arithmetic on-chain. The proof verifies the entire Sigstore certificate chain (root CA → intermediate → leaf), ECDSA P-256 signatures, and SHA-256 hashes inside a single SNARK.

For comparison, `registerDstack` only needs `ecrecover` (secp256k1 precompile, ~3000 gas each) — no ZK math.

### Alternative: native P-256 verification (no ZK)

Sigstore uses P-256 (NIST) ECDSA signatures. Instead of proving the certificate chain inside a ZK circuit, you could verify P-256 signatures directly on-chain:

| Approach | Gas per P-256 sig | 2 sigs + parsing | vs our ZK |
|----------|-------------------|------------------|-----------|
| **RIP-7212 precompile** (Base has it) | ~100k | ~300-400k | **~10x cheaper** |
| **Solidity P-256 library** (no precompile) | ~1-2M | ~2-4M | Comparable or worse |
| **Our UltraHonk ZK proof** | n/a (fixed cost) | 3,198,196 | Baseline |

The RIP-7212 precompile makes native P-256 verification significantly cheaper. The tradeoffs:

- **ZK advantage**: constant-size proof regardless of circuit complexity, privacy (can hide repo/commit), composability (add checks to the circuit without changing on-chain verifier)
- **Native P-256 advantage**: ~10x cheaper gas, simpler toolchain (no Noir/barretenberg), no prover infrastructure needed
- **Both**: the on-chain calldata is similar size — the ZK proof is 10.5 KB, while raw Sigstore attestation data (certs + signatures) is comparable

For the GroupAuth use case where attestation contents are public anyway, native P-256 via RIP-7212 would be the more gas-efficient path. The ZK approach becomes worthwhile when you need to hide attestation details or when the verification logic grows more complex than two signature checks.

## Local Test Results

Before the on-chain experiment, all tests passed locally:

- **22 forge unit tests** — `forge test --match-contract GroupAuthTest` (includes proof replay protection tests)
- **3 integration scenarios** on Anvil + Dstack simulator:
  - GitHub → GitHub onboarding
  - GitHub → Dstack onboarding
  - Dstack → GitHub → GitHub chain onboarding

## Infrastructure

| Component | Details |
|-----------|---------|
| **TEE agent** | Phala Cloud CVM `app_7385b203...`, phala KMS, `dstack-pha-prod7` |
| **Agent health** | [7385b2...8080.dstack-pha-prod7.phala.network](https://7385b203510cc6735e512ca776ad27c37a52d249-8080.dstack-pha-prod7.phala.network/) |
| **Agent image** | `ghcr.io/amiller/groupauth-agent:v5@sha256:787570bead4d...` |
| **ZK circuit** | Noir + UltraHonk (nargo 1.0.0-beta.17, bb v3.0.3) |
| **Proof** | 10,560 bytes, 84 public inputs |

## What Was Proven

1. **Cross-attestation works on mainnet** — Sigstore ZK proofs and Dstack KMS proofs coexist on the same contract, using the same membership primitive (`keccak256(compressedPubkey)`)

2. **Proof replay protection works** — the ownership signature binds each ZK proof to a specific pubkey, so the same Sigstore attestation can register multiple nodes but each must prove key control

3. **Automatic onboarding works** — the TEE agent detected the GitHub registration event and delivered the group secret in 6 seconds with zero human intervention

4. **The gas cost is practical** — full cycle costs ~$0.03 on Base L2. The 3.2M gas ZK verification is the bottleneck; Dstack registration is 17x cheaper

5. **Two trust roots verified independently** — GitHub's trust comes from Sigstore's certificate transparency + ZK proof; Dstack's trust comes from Phala's on-chain KMS (`0xd5BDeB0...` on Base mainnet). Neither trusts the other's attestation mechanism — the smart contract is the neutral meeting point.

## Source Code

- Contract: [`contracts/examples/GroupAuth.sol`](../contracts/examples/GroupAuth.sol)
- TEE agent: [`agent/app.py`](../agent/app.py)
- Unit tests: [`contracts/test/GroupAuth.t.sol`](../contracts/test/GroupAuth.t.sol)
- Integration tests: [`contracts/test_groupauth_integration.py`](../contracts/test_groupauth_integration.py)
- Deploy script: [`contracts/script/DeployGroupAuth.s.sol`](../contracts/script/DeployGroupAuth.s.sol)
