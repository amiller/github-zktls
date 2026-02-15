# Lessons Learned

## 2026-02-15: Faucet Claim Debugging

### Custom error selectors are opaque
- Solidity custom errors (e.g. `error WrongCommit()`) revert with a 4-byte selector
- `cast run <tx>` shows the raw selector like `custom error 0x832f97cb`
- To decode: `cast sig "WrongCommit()"` → `0x832f97cb` (match!)
- **Fix**: Build a lookup table in process-claim.yml so agents/users get readable errors

### Workflow ref matters and isn't validated
- `gh workflow run "Name"` defaults to the repo's default branch (master)
- The faucet contract checks `requiredCommitSha` — proof must come from that exact commit
- Running from wrong ref wastes ~1min CI time generating a useless proof
- **Fix**: Add pre-flight check in workflow that queries the contract

### Stale version references in docs
- README referenced v1.0.2 but faucet was updated to v1.0.3
- VERSIONS.json has the prover digest but not the required tag
- **Fix**: Single source of truth — put the tag in VERSIONS.json, reference it everywhere

### Error selector reference for GitHubFaucet
| Error | Selector | Meaning |
|-------|----------|---------|
| `InvalidProof()` | `0x09bde339` | ZK proof failed verification |
| `CertificateMismatch()` | `0xddf32b51` | sha256(cert) ≠ attestation artifact hash |
| `UsernameMismatch()` | `0x4dca8d92` | Username in cert doesn't match arg |
| `RecipientMismatch()` | `0xc0ee95bb` | Recipient in cert doesn't match arg |
| `WrongCommit()` | `0x832f97cb` | Proof commit SHA ≠ required commit |
| `AlreadyClaimedToday()` | `0x39b1a59e` | 24h cooldown not met |
| `FaucetEmpty()` | `0xc1336f85` | No ETH left in faucet |
| `NotOwner()` | — | Only owner can call admin functions |
