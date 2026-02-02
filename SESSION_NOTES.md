# GitHub zkTLS Development Session Notes

**Date:** 2026-02-01/02
**Status:** General-purpose GitHub Actions proof system with browser session special case

## Project Summary

GitHub Actions as a "poor man's TEE" for verifiable proofs. Two parties who don't trust each other can both trust GitHub. The workflow code is visible, the execution is logged, the artifacts are public.

Core insight: The commit SHA is a merkle root of the entire repo. Fetching the workflow at that SHA gives you exactly what ran. No ceremony needed.

## Active Components

| Directory | Purpose |
|-----------|---------|
| `README.md` | General pattern + agent instructions for provers/verifiers |
| `browser-container/` | Neko-based container for authenticated browser screenshots |
| `examples/login-with-anything/` | Reference verifier server with workflow verification |
| `extract-cookies.py` | Cookie extraction from Chrome/Firefox |
| `.github/workflows/` | Proof workflow examples |
| `WORKFLOW_GUIDELINES.md` | Pattern for writing proof workflows |
| `refs/` | Reference materials (yt-dlp cookie code) |

## Proof Workflows

| Workflow | Proves | Secret |
|----------|--------|--------|
| `twitter-proof.yml` | Twitter profile + followers | `TWITTER_COM_SESSION` |
| `ebay-feedback.yml` | eBay seller feedback | `EBAY_COM_SESSION` |
| `paypal-balance.yml` | PayPal account access | `PAYPAL_COM_SESSION` |
| `github-contributions.yml` | GitHub profile | `GITHUB_COM_SESSION` |
| `anthropic-proof.yml` | API key validity | `ANTHROPIC_API_KEY` |

## Relying Party Server

**URL:** http://localhost:3003

Features:
- Workflow verification against canonical (fetches workflow @ commit SHA, diffs)
- 57 proof types across 20 sites (on-demand workflow generation)
- Proof screenshot display
- Public wall for posting as verified identities

Key endpoints:
```
POST /api/verify              - Verify run URL, returns workflow verification status
GET  /api/session/:id/workflow - Inspect actual workflow that ran
GET  /api/session/:id/screenshot - View proof screenshot
POST /api/workflow/generate   - Generate workflow for proof type (Claude)
```

## Verification Model

The relying party fetches:
1. Run metadata via `gh api /repos/{owner}/{repo}/actions/runs/{run_id}` → gets `head_sha`, `path`
2. Workflow content at that commit via `gh api /repos/{owner}/{repo}/contents/{path}?ref={head_sha}`
3. Compares to canonical workflow → returns `workflow.verified: true/false`

No "cryptographic attestation" ceremony—we're trusting GitHub's API over TLS either way.

## Archived

Moved to `archive/`:
- `extension/` - Browser extension concept (not used)
- `test-service/` - Early dev test service
- `verifier-site/` - Superseded by relying-party
- `wormhole/` - WebRTC tunnel (deprioritized)
- `ARCHITECTURE.md` - Detailed but partly stale

## Test Runs

- Twitter: https://github.com/amiller/github-zktls/actions/runs/21573892596
- eBay: https://github.com/amiller/github-zktls/actions/runs/21592011535
- PayPal: https://github.com/amiller/github-zktls/actions/runs/21595600188
- Anthropic API: https://github.com/amiller/github-zktls/actions/runs/21573298782

---

*Last updated: 2026-02-02*
