# GitHub zkTLS

**Use GitHub Actions as a general-purpose verifiable execution environment.**

GitHub Actions is a "poor man's TEE." Two parties who don't trust each other can both trust GitHub. The workflow code is visible, the execution is logged, the artifacts are public. This repo shows how to use it for proofs.

## The Pattern

Any claim that can be verified by running code can become a GitHub Actions proof:

```
Prover                          GitHub Actions                    Verifier
  │                                   │                              │
  ├── write workflow for claim ──────>│                              │
  ├── add secrets if needed ─────────>│                              │
  ├── trigger workflow ──────────────>│                              │
  │                                   ├── execute proof code         │
  │                                   ├── generate artifacts         │
  │                                   │                              │
  │                                   │<──── fetch workflow @ SHA ───┤
  │                                   │<──── download artifacts ─────┤
  │                                   │       verify claim ─────────>│
```

The commit SHA is a merkle root of the entire repo. Fetching the workflow at that SHA gives you exactly what ran. No ceremony needed—we're trusting GitHub's API over TLS either way.

## Examples

| Proof Type | How It Works |
|------------|--------------|
| **API key validity** | Workflow calls API, logs success/failure |
| **Computation result** | Workflow runs code, outputs hash of result |
| **File existence** | Workflow fetches URL, checksums content |
| **Browser session** | Workflow runs browser with cookies, screenshots page |
| **Rate/score/status** | Workflow scrapes authenticated page, extracts data |

The browser session case is powerful but complex—it's a special case detailed below.

## For Provers (Agents)

1. **Fork this repo** (or create your own)

2. **Write a workflow** that proves your claim:
   ```yaml
   name: My Proof
   on:
     workflow_dispatch:
   jobs:
     prove:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
         - name: Generate proof
           run: |
             # Your proof logic here
             # Output to proof/ directory
         - uses: actions/upload-artifact@v4
           with:
             name: proof
             path: proof/
   ```

3. **Add secrets** if your proof needs credentials:
   ```bash
   gh secret set MY_SECRET < secret.txt
   ```

4. **Run and share:**
   ```bash
   gh workflow run my-proof.yml
   # Share: https://github.com/you/repo/actions/runs/12345
   ```

### Security for Provers

- **Inspect workflows before running.** A malicious workflow could exfiltrate your secrets.
- **Secrets are sensitive.** GitHub encrypts them, but has access. Use short-lived credentials.
- **Runs must be visible to verifiers.** Public repo, or grant read access.

## For Verifiers (Agents)

1. **Fetch run metadata:**
   ```bash
   gh api /repos/{owner}/{repo}/actions/runs/{run_id}
   # → head_sha, path (workflow file), conclusion
   ```

2. **Fetch workflow at that exact commit:**
   ```bash
   gh api /repos/{owner}/{repo}/contents/{path}?ref={head_sha}
   # → base64-encoded workflow content
   ```

3. **Verify the workflow** does what it claims:
   - **Exact match:** Diff against a canonical workflow
   - **Structural check:** Verify pattern, no exfiltration
   - **Trust repo:** If from known-good source, accept

4. **Download artifacts:**
   ```bash
   gh run download {run_id}
   ```

5. **Verify the claim** matches artifact contents.

## Browser Session Proofs (Special Case)

Browser login proofs use a containerized browser that accepts cookies and takes screenshots. This is useful for "log in with anything"—prove Twitter followers, eBay feedback, PayPal access, etc.

### How It Works

```yaml
- name: Start browser container
  run: |
    cd browser-container
    docker compose up -d --build

- name: Inject cookies and capture
  env:
    SESSION_JSON: ${{ secrets.SITE_COM_SESSION }}
  run: |
    echo "$SESSION_JSON" | curl -X POST http://localhost:3002/session -d @-
    curl -X POST http://localhost:3002/navigate -d '{"url":"https://site.com/profile"}'
    curl http://localhost:3002/screenshot -o proof/screenshot.png
```

### Cookie Extraction

```bash
python extract-cookies.py chrome twitter.com > cookies.json
gh secret set TWITTER_COM_SESSION < cookies.json
```

### Existing Browser Workflows

| Workflow | Proves | Secret |
|----------|--------|--------|
| `twitter-proof.yml` | Twitter profile + followers | `TWITTER_COM_SESSION` |
| `ebay-feedback.yml` | eBay seller feedback | `EBAY_COM_SESSION` |
| `paypal-balance.yml` | PayPal account access | `PAYPAL_COM_SESSION` |
| `github-contributions.yml` | GitHub profile | `GITHUB_COM_SESSION` |

### Example: Login With Anything

Reference implementation for verifying browser proofs:

```bash
cd examples/login-with-anything && npm install
ANTHROPIC_API_KEY=sk-... node server.js
# http://localhost:3003
```

- Verifies workflow content against canonical
- Displays proof screenshots
- Public wall for posting as verified identities

## Trust Model

| Component | Trust Level |
|-----------|-------------|
| GitHub Actions execution | High—logs public, can't fake completion |
| GitHub Secrets | Medium—encrypted, GitHub has access |
| Workflow content | Verifiable—fetch at commit SHA, diff |
| Artifact integrity | High—uploaded by workflow, immutable |

**This is "good enough" ZK.** For high-stakes proofs, use real ZK (TLSNotary, Reclaim). For most cases—proving ownership, status, membership—GitHub as neutral ground works.

## Why Not Real ZK?

| | GitHub Actions | True ZK (TLSNotary, etc.) |
|-|----------------|---------------------------|
| **Setup** | Fork repo, write YAML | Run notary server, MPC setup |
| **Trust** | GitHub | Cryptographic |
| **Cost** | Free | Computation overhead |
| **Flexibility** | Any code | TLS-specific |
| **Use case** | Quick proofs, demos | High-value, adversarial |

GitHub Actions is a general-purpose verifiable execution environment. ZK proofs are cryptographically sound but specialized. Pick based on your threat model.

## Related

- [TLSNotary](https://tlsnotary.org/) - True zkTLS with MPC
- [Reclaim Protocol](https://reclaimprotocol.org/) - zkTLS for web2 credentials
