# GitHub zkTLS Development Session Notes

**Date:** 2026-02-01/02
**Status:** Working proof-of-concept with cookie extraction + browser container

## Project Goal

Build a system for verifiable proofs about authenticated browser sessions using:
1. **GitHub Actions** as attestation oracle (for verifiable execution)
2. **Browser automation** for arbitrary website proofs (Twitter followers, etc.)

Core insight: "GitHub as neutral ground" - two developers who don't trust each other can both trust GitHub. Cookies are the universal API key.

## What Works

### 1. GitHub Actions Proof (Anthropic API Key)
- **Workflow:** `.github/workflows/anthropic-proof.yml`
- **Verifier:** `verify-proof.sh`
- **Test run:** https://github.com/amiller/github-zktls/actions/runs/21573298782

Flow:
```bash
gh secret set ANTHROPIC_API_KEY
gh workflow run anthropic-proof.yml
./verify-proof.sh <run-url>
```

### 2. Cookie Extraction (yt-dlp style)
- **Script:** `extract-cookies.py`
- Reads directly from Chrome's SQLite cookie database
- Decrypts v10 (peanuts key) and v11 (keyring) cookies
- Handles meta_version >= 24 hash prefix
- No browser extension needed on client

```bash
python3 extract-cookies.py chrome github.com --include-ua -o session.json
```

### 3. Browser Container (Neko-based)
- **Directory:** `browser-container/`
- Uses Neko base image (ghcr.io/m1k1o/neko/chromium)
- Proof extension injects cookies + spoofs UA
- Bridge API for commands

```bash
cd browser-container && docker compose up -d
curl http://localhost:3002/health
curl -X POST http://localhost:3002/session -d @session.json
curl -X POST http://localhost:3002/navigate -d '{"url":"https://github.com/settings"}'
curl http://localhost:3002/screenshot -o proof.png
```

**Verified working:** Screenshot shows logged in as "amiller" on GitHub settings page.

## Architecture

```
Client Machine                    Docker Container (Neko)
┌─────────────────┐               ┌─────────────────────────┐
│ extract-cookies │  HTTP POST    │ Chromium                │
│ (reads Chrome   │ ───────────>  │ + Proof Extension       │
│  SQLite DB)     │  /session     │ (cookie inject + UA)    │
└─────────────────┘               └───────────┬─────────────┘
                                              │
                                              ▼
                                  ┌─────────────────────────┐
                                  │ Bridge API (:3002)      │
                                  │ /session, /navigate,    │
                                  │ /capture, /screenshot   │
                                  └─────────────────────────┘
```

## Key Files

| File | Purpose |
|------|---------|
| `extract-cookies.py` | Client-side cookie extraction from Chrome DB |
| `browser-container/docker-compose.yml` | Container setup (ports 8082, 3002) |
| `browser-container/Dockerfile.neko` | Neko + extension build |
| `browser-container/bridge.js` | HTTP API for container control |
| `browser-container/proof-extension/` | MV3 extension for cookie injection |
| `ARCHITECTURE.md` | Full architecture documentation |
| `.github/workflows/anthropic-proof.yml` | Non-browser proof example |
| `verify-proof.sh` | Verifier script for GitHub Actions proofs |

## References

- `refs/envoy/` - Neko + extension architecture reference
- `refs/yt-dlp/` - Cookie extraction from browser databases

## Port Configuration

Current docker-compose.yml uses:
- `8082:8080` - Neko WebRTC UI (view browser at http://localhost:8082, password: "proof")
- `3002:3000` - Bridge API

## Next Steps

1. **Capture proof endpoint** - Complete `/capture` to save screenshot + certificate
2. **Twitter follower proof** - Extract Twitter cookies, capture follower count
3. **GitHub Actions integration** - Wrap browser container in a workflow
4. **Verifier improvements** - Add certificate validation
5. **UA extraction** - Get actual Chrome UA instead of hardcoded

## Cookie Extraction Details

Chrome cookie encryption on Linux:
- **v10**: AES-CBC, key derived from "peanuts" (fixed)
- **v11**: AES-CBC, key derived from GNOME keyring password

For meta_version >= 24, decrypted cookies have 32-byte hash prefix to strip.

secretstorage package needed for keyring access:
```bash
pip install secretstorage cryptography
```

## Testing Notes

- Container takes ~5s to fully start
- Cookie injection is fast, navigation takes a few seconds
- Screenshot shows authenticated state correctly

## Commit History

1. Initial commit - test service, extension, Playwright container
2. Add browser-based proof architecture docs
3. Add Neko-based browser container + yt-dlp style cookie extraction
4. Fix cookie decryption for v11 + hash prefix

---

*Last updated: 2026-02-02 00:55 UTC*
