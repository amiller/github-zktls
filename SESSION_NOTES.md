# GitHub zkTLS Development Session Notes

**Date:** 2026-02-01/02
**Status:** "Prove Anything" relying party server working with on-demand workflow generation

## Project Goal

Build a system for verifiable proofs about authenticated browser sessions using:
1. **GitHub Actions** as attestation oracle (for verifiable execution)
2. **Browser automation** for arbitrary website proofs (Twitter followers, eBay seller rating, etc.)
3. **Relying party server** for "log in with anything" via verified proofs

Core insight: "GitHub as neutral ground" - two developers who don't trust each other can both trust GitHub. Cookies are the universal API key.

## What Works

### 1. Relying Party Server ✅ (NEW)
- **Directory:** `relying-party/`
- **URL:** http://localhost:3003
- **Features:**
  - 57 proof types across 20 popular sites
  - On-demand workflow generation via Claude
  - Proof verification from GitHub Actions artifacts
  - Screenshot display of verified sessions
  - Public wall for posting as verified identities

### 2. On-Demand Workflow Generation ✅ (NEW)
- Claude generates site-specific workflows from examples + guidelines
- Workflows cached after first generation
- No messy "generic workflow" - each is clean and specific
- Guidelines doc: `WORKFLOW_GUIDELINES.md`

### 3. eBay Proof ✅ (NEW)
- **Workflow:** `.github/workflows/ebay-feedback.yml`
- Successfully verified eBay seller profile (socrates1024, 100% feedback, member since 2004)
- Test run: https://github.com/amiller/github-zktls/actions/runs/21592011535

### 4. Twitter Proof ✅
- **Workflow:** `.github/workflows/twitter-proof.yml`
- Successfully captured screenshot showing authenticated @socrates1024 with 23.9K followers
- Test run: https://github.com/amiller/github-zktls/actions/runs/21573892596

### 5. GitHub Actions Proof (Anthropic API Key) ✅
- **Workflow:** `.github/workflows/anthropic-proof.yml`
- **Verifier:** `verify-proof.sh`
- Successfully tested: https://github.com/amiller/github-zktls/actions/runs/21573298782

### 6. Cookie Extraction (yt-dlp style) ✅
- **Script:** `extract-cookies.py`
- Reads directly from Chrome's SQLite cookie database
- Decrypts v10 (peanuts key) and v11 (keyring) cookies

### 7. Browser Container (Neko-based) ✅
- **Directory:** `browser-container/`
- Captures authenticated screenshots via Bridge API
- Port 3002 for Bridge API

## Proof Catalog (57 types)

Sites covered: Twitter, Amazon, GitHub, LinkedIn, Reddit, Spotify, Netflix, YouTube, Discord, Twitch, Instagram, TikTok, PayPal, Airbnb, Uber, DoorDash, eBay, Etsy, Stack Overflow, Duolingo

Example proof types per site:
- **Twitter:** Follower count, verified badge, account age
- **Amazon:** Cart contents, Prime member, order history
- **eBay:** Feedback score, watching items
- **GitHub:** Contributions, stars, repos
- **Uber:** Rider rating, trip count

## Key Files

| File | Purpose |
|------|---------|
| `relying-party/server.js` | Express server - verify proofs, generate workflows, wall API |
| `relying-party/proofs.js` | Catalog of 57 proof types across 20 sites |
| `relying-party/public/index.html` | "Prove Anything" UI |
| `WORKFLOW_GUIDELINES.md` | Pattern for writing proof workflows |
| `.github/workflows/twitter-proof.yml` | Example: Twitter proof |
| `.github/workflows/ebay-feedback.yml` | Example: eBay proof |
| `.github/workflows/github-contributions.yml` | Example: GitHub proof |
| `extract-cookies.py` | Cookie extraction from Chrome |
| `browser-container/` | Neko container for browser automation |

## API Endpoints

```
GET  /api/proofs/random?n=5  - Get random proof options
GET  /api/proofs/all         - Get full catalog
POST /api/workflow/generate  - Generate workflow for proof type (Claude)
GET  /api/workflow/:proofId  - Get cached workflow
POST /api/verify             - Verify a GitHub Actions proof
GET  /api/session/:id        - Get session info
GET  /api/session/:id/screenshot - Get proof screenshot
GET  /api/wall               - Get wall posts
POST /api/wall               - Post to wall (requires session)
```

## GitHub Secrets
- `ANTHROPIC_API_KEY` - For API key proof workflow
- `TWITTER_COM_SESSION` - Twitter session cookies JSON
- `EBAY_COM_SESSION` - eBay session cookies JSON

## Running the Server

```bash
cd relying-party
npm install
ANTHROPIC_API_KEY=sk-... node server.js
# Server at http://localhost:3003
```

## Adding a New Proof Type

1. Extract cookies: `python extract-cookies.py chrome site.com`
2. Add as GitHub secret: `gh secret set SITE_COM_SESSION < cookies.json`
3. Generate workflow via UI or API (Claude creates it)
4. Copy workflow to `.github/workflows/`
5. Run workflow and verify

## Deprioritized: WebRTC Tunnel

WebRTC tunnel to GitHub Actions was deprioritized. Both sides get relay candidates but timing issues with log-based signaling prevented connection. The proof system works fine via secrets - the IP proxy was for robustness against IP blocking, not security.

## Public Wall Posts

The wall shows posts from verified identities:
- `twitter-follower-proof` / socrates1024 - "Test post from verified user"
- `ebay-feedback` / socrates1024 - "Verified eBay seller - 100% positive feedback, member since 2004"

---

*Last updated: 2026-02-02 13:55 UTC*
