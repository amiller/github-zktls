# GitHub zkTLS

**Prove browser session properties using GitHub Actions as a "soft TEE"**

Generate cryptographic proofs about authenticated browser sessions (e.g., "I own this Twitter account") without revealing credentials. Uses GitHub Actions' public audit trail as verifiable execution environment.

## Architecture

```
┌─────────────────┐
│  USER BROWSER   │
│  + Extension    │ ──┐
└─────────────────┘   │
                      │ 1. Copy cookies
                      ▼
┌─────────────────────────────────┐
│  GITHUB ACTIONS RUNNER (TEE)    │
│  ┌─────────────────────────┐    │
│  │  Headless Browser       │    │
│  │  + Copied cookies       │    │
│  │  + Playwright script    │    │
│  └─────────────────────────┘    │
│           │                      │
│           │ 2. Visit page        │
│           │    Replay TLS        │
│           ▼                      │
│  ┌─────────────────────────┐    │
│  │  Execution Trace        │    │
│  │  + Screenshots          │    │
│  │  + Network logs         │    │
│  │  + TLS transcripts      │    │
│  └─────────────────────────┘    │
└─────────────────────────────────┘
          │
          │ 3. Public artifact
          ▼
┌─────────────────┐
│  PROOF CERT     │
│  - Session log  │
│  - Screenshots  │
│  - GitHub URL   │
└─────────────────┘
```

## Components

### 1. Browser Extension
**Purpose:** Copy cookies from user's browser to GitHub runner

**Features:**
- Extract cookies for target domain (e.g., twitter.com)
- Securely transmit to GitHub Actions via secrets
- Minimal permissions (only cookie access)

**Tech:** Chrome/Firefox WebExtension API

### 2. Local Proxy
**Purpose:** Route GitHub runner traffic through user's IP

**Features:**
- HTTP/HTTPS proxy
- Connect to GitHub runner via ngrok tunnel
- Optional: Switch to WebRTC for P2P later

**Tech:** Node.js + express-http-proxy

### 3. GitHub Actions Runner
**Purpose:** Verifiable execution environment

**Features:**
- Headless browser (Playwright)
- Receive cookies via GitHub Secrets
- Execute proof script (visit pages, replay TLS)
- Generate execution trace + screenshots
- Upload proof as artifact

**Tech:** GitHub Actions + Playwright + Chrome

### 4. Proof Certificate
**Purpose:** Verifiable output

**Contains:**
- Execution trace (all HTTP requests)
- Screenshots at key moments
- TLS transcript (if TLS replay used)
- GitHub Actions run URL (public audit trail)
- Timestamp + commit hash

## Use Case: Twitter Account Ownership

**Scenario:** Prove you own @username without revealing password

**Workflow:**
```bash
# 1. User installs browser extension
chrome://extensions -> Load unpacked -> github-zktls/extension

# 2. User triggers proof generation
Extension: "Create proof for Twitter" 
  → Copies twitter.com cookies
  → Triggers GitHub Action with cookies as secret

# 3. GitHub runner executes
- Loads cookies
- Visits https://twitter.com/settings/your_twitter_data
- Screenshot shows "Logged in as @username"
- Captures network trace

# 4. Proof generated
- Artifact uploaded to GitHub
- Public URL: https://github.com/user/repo/actions/runs/123456
- Anyone can verify: screenshot + execution log + commit
```

## Development Setup

### Phase 1: Local Testing (No GitHub yet)

**Test webservice:**
```bash
# Simple cookie-based auth
cd test-service
npm install
npm start  # http://localhost:3000
```

**Containerized browser with extension:**
```bash
cd browser-container
docker build -t github-zktls-browser .
docker run -p 9222:9222 github-zktls-browser
```

**Test flow:**
1. Visit test service, log in (gets cookie)
2. Extension copies cookie
3. Container browser receives cookie
4. Playwright visits test service
5. Verify: "Logged in as testuser"

### Phase 2: GitHub Actions Integration

**Trigger workflow:**
```bash
gh workflow run proof.yml \
  --field cookies="sessionId=abc123" \
  --field target_url="https://twitter.com/settings"
```

**Workflow captures:**
- Screenshots
- HAR file (network trace)
- Console logs
- Uploads as artifact

### Phase 3: Production Flow

**Full integration:**
- Extension auto-triggers workflow
- Proxy connects runner to user IP
- Proof certificate generated
- Shareable verification URL

## Security Model

**Threat model:**
- ✅ Proves: Cookies work, session is authenticated
- ✅ Public audit: Full GitHub Actions log
- ✅ Reproducible: Commit hash + workflow visible
- ⚠️  Not true TEE: GitHub could theoretically log cookies
- ⚠️  Cookie exposure: Transmitted via GitHub Secrets (encrypted but trusted)

**Why this still works:**
- GitHub Actions logs are public (can't fake execution)
- Cookies expire quickly (can generate proof, then revoke)
- Better than "trust me, here's a screenshot"
- Stepping stone to true zkTLS

## Comparison to True zkTLS

| Feature | GitHub zkTLS | True zkTLS (e.g., TLSNotary) |
|---------|--------------|------------------------------|
| TEE | GitHub Actions (soft) | MPC/ZK proofs |
| Cookie privacy | GitHub Secrets (trusted) | Never revealed |
| Execution proof | Public logs | Cryptographic proof |
| Setup complexity | Low (browser ext + GH) | High (notary server, ZK) |
| Cost | Free (GH Actions) | Computation cost |
| Use case | Quick demos, low stakes | High-value proofs |

**Position:** This is a practical "good enough" zkTLS for many use cases. Upgrade to true zkTLS when stakes justify the complexity.

## Roadmap

**Week 1: Core Proof of Concept**
- [ ] Test webservice with cookie auth
- [ ] Docker browser container with Playwright
- [ ] Extension: basic cookie capture
- [ ] Local flow working (no GitHub)

**Week 2: GitHub Integration**
- [ ] GitHub Actions workflow
- [ ] Cookie transmission via secrets
- [ ] Artifact generation (screenshots + logs)
- [ ] Public verification page

**Week 3: Proxy & Connectivity**
- [ ] Local proxy service
- [ ] ngrok tunnel setup
- [ ] Runner connects through user's IP
- [ ] End-to-end Twitter example

**Week 4: Polish & Distribution**
- [ ] Chrome Web Store extension
- [ ] Video demo
- [ ] Documentation
- [ ] Example proofs gallery

## Related Projects

- **TLSNotary:** True zkTLS with MPC
- **Reclaim Protocol:** zkTLS for web2 credentials
- **Pluto:** Browser extension for provable browsing

**Our differentiator:** Use GitHub Actions as TEE. Simpler, more accessible, "good enough" for many cases.

---

**Status:** Project created 2026-02-01  
**Next:** Build test webservice + browser container
