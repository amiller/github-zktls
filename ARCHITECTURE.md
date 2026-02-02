# Architecture: GitHub Actions as Attestation Oracle

## Core Concept

**GitHub as neutral ground**: Two developers who don't trust each other can both trust GitHub. One proves something, the other verifies it, neither has to trust the other.

If you already push secrets to GitHub Actions, this adds zero new trust assumptions.

We use GitHub's existing properties:
- **Public audit logs** - immutable execution history
- **Reproducible runs** - tied to specific commits
- **Artifact storage** - tamper-evident outputs

A verifier doesn't need special tools. They use `git` and `gh` - things they already trust.

## What This Proves

| Property | How |
|----------|-----|
| Session validity | Cookies work, page renders authenticated state |
| Execution integrity | GitHub logs show exactly what ran |
| Code transparency | Verifier can checkout the commit and read the proof script |
| Timestamp | GitHub provides signed timestamps on runs |

**Not proven** (and that's okay for many use cases):
- Cookie confidentiality (GitHub Secrets are trusted, not cryptographic)
- That *you* own the session (vs borrowed cookies) - but this is true of OAuth too
- Network-level authenticity (relies on TLS to target site)

## Trust Model

The whole point: **prover and verifier don't trust each other**.

```
┌─────────────────────────────────────────────────────────────┐
│                     TRUST BOUNDARIES                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  PROVER trusts:                                              │
│    - GitHub (won't leak secrets, logs are accurate)          │
│    - Their own browser (extension extracts real cookies)     │
│                                                              │
│  VERIFIER trusts:                                            │
│    - GitHub (logs are authentic, artifacts untampered)       │
│    - The proof script (auditable via commit checkout)        │
│    - Target site TLS (Twitter is really Twitter)             │
│                                                              │
│  NEITHER trusts:                                             │
│    - Each other (that's the point)                           │
│                                                              │
│  BOTH already trust:                                         │
│    - GitHub (they're developers)                             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

This matches the escrow use case: two parties who need to verify something about each other without revealing everything. GitHub is the escrow agent they both accept.

## Why Browser + Cookies

**Cookies are the universal API key.** Any site you can log into, you can prove things about.

- No OAuth app registration
- No API rate limits or deprecation
- No "contact sales for API access"
- Works on sites with no API at all

Twitter example: There's no public API to get "am I logged in as @handle with X followers." But if you're logged in, that info is on the page. Extract cookies → visit page in Actions → screenshot shows follower count. Done.

This is the unlock: **prove properties about any authenticated web session**.

## Components

### 1. Browser Extension (Cookie Extractor)
Extracts cookies from user's authenticated browser session.

```
User Browser ──[extension]──> Cookie JSON
```

- Uses `chrome.cookies.getAll()` for target domain
- Outputs portable JSON format
- User copies to clipboard or triggers workflow directly

### 2. Proof Generator (Playwright Script)
Headless browser that replays the session and captures evidence.

```
Cookie JSON ──[playwright]──> Proof Artifacts
```

Captures:
- `proof-screenshot.png` - visual evidence
- `proof-certificate.json` - structured claims
- `network-log.json` - all HTTP traffic
- `page-content.html` - rendered DOM

### 3. GitHub Actions (Execution Environment)
Provides verifiable execution - public logs, pinned commits, downloadable artifacts.

```yaml
on:
  workflow_dispatch:
    inputs:
      target_url:
        description: 'URL to prove access to'
      cookies:
        description: 'Cookie JSON (use secrets for sensitive)'
```

Properties:
- Run ID links to immutable logs
- Commit SHA pins exact code version
- Artifacts downloadable by anyone with URL

### 4. Proof Artifacts (The Output)
What the prover shares with verifiers.

```
https://github.com/user/repo/actions/runs/123456789
  └── Artifacts/
      ├── proof-screenshot.png
      ├── proof-certificate.json
      ├── network-log.json
      └── page-content.html
```

## Verification Flow

A verifier receives an artifact URL and can fully verify without trusting the prover:

```bash
# 1. View the execution logs
gh run view 123456789 --log

# 2. Download proof artifacts
gh run download 123456789

# 3. Check what code actually ran
git checkout abc123def  # commit SHA from the run
cat browser-container/run-proof.js

# 4. (Optional) Run it themselves on test data
npm run proof -- --url=http://localhost:3000/profile --cookies='[...]'
```

**Key insight**: The repository IS the specification. A verifier who reads the workflow file knows exactly what the proof means.

### Verifier Script (Minimal)

```bash
#!/bin/bash
# verify-proof.sh <run-url>
# e.g., verify-proof.sh https://github.com/user/repo/actions/runs/123456789

RUN_URL=$1
# Extract owner/repo/run_id from URL
RUN_ID=$(echo "$RUN_URL" | grep -oE '[0-9]+$')
REPO=$(echo "$RUN_URL" | sed 's|https://github.com/||' | sed 's|/actions/runs/.*||')

echo "=== Fetching run metadata ==="
gh run view "$RUN_ID" --repo "$REPO" --json headSha,workflowName,conclusion

echo "=== Commit that ran ==="
COMMIT=$(gh run view "$RUN_ID" --repo "$REPO" --json headSha -q .headSha)
echo "$COMMIT"

echo "=== Download artifacts ==="
gh run download "$RUN_ID" --repo "$REPO" --dir ./proof-artifacts

echo "=== Proof contents ==="
cat ./proof-artifacts/proof/*.txt 2>/dev/null || cat ./proof-artifacts/*/*.json

echo "=== To audit the code that ran: ==="
echo "git clone https://github.com/$REPO && cd $(basename $REPO) && git checkout $COMMIT"
```

Output is human-readable. Verifier can eyeball it or build tooling on top.

## Data Flow

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│    USER      │     │   GITHUB     │     │   VERIFIER   │
│   BROWSER    │     │   ACTIONS    │     │              │
└──────┬───────┘     └──────┬───────┘     └──────┬───────┘
       │                    │                    │
       │ 1. Login to        │                    │
       │    target site     │                    │
       │    (get cookies)   │                    │
       │                    │                    │
       │ 2. Extract cookies │                    │
       │    via extension   │                    │
       │                    │                    │
       │ 3. Trigger workflow│                    │
       │───────────────────>│                    │
       │    (cookies as     │                    │
       │     secret input)  │                    │
       │                    │                    │
       │                    │ 4. Inject cookies  │
       │                    │    into Playwright │
       │                    │                    │
       │                    │ 5. Visit target,   │
       │                    │    capture proof   │
       │                    │                    │
       │                    │ 6. Upload artifacts│
       │                    │                    │
       │ 7. Get artifact URL│                    │
       │<───────────────────│                    │
       │                    │                    │
       │ 8. Share URL ──────────────────────────>│
       │                    │                    │
       │                    │ 9. Verify via gh   │
       │                    │<───────────────────│
       │                    │                    │
       │                    │ 10. Download       │
       │                    │     artifacts      │
       │                    │────────────────────>
       │                    │                    │
       │                    │ 11. Checkout repo, │
       │                    │     audit code     │
       │                    │────────────────────>
```

## Deployment Model

**Prover runs in their own repo.** This is key for adoption and trust:

```
Prover:
  1. Forks/clones this repo
  2. Has full control over their copy
  3. Runs proofs in their own GitHub Actions
  4. Owns their secrets, logs, artifacts

Verifier:
  1. Gets artifact URL from prover
  2. Checks the commit SHA the run used
  3. Audits the proof script at that commit
  4. Trusts GitHub's logs, not the prover
```

No shared infrastructure beyond GitHub itself. The prover can't fake the logs, the verifier doesn't need to trust the prover's word.

**Agent-friendly**: AI agents with GitHub access get attestation capabilities automatically. An agent can prove properties about data it has access to by running a workflow and sharing the artifact URL.

## Use Cases

### Anthropic API Key Proof (No Browser)
> "Prove you have a valid Anthropic API key"

Simplest example - just curl from Actions. No browser, no extension, no cookies.

```bash
# Prover: add your key as a GitHub secret, then trigger
gh secret set ANTHROPIC_API_KEY
gh workflow run anthropic-proof.yml

# Wait for completion, get run URL
gh run list --workflow=anthropic-proof.yml --limit=1

# Share the run URL with verifier
```

The workflow makes a minimal API call and captures:
- HTTP status (200 = key valid)
- Model used in response
- Token usage stats

Verifier runs:
```bash
./verify-proof.sh https://github.com/you/repo/actions/runs/123456789
```

They see the proof certificate, can check the logs, can audit the workflow code. Key never leaves GitHub Secrets.

### Twitter Follower Proof
> "Prove you own @handle with >10k followers"

No API key. No OAuth app. Just cookies.

```
1. Log into Twitter in your browser
2. Extension extracts twitter.com cookies
3. Trigger workflow with cookies as secret
4. Playwright visits twitter.com/settings/account
   → Screenshot shows "Logged in as @handle"
5. Playwright visits twitter.com/handle
   → Screenshot shows follower count
6. Artifacts uploaded: screenshots + page HTML
7. Share artifact URL with verifier
```

Verifier sees: GitHub logs prove the screenshots came from a real browser session, not Photoshop.

### GitHub Contributor Proof
> "Prove you have push access to repo X"

```
1. Log into GitHub (yes, proving GitHub access via GitHub Actions)
2. Extract cookies
3. Playwright visits github.com/org/repo/settings
4. If settings page loads → you have admin/write access
5. Screenshot as proof
```

### Private Balance Threshold
> "Prove bank balance > $10k without revealing exact amount"

```
1. Log into bank
2. Playwright visits account page
3. Script extracts balance, checks threshold
4. Outputs: { "balance_above_10k": true }
5. Full screenshot NOT included (or redacted)
6. Verifier sees boolean claim, trusts GitHub ran the check
```

### Document Access Timestamp
> "Prove I had access to this document at time T"

```
1. Log into Google Docs
2. Playwright opens specific doc URL
3. Screenshot shows doc content + browser timestamp
4. GitHub run has immutable timestamp
5. Proves: "I could access doc X at time T"
```

## Comparison to Alternatives

| Approach | Who You Trust | Complexity | Transparency |
|----------|---------------|------------|--------------|
| Screenshot | Prover (easily faked) | Zero | None |
| OAuth | Platform + reveals identity to verifier | Low | Opaque |
| **GitHub Actions** | GitHub | Low | Full (audit logs + code) |
| Hardware TEE | Intel/AMD + cloud provider | Medium | Attestation quotes |
| zkTLS (TLSNotary) | Cryptography + notary availability | High | Proofs |

**Our position**: Full code transparency, no special infrastructure. Ideal for:
- Developers comfortable with GitHub
- Use cases where "trust GitHub" is acceptable
- Demos that explain attestation concepts
- Stepping stone to zkTLS

## Security Considerations

### Cookie Lifecycle
```
Extract → Transmit (encrypted via GH Secrets) → Use → REVOKE
                                                      ↑
                                            Do this immediately
                                            after proof generation
```

Cookies should be short-lived. Generate proof, then rotate credentials.

### What Could Go Wrong

| Threat | Mitigation |
|--------|------------|
| GitHub logs cookies | Use GH Secrets (encrypted at rest), trust GitHub's security model |
| Prover fakes cookies | They can only prove access they actually have |
| Verifier doesn't audit code | Their problem - tools are available |
| Target site blocks GH IPs | Phase 3: proxy through user's IP |
| Replay attacks | Timestamps in proof, cookies expire |

### Trusted Computing Base

The verifier's TCB is small and auditable:
1. GitHub's infrastructure (logs, artifacts, timestamps)
2. `run-proof.js` - the proof generation script
3. Target site's TLS certificate

## Future Directions

### Proxy for IP Masking (Phase 3)
Route GitHub runner traffic through user's IP to avoid detection/blocking.

### Proof Chaining
Build proofs that reference previous proofs - "I had access yesterday AND today"

### Selective Disclosure
Proof scripts that extract specific claims without revealing full page content.

### Upgrade Path to zkTLS
When stakes justify complexity, the same cookie extraction can feed TLSNotary instead of Playwright.

---

*This architecture prioritizes transparency and accessibility over cryptographic minimalism. The goal is a proof system developers can fully understand by reading the code.*
