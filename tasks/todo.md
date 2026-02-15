# Faucet Claim UX Improvements — 2026-02-15

## Problem Statement
An agent (Claude Code) tried to claim from the faucet end-to-end and hit several preventable failures:

### What went wrong
1. **Workflow ran from `master` HEAD** — natural default, but faucet requires pinned tag `v1.0.3`
2. **No pre-flight validation** — workflow happily generates a proof from the wrong ref, wasting ~1min of CI time
3. **Revert reason was opaque** — on-chain tx reverted with `0x832f97cb` (custom error selector). Had to manually `cast sig` every error to find it was `WrongCommit()`
4. **README says v1.0.2** — but faucet was updated to require v1.0.3 commit. Docs are stale.
5. **process-claim.yml error parsing is brittle** — `grep -oP 'Error\("\K[^"]+'` only catches string errors, not custom errors like `WrongCommit()`

## Completed

- [x] Add commit SHA pre-flight check to github-identity.yml
  - Reads required commit from VERSIONS.json
  - Compares against $GITHUB_SHA
  - Fails fast with clear error message + fix instructions
- [x] Decode custom errors in process-claim.yml
  - `decode_error()` function maps all 7 error selectors to readable messages
  - Handles both cast send failure and on-chain revert (status 0x0) paths
  - Falls back to string error extraction for unknown errors
- [x] Update README v1.0.2 → v1.0.3 (5 instances replaced)
- [x] Add agent quick-start section in README with copy-pasteable commands + error table
- [x] Update docs/faucet.md: add --ref flag, note about WrongCommit, troubleshooting entry
