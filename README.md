# GitHub zkTLS

**Prove things about authenticated browser sessions using GitHub Actions as neutral ground.**

Core insight: Two parties who don't trust each other can both trust GitHub. The workflow code is visible, the execution is logged, the artifacts are public. Cookies are the universal API key.

## How It Works

```
Prover                          GitHub Actions                    Verifier
  │                                   │                              │
  ├── fork repo, add workflow ───────>│                              │
  ├── add cookies as secret ─────────>│                              │
  ├── trigger workflow ──────────────>│                              │
  │                                   ├── run browser container      │
  │                                   ├── inject cookies             │
  │                                   ├── navigate + screenshot      │
  │                                   ├── upload artifacts           │
  │                                   │                              │
  │                                   │<───── fetch run metadata ────┤
  │                                   │<───── fetch workflow @ SHA ──┤
  │                                   │<───── download artifacts ────┤
  │                                   │        diff workflow ───────>│
  │                                   │                              │
```

The commit SHA is a merkle root of the entire repo state. Fetching the workflow at that SHA via GitHub API (over TLS) gives you exactly what ran. No "cryptographic attestation" ceremony needed—we're trusting GitHub either way.

## For Provers (Agents)

**Goal:** Prove something about an account you control (follower count, purchase history, membership status, etc.)

### Steps

1. **Fork this repo** to your GitHub account

2. **Create or copy a workflow** for your claim:
   ```yaml
   name: My Proof
   on:
     workflow_dispatch:
   jobs:
     prove:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
         - name: Start browser container
           run: |
             cd browser-container
             docker compose up -d --build
             sleep 10
         - name: Capture proof
           env:
             SESSION_JSON: ${{ secrets.SITE_COM_SESSION }}
           run: |
             mkdir -p proof
             echo "$SESSION_JSON" | curl -X POST http://localhost:3002/session -H "Content-Type: application/json" -d @-
             curl -X POST http://localhost:3002/navigate -H "Content-Type: application/json" -d '{"url":"https://site.com/my-profile"}'
             sleep 5
             curl http://localhost:3002/screenshot -o proof/screenshot.png
             # ... certificate.json with claim details
         - uses: actions/upload-artifact@v4
           with:
             name: proof
             path: proof/
   ```

3. **Extract cookies** from your browser:
   ```bash
   python extract-cookies.py chrome site.com > cookies.json
   ```

4. **Add as GitHub secret:**
   ```bash
   gh secret set SITE_COM_SESSION < cookies.json
   ```

5. **Run the workflow:**
   ```bash
   gh workflow run my-proof.yml
   ```

6. **Share the run URL** with the verifier:
   ```
   https://github.com/yourname/github-zktls/actions/runs/12345
   ```

### Security Notes for Provers

- **Inspect the workflow before running.** If using someone else's workflow, read it. A malicious workflow could exfiltrate your cookies.
- **Cookies are sensitive.** GitHub Secrets are encrypted, but GitHub (and anyone with repo admin access) could theoretically access them. Use short-lived sessions when possible.
- **The run must be visible to the verifier.** Either make the repo public, or give the verifier read access.

## For Verifiers (Agents)

**Goal:** Verify that a proof is legitimate—the workflow did what it claims, and wasn't tampered with.

### Verification Steps

1. **Parse the run URL:**
   ```
   https://github.com/{owner}/{repo}/actions/runs/{run_id}
   ```

2. **Fetch run metadata:**
   ```bash
   gh api /repos/{owner}/{repo}/actions/runs/{run_id}
   # Returns: head_sha, path (workflow file), conclusion, created_at
   ```

3. **Fetch workflow content at that exact commit:**
   ```bash
   gh api /repos/{owner}/{repo}/contents/{path}?ref={head_sha}
   # Returns base64-encoded workflow file
   ```

4. **Compare to expected workflow.** Options:
   - **Exact match:** Diff against a canonical workflow you trust
   - **Structural check:** Verify it follows the expected pattern (browser container, screenshot, no exfiltration)
   - **Trust the repo:** If it's from a known-good repo (e.g., `amiller/github-zktls`), trust it

5. **Download and inspect artifacts:**
   ```bash
   gh run download {run_id}
   # Gets: screenshot.png, certificate.json
   ```

6. **Verify the claim** matches the screenshot content (may require vision/OCR for browser proofs).

### Reference Relying Party

This repo includes a reference verifier server:

```bash
cd relying-party
npm install
ANTHROPIC_API_KEY=sk-... node server.js
# http://localhost:3003
```

Features:
- Verifies workflow content against canonical workflows
- Downloads and displays proof screenshots
- Generates bespoke content based on verified claims
- Public wall for posting as verified identities

API:
```
POST /api/verify         - Verify a run URL, returns workflow verification status
GET  /api/session/:id/workflow - Inspect the actual workflow that ran
GET  /api/session/:id/screenshot - View proof screenshot
```

### Browser Login Proofs (Special Case)

Browser session proofs are powerful but require care:

- The screenshot shows authenticated state, but **the verifier must trust the workflow** didn't just render a fake page
- Our workflows use `browser-container/` which runs a real Chromium instance
- The workflow navigates to a real URL and screenshots what the browser renders
- If you don't trust the prover's workflow, compare it byte-for-byte to a known-good one

## Existing Workflows

| Workflow | Proves | Secret |
|----------|--------|--------|
| `twitter-proof.yml` | Twitter profile + followers | `TWITTER_COM_SESSION` |
| `ebay-feedback.yml` | eBay seller feedback | `EBAY_COM_SESSION` |
| `paypal-balance.yml` | PayPal account access | `PAYPAL_COM_SESSION` |
| `github-contributions.yml` | GitHub profile | `GITHUB_COM_SESSION` |

## Cookie Extraction

```bash
# Chrome (Linux/Mac)
python extract-cookies.py chrome twitter.com

# Firefox
python extract-cookies.py firefox twitter.com
```

Outputs JSON compatible with the browser container's `/session` endpoint.

## Trust Model

| What | Trust Level |
|------|-------------|
| GitHub Actions execution | High—logs are public, can't fake run completion |
| GitHub Secrets | Medium—encrypted, but GitHub has access |
| Workflow content | Verify via commit SHA—content-addressed |
| Screenshot authenticity | Depends on workflow—real browser or fake render? |

**This is "good enough" zkTLS.** For high-stakes proofs, use true zkTLS (TLSNotary, Reclaim). For most use cases—proving social media ownership, membership status, purchase history—GitHub as neutral ground is sufficient.

## Related

- [TLSNotary](https://tlsnotary.org/) - True zkTLS with MPC
- [Reclaim Protocol](https://reclaimprotocol.org/) - zkTLS for web2 credentials
