# GroupAuth Cross-Attestation Demo Report

**Date:** 2026-02-09
**Network:** Base mainnet (chain 8453)

## Summary

Demonstrated end-to-end interoperability between two different trusted execution environments — **GitHub Actions** (Sigstore attestations + ZK proofs) and **Dstack TEE** (Phala Cloud KMS signature chains) — sharing a group secret through a single smart contract.

A Dstack TEE agent running on Phala Cloud registered itself, then automatically detected and onboarded a GitHub-attested node within one block (~2 seconds).

## Deployed Contracts

All contracts verified on Basescan.

| Contract | Address | Deploy TX |
|----------|---------|-----------|
| ZKTranscriptLib | [`0xebdf63...`](https://basescan.org/address/0xebdf63eef3fad903a495fbe2d8ea087da12ac6ab) | [`0x306745...`](https://basescan.org/tx/0x306745b43934046b075060e75037351fe627e7b3e7b4411d91b04700129dbf7f) |
| HonkVerifier | [`0xd317A5...`](https://basescan.org/address/0xd317A58C478a18CA71BfC60Aab85538aB28b98ab) | [`0x91e4ca...`](https://basescan.org/tx/0x91e4ca70c1c628885922428097a0de8467126ed846371e8b265a014c08dfc85c) |
| SigstoreVerifier | [`0x904Ae9...`](https://basescan.org/address/0x904Ae91989C4C96F2f51f1F8c9eF65C3730b3d8d) | [`0xc20a2e...`](https://basescan.org/tx/0xc20a2edb2d93209d8ee99c477d76ca2ba6e5ef65bf39f803086e258282cbbb3f) |
| **GroupAuth** | [`0x0Af922...`](https://basescan.org/address/0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725) | [`0x72ba18...`](https://basescan.org/tx/0x72ba187ced6d92bdb17a1b4fa051a06978498ff9bc27d5e4ddabe298d49e5b8f) |

## Event Timeline

### 1. Owner adds allowed code IDs

Two types of approved code — a GitHub commit SHA and a Dstack CVM app ID:

| Code ID | Type | TX |
|---------|------|----|
| `4f540ac7...` (commit SHA) | GitHub workflow | [`0xa04f93...`](https://basescan.org/tx/0xa04f9318572318af6d6e4ec07f6a06c241dc7184881ba734fc027f3e04351fcc) |
| `7385b203...` (CVM app ID) | Dstack TEE | [`0x26c376...`](https://basescan.org/tx/0x26c3767983c0f58c5a14a98fd09c9a21ad4f9f282e16819dfbcc8a0679f2576c) |

### 2. Dstack TEE registers via KMS signature chain

The TEE agent on Phala Cloud derived a key from Dstack KMS, built a signature chain proof (app signature → KMS signature → root), and called `registerDstack()`.

| Field | Value |
|-------|-------|
| **memberId** | `0x66a87d520c4776df56fc82410a72117cdf2605a397d2c4355933bc070ca3ba02` |
| **codeId** | `0x7385b203510cc6735e512ca776ad27c37a52d249` (CVM app ID) |
| **KMS root** | `0xd5BDeB037F237Baac161EA37999B6aA37f7f4C77` (Phala production) |
| **Block** | 41,947,074 |
| **TX** | [`0xb86115...`](https://basescan.org/tx/0xb86115f2ba9ffb2bdb0ddd8fed20e1968105a9cf39cce481a7f5c693e5e53d3a) |

**Verification path:** The contract verified the KMS signature chain — `derivedKey` was signed by `appKey`, `appKey` was signed by `kmsRoot` — confirming the derived key belongs to CVM `7385b203...` running on Phala's production KMS.

### 3. GitHub node registers via ZK proof

A ZK proof of a Sigstore attestation was submitted. The proof verifies the entire certificate chain (Sigstore root CA → intermediate → leaf) and extracts the commit SHA.

| Field | Value |
|-------|-------|
| **memberId** | `0x41d1312a747f9d3664f09a8c417de8f63a77a6d35a5cf1b266310aad1adc782f` |
| **codeId** | `0x4f540ac7723fa900c0078eca8e52b3cb0c0a3f13` (commit SHA) |
| **Proof size** | 10,560 bytes |
| **Gas used** | 3,209,839 |
| **Block** | 41,947,709 |
| **TX** | [`0x4d1477...`](https://basescan.org/tx/0x4d1477454c61be22232dc93c3fb60c571f3155474a6ef014dbbe55b608993d8c) |

**Verification path:** The HonkVerifier validated the ZK proof on-chain. The SigstoreVerifier decoded the public inputs to extract `commitSha`, `artifactHash`, and `repoHash`. The GroupAuth contract checked `commitSha` against the allowed code list.

### 4. TEE auto-onboards GitHub node (the interop moment)

The Dstack TEE agent detected the `MemberRegistered` event and posted the group secret for the new GitHub member — **one block later**.

| Field | Value |
|-------|-------|
| **From** | `0x66a87d52...` (Dstack TEE) |
| **To** | `0x41d1312a...` (GitHub node) |
| **Payload** | `groupauth-demo-secret-v1` |
| **Block** | 41,947,713 (4 blocks / ~8s after registration) |
| **TX** | [`0x87e7e6...`](https://basescan.org/tx/0x87e7e6b5a2311d3d4f3948514954a7618af5d188930039ea7e2b951e9ae66664) |

### 5. GitHub node reads the group secret

```
getOnboarding(0x41d1312a...) →
  fromMember: 0x66a87d52...  (Dstack TEE)
  payload: "groupauth-demo-secret-v1"
```

The GitHub runner now has the group secret, delivered by a TEE it never directly communicated with. Trust was mediated entirely by the smart contract verifying both attestation types.

## What was proven

1. **Sigstore ZK proofs and Dstack KMS proofs coexist** on the same contract — different verification logic, same membership primitive
2. **Automatic cross-attestation onboarding** — no human intervention between GitHub registration and TEE response
3. **On-chain verification of both paths** — the HonkVerifier checked the ZK proof (~3.2M gas), the Dstack verifier checked the KMS signature chain (~500K gas)
4. **The group secret pattern works** — existing members post encrypted payloads for new members, enabling key distribution without direct communication

## Infrastructure

| Component | Details |
|-----------|---------|
| **TEE agent** | Phala Cloud CVM `7385b203...`, phala KMS, `dstack-pha-prod7` |
| **Agent health** | [7385b2...8080.dstack-pha-prod7.phala.network](https://7385b203510cc6735e512ca776ad27c37a52d249-8080.dstack-pha-prod7.phala.network/) |
| **Agent image** | `ghcr.io/amiller/groupauth-agent:v4` |
| **ZK circuit** | Noir + UltraHonk (nargo 1.0.0-beta.17, bb v3.0.3) |
| **Contract source** | [`GroupAuth.sol`](../contracts/examples/GroupAuth.sol) |
| **Integration tests** | 21 unit tests + 3 cross-attestation scenarios (GitHub↔GitHub, GitHub↔Dstack, Dstack↔GitHub) |

## Source code

- Contract: [`contracts/examples/GroupAuth.sol`](../contracts/examples/GroupAuth.sol)
- TEE agent: [`agent/app.py`](../agent/app.py)
- Unit tests: [`contracts/test/GroupAuth.t.sol`](../contracts/test/GroupAuth.t.sol)
- Integration tests: [`contracts/test_groupauth_integration.py`](../contracts/test_groupauth_integration.py)
- Deployment guide: [`docs/groupauth-deployment.md`](groupauth-deployment.md)
