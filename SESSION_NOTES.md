# GitHub zkTLS Development Session Notes

**Date:** 2026-02-01/02
**Status:** WebRTC wormhole tunnel in progress - TURN relay working locally but not on GitHub yet

## Project Goal

Build a system for verifiable proofs about authenticated browser sessions using:
1. **GitHub Actions** as attestation oracle (for verifiable execution)
2. **Browser automation** for arbitrary website proofs (Twitter followers, etc.)
3. **WebRTC wormhole** for IP proxying (browser traffic exits through user's IP)

Core insight: "GitHub as neutral ground" - two developers who don't trust each other can both trust GitHub. Cookies are the universal API key.

## What Works

### 1. GitHub Actions Proof (Anthropic API Key) ✅
- **Workflow:** `.github/workflows/anthropic-proof.yml`
- **Verifier:** `verify-proof.sh`
- Successfully tested: https://github.com/amiller/github-zktls/actions/runs/21573298782

### 2. Cookie Extraction (yt-dlp style) ✅
- **Script:** `extract-cookies.py`
- Reads directly from Chrome's SQLite cookie database
- Decrypts v10 (peanuts key) and v11 (keyring) cookies
- Handles meta_version >= 24 hash prefix

### 3. Browser Container (Neko-based) ✅
- **Directory:** `browser-container/`
- Successfully captured authenticated Twitter screenshot locally
- Port 8082 for Neko WebRTC UI, 3002 for Bridge API

### 4. Twitter Proof Workflow (via secrets) ✅
- **Workflow:** `.github/workflows/twitter-proof.yml`
- Successfully captured screenshot showing authenticated @socrates1024 with 23.9K followers
- Test run: https://github.com/amiller/github-zktls/actions/runs/21573892596

### 5. WebRTC Local Test ✅
- `wormhole/test-local.js` - Both peers in same process works perfectly
- SOCKS5 proxy over WebRTC data channel verified working
- Traffic correctly exits through local IP

### 6. Cloudflare TURN ✅ (locally)
- Free TURN at `speed.cloudflare.com/turn-creds`
- Generates **relay candidates** locally:
  ```
  a=candidate:11 1 UDP 8386047 104.30.145.20 41165 typ relay raddr 0.0.0.0 rport 0
  ```

## What's Not Working Yet

### WebRTC Tunnel to GitHub Actions ❌

**Problem:** Connection between local machine and GitHub runner doesn't establish.

**Architecture:**
```
Local (client.js)                    GitHub Actions (runner.js)
┌────────────────┐                   ┌────────────────┐
│ Create offer   │─── workflow ───>  │ Read offer     │
│ (with relay)   │    input          │                │
│                │                   │ Fetch CF TURN  │
│ Watch logs     │<── logs ──────────│ Print answer   │
│ Parse answer   │                   │                │
│                │                   │                │
│ Set remote SDP │     WebRTC ???    │ Set remote SDP │
│ Wait for DC    │<═══════════════X═>│ Start SOCKS5   │
└────────────────┘  (not connecting) └────────────────┘
```

**Attempts:**
1. **STUN only** - Both sides got srflx candidates but symmetric NAT blocked hole punch
2. **Open Relay Project** - Credentials `openrelayproject:openrelayproject` don't work anymore
3. **Cloudflare TURN** - Gets relay candidates locally, but GitHub runner workflow still shows "tunnel-not-ready"

**Latest failed run:** https://github.com/amiller/github-zktls/actions/runs/21574861266

**ICE Candidates from last attempt:**
- Client: host candidates + srflx (68.36.209.203:58138) + relay (via Cloudflare)
- Runner: Only host (10.1.0.x) - Need to verify if runner got relay candidates

**Next debugging steps:**
1. Check if runner.js actually fetches Cloudflare creds and gets relay candidates
2. Increase ICE gathering time (currently 2s, may need more)
3. Add logging of all ICE candidates on runner side
4. Try TCP transport explicitly

## Key Files

| File | Purpose |
|------|---------|
| `wormhole/client.js` | Client-side WebRTC + gathers ICE + triggers workflow |
| `wormhole/runner.js` | Runner-side WebRTC + SOCKS5 proxy |
| `wormhole/test-local.js` | Local test (both peers same process) |
| `.github/workflows/wormhole-proof.yml` | Workflow that uses WebRTC tunnel |
| `extract-cookies.py` | Cookie extraction from Chrome |
| `browser-container/` | Neko container for browser automation |
| `verifier-site/index.html` | Simple proof verifier website |

## Technical Details

### node-datachannel ICE Server Format
```javascript
// TURN with credentials uses: turn:user:pass@host:port
const iceServers = [
  'stun:stun.cloudflare.com:3478',
  'turn:username:credential@turn.cloudflare.com:3478'
]
```

### Cloudflare TURN Credentials
```javascript
const res = await fetch('https://speed.cloudflare.com/turn-creds')
const { urls, username, credential } = await res.json()
// Convert to node-datachannel format
```

### Signaling Flow
1. **Client→Runner:** Offer via workflow dispatch input (base64 encoded)
2. **Runner→Client:** Answer via logs with `ANSWER_START{base64}|{punchTime}ANSWER_END` markers
3. **Timing:** Both sides sync on punchTime (next 5-second boundary)

## GitHub Secrets
- `ANTHROPIC_API_KEY` - For API key proof workflow
- `TWITTER_SESSION` - x.com session cookies JSON

## Port Configuration
- `8082:8080` - Neko WebRTC UI
- `3002:3000` - Bridge API
- `1080` - SOCKS5 proxy (in wormhole)

## Commits (chronological)
1. Working cookie extraction + twitter proof via secrets
2. Add WebRTC wormhole architecture
3. Switch to node-datachannel (wrtc had build issues)
4. Use logs for signaling instead of gist
5. Add synchronized hole punch timing
6. Try Open Relay TURN (didn't work)
7. Switch to Cloudflare TURN (relay candidates work locally)

## Resume Instructions

1. Check why runner doesn't get relay candidates:
   ```bash
   gh run view <run-id> --log | grep -E "(candidate|relay|Cloudflare)"
   ```

2. If no relay on runner, debug ICE gathering time or fetch issues

3. Once both sides have relay candidates, connection should work via TURN relay

4. Alternative: Use ngrok fallback (simpler but requires clearing other sessions)
   ```bash
   pkill ngrok  # Kill other sessions first
   node wormhole/client-ngrok.js
   ```

---

*Last updated: 2026-02-02 02:10 UTC*
