# Gas & Circuit Analysis

Empirical breakdown of on-chain verification gas costs and circuit constraint
contributions. All measurements taken with nargo 1.0.0-beta.17, barretenberg v3.0.3,
Foundry (Cancun EVM), optimizer_runs=1.

Reproduce with:
```bash
# On-chain gas profile
cd contracts && forge test --match-contract GasProfileTest -vv

# Circuit constraint counts (per-component)
cd zk-proof/benchmarks/<name> && nargo info
```

---

## On-Chain Verification Gas (2,825,166 total)

Measured via `contracts/test/GasProfile.t.sol`. The test contract inherits from
`BaseZKHonkVerifier` and inserts `gasleft()` checkpoints between each verification stage.

| # | Component | Gas | % |
|---|-----------|-----|---|
| 1 | Load VK + parse proof | 227,965 | 8.1% |
| 2 | Fiat-Shamir transcript (keccak256) | 310,881 | 11.0% |
| 3 | Public input delta (100 field muls) | 86,707 | 3.1% |
| 4 | Sumcheck (20 rounds, barycentric eval) | 599,934 | 21.2% |
| 5 | Shplemini (62-point MSM + fold + pairing) | 1,599,679 | 56.6% |

### EVM Precompile Unit Costs

| Precompile | Address | Gas/call | Calls in verifier |
|------------|---------|----------|-------------------|
| MODEXP (field invert) | 0x05 | 1,595 | ~50 (sumcheck + shplemini) |
| ECMUL (scalar mul) | 0x07 | 6,187 | 62 (MSMSize) |
| ECADD (point add) | 0x06 | 355 | 62 |
| ECPAIRING (2 pairs) | 0x08 | 113,581 | 1 |

### Key Constants

```
N            = 2^20 = 1,048,576 gates
LOG_N        = 20
PUBLIC_INPUTS = 100 (84 attestation data + 16 pairing points)
MSMSize      = NUMBER_UNSHIFTED_ZK + LOG_N + LIBRA_COMMITMENTS + 2
             = 37 + 20 + 3 + 2 = 62
Proof size   = 10,560 bytes (330 field elements × 32 bytes)
```

### Scaling

Verification gas scales **O(log N)** — NOT linearly in circuit size or witness size.
Doubling the circuit from 2^20 → 2^21 adds ~1 ECMUL (6.2K) + ~1 sumcheck round (30K)
≈ 36K extra gas (~1.3%).

The 2.83M gas is essentially fixed protocol overhead, dominated by EVM precompile calls
in the Shplemini polynomial commitment check.

### Full Transaction Cost

| Layer | Gas |
|-------|-----|
| HonkVerifier.verify() | 2,827,449 |
| SigstoreVerifier.verify() (wrapper) | 2,834,235 |
| GitHubFaucet.claim() (app logic) | ~120,880 |
| **Full claim transaction** | **~2,950,000** |

---

## Circuit Constraint Breakdown

The ZK circuit verifies a full Sigstore certificate chain: intermediate CA (P-384) →
leaf cert (P-256) → DSSE attestation. Each cryptographic operation contributes a
measurable number of constraints.

Measured via isolated benchmark circuits in `zk-proof/benchmarks/`. Each benchmark
contains a single cryptographic operation compiled independently with `nargo info`.

| Component | Expression Width | ACIR Opcodes | % of circuit |
|-----------|-----------------|--------------|--------------|
| **SHA-384** (1800 bytes, cert TBS) | 198,064 | 650 | **65.2%** |
| **P-384 ECDSA** verify | 66,813 | 255,723 | **22.0%** |
| **SHA-256** (2048 bytes, PAE msg) | 30,839 | 2,560 | **10.1%** |
| SHA-256 (64 bytes, repo name) | 1,730 | 575 | 0.6% |
| P-256 ECDSA verify (blackbox) | 162 | 0 | <0.1% |
| Hex decode + comparisons | — | — | ~2% |
| **Full circuit** | **303,899** | **256,771** | **100%** |

### Interpretation

**SHA-384 dominates at 65%.** This is because:
- SHA-384 operates on 64-bit words → expensive in a ~254-bit prime field circuit
- 1800 bytes of input requires ~14 compression rounds (128-byte blocks)
- The `sha512` library (which implements SHA-384) is constraint-heavy in Noir

**P-384 ECDSA is 22%.** Elliptic curve scalar multiplication over a 384-bit field
requires extensive bignum arithmetic (modular multiplication, inversion, point
addition/doubling).

**SHA-256 (2048 bytes) is 10%.** SHA-256 uses 32-bit words — much cheaper per round
than SHA-384. But 2048 bytes still requires ~32 compression rounds.

**P-256 ECDSA is near-zero in ACIR.** It's a Noir **blackbox function** — the backend
(barretenberg) implements it natively. The 162 expression width is just I/O marshalling.
The real gate contribution is hidden inside the backend.

### What the Full Circuit Does

```
Step 1: SHA-384(leaf_tbs, 1800 bytes)         ← 65% of constraints
Step 2: P-384 ECDSA verify(intermediate_sig)  ← 22% of constraints
Step 3: Extract P-256 pubkey from TBS
Step 4: SHA-256(pae_message, 2048 bytes)       ← 10% of constraints
Step 5: P-256 ECDSA verify(leaf_sig)           ← blackbox (backend-native)
Step 6: Extract & verify commit SHA, repo, artifact hash
Step 7: SHA-256(repo_name, 64 bytes)           ← 0.6% of constraints
```

### Optimization Opportunities

If circuit size reduction is needed:
1. **SHA-384 → SHA-256** — would save ~65% of constraints, but requires Sigstore
   to change their cert signing algorithm (not feasible)
2. **Reduce MAX_TBS_LENGTH** — 1800→1200 bytes could save ~20% of SHA-384 cost
   if certs are consistently smaller
3. **Reduce MAX_PAE_LENGTH** — 2048→1024 bytes saves ~5% of total
4. **Note:** Reducing circuit size has minimal impact on on-chain gas (O(log N))
   but directly reduces prover time and memory

---

## Gas Optimization Experiments

### Experiment 1: Drop ZK (`evm-no-zk`) — 1,016K savings (37.3%)

**Status: Implemented on `packed-inputs` branch**

The UltraHonk verifier includes zero-knowledge overhead via `checkEvalsConsistency`,
which performs 256 MODEXP inversions plus LIBRA commitment processing.
Generating the verifier with `-t evm-no-zk` instead of `-t evm` eliminates this
entirely, plus reduces proof size and MSM point count.

**Measured results** (both using packed 21 public inputs):

| Component | evm (ZK) | evm-no-zk | Savings |
|-----------|----------|-----------|---------|
| Load VK + parse proof | 227,965 | 201,791 | 26,174 |
| Fiat-Shamir transcript | 276,983 | 154,149 | 122,834 |
| Public input delta | 18,451 | 18,451 | 0 |
| Sumcheck (20 rounds) | 599,632 | 543,045 | 56,587 |
| Shplemini (MSM+pairing) | 1,598,994 | 788,082 | 810,912 |
| **TOTAL** | **2,722,025** | **1,705,518** | **1,016,507 (37.3%)** |

Key observations:
- **Shplemini savings (-811K)** dominate: fewer MSM points (58 vs 62), and
  no `checkEvalsConsistency` (256 MODEXP inversions eliminated)
- **Transcript savings (-123K):** smaller proof means less Fiat-Shamir hashing
- **Proof size:** 9,440 bytes (no-ZK) vs 10,560 bytes (ZK) — 1,120 fewer bytes
- **Total savings far exceed initial estimate** (1,016K vs ~450K estimated) because
  the ZK overhead permeates multiple verification stages, not just `checkEvalsConsistency`

Trade-off: Without ZK, a verifier who sees the proof can extract partial witness
information. This is acceptable for public attestation verification where the
witness data (Sigstore certificates) is already public.

### Experiment 2: Pack Public Inputs — 103K savings (3.7%)

**Status: Implemented on `packed-inputs` branch**

The baseline circuit exposes 84 byte-level public inputs (32 + 32 + 20 bytes),
each occupying one field element. Packing these into 5 Field elements reduces
the public input delta computation and Fiat-Shamir transcript hashing.

**Packing scheme:**
```
Before: artifact_hash[32] + repo_hash[32] + commit_sha[20] = 84 fields
After:  artifact_hash_hi, artifact_hash_lo (16 bytes each)
        repo_hash_hi, repo_hash_lo (16 bytes each)
        commit_sha_packed (20 bytes)                        = 5 fields
Total:  84 + 16 pairing → 100 pub inputs  →  5 + 16 = 21 pub inputs
```

**Measured results:**

| Component | Baseline (100 inputs) | Packed (21 inputs) | Savings |
|-----------|-----------------------|--------------------|---------|
| Load VK + parse proof | 227,965 | 227,965 | 0 |
| Fiat-Shamir transcript | 310,881 | 276,983 | 33,898 |
| Public input delta | 86,707 | 18,451 | 68,256 |
| Sumcheck | 599,934 | 599,632 | 302 |
| Shplemini | 1,599,679 | 1,598,994 | 685 |
| **TOTAL** | **2,825,166** | **2,722,025** | **103,141 (3.7%)** |

The savings come from:
- **Public input delta (-68K):** 79 fewer field multiplications
  (each input requires one mul by beta^i * gamma)
- **Transcript (-34K):** Fewer keccak256 inputs during Fiat-Shamir

Circuit constraints increase negligibly (5 byte-packing assertions are ~100
constraints, invisible against the 303K baseline).

**Trade-off:** The SigstoreVerifier contract must unpack the Fields back to
bytes for the Attestation struct, adding ~200 gas in Solidity. Net savings
remain ~103K.

### Combined: Packed Inputs + No-ZK — 1,120K savings (39.6%)

Applying both optimizations together (packed public inputs + no-ZK verifier):

| Configuration | Total Gas | Savings vs Baseline |
|---------------|-----------|---------------------|
| Baseline (ZK, 100 inputs) | 2,825,166 | — |
| Packed inputs only | 2,722,025 | 103,141 (3.7%) |
| No-ZK + packed inputs | 1,705,518 | 1,119,648 (39.6%) |

The no-ZK optimization is by far the most impactful single change. Packed inputs
provide a modest additional reduction. Together they bring verification gas under
1.8M — a 40% reduction from baseline.
