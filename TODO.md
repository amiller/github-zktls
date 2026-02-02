# GitHub zkTLS - TODO

## Phase 1: Local Testing (Week 1) - IN PROGRESS

### Test Service
- [x] Express server with cookie-based auth
- [x] Login/logout endpoints
- [x] Profile page (proof target)
- [x] API endpoint (JSON response)
- [x] Health check
- [ ] Test with extension
- [ ] Verify cookie extraction works

### Browser Extension
- [x] Manifest v3
- [x] Popup UI
- [x] Cookie extraction logic
- [x] Copy to clipboard
- [ ] Create actual icon files (currently placeholders)
- [ ] Test in Chrome
- [ ] Test domain auto-detection
- [ ] Add error handling

### Browser Container
- [x] Dockerfile with Playwright
- [x] Cookie injection script
- [x] Proof generation (screenshot + certificate)
- [x] Network logging
- [x] API data extraction
- [ ] Test with manual cookies
- [ ] Test with Docker
- [ ] Fix host.docker.internal on Linux

## Phase 2: GitHub Actions (Week 2)

### Workflow
- [ ] Create .github/workflows/proof.yml
- [ ] workflow_dispatch with cookies input
- [ ] Install Playwright in runner
- [ ] Run proof generation
- [ ] Upload artifacts
- [ ] Test manual trigger
- [ ] Test with real Twitter (or test service)

### Extension Integration
- [ ] "Trigger GitHub Action" button in popup
- [ ] Settings page for GitHub token
- [ ] Repo name configuration
- [ ] Auto-open GitHub Actions run URL
- [ ] Show run status in popup

### Documentation
- [ ] Update README with GitHub Actions setup
- [ ] Add workflow trigger examples
- [ ] Document cookie security model
- [ ] Add Twitter example walkthrough

## Phase 3: Proxy & Connectivity (Week 3)

### Local Proxy
- [ ] Create proxy service (Node.js)
- [ ] HTTP/HTTPS proxy support
- [ ] ngrok tunnel integration
- [ ] Pass tunnel URL to GitHub runner
- [ ] Runner connects through user's IP

### GitHub Runner Updates
- [ ] Accept proxy URL input
- [ ] Configure Playwright to use proxy
- [ ] Verify IP matches user's location
- [ ] Include proxy logs in proof

### Testing
- [ ] Test IP masking works
- [ ] Test with rate-limited APIs
- [ ] Verify network trace shows correct IP
- [ ] Compare: direct vs proxied

## Phase 4: Production (Week 4)

### Extension Polish
- [ ] Proper icons (16, 48, 128)
- [ ] Better error messages
- [ ] Loading states
- [ ] Success animations
- [ ] Settings persistence

### Chrome Web Store
- [ ] Create store listing
- [ ] Privacy policy page
- [ ] Screenshots
- [ ] Demo video
- [ ] Submit for review

### Documentation
- [ ] Video walkthrough
- [ ] Example proofs gallery
- [ ] Comparison to true zkTLS
- [ ] FAQ section
- [ ] Troubleshooting guide

### Security
- [ ] Cookie encryption in extension storage
- [ ] Short cookie expiration recommendations
- [ ] Audit GitHub Secrets transmission
- [ ] Rate limiting guidance
- [ ] Threat model documentation

## Backlog / Future Ideas

### WebRTC P2P Connection
- [ ] Replace ngrok with WebRTC
- [ ] Direct peer connection (runner ↔ proxy)
- [ ] ICE/STUN/TURN setup
- [ ] Lower latency

### TLS Replay
- [ ] Capture TLS handshake
- [ ] Replay exact API calls
- [ ] Include TLS transcript in proof
- [ ] Cryptographic proof of connection

### Multi-Service Support
- [ ] Twitter profile proof
- [ ] GitHub contributor proof
- [ ] Email ownership proof
- [ ] Calendar access proof
- [ ] Custom service templates

### Proof Verification Page
- [ ] Public verification tool
- [ ] Parse proof certificate
- [ ] Show screenshot
- [ ] Validate GitHub Actions URL
- [ ] Check commit hash

### Advanced Features
- [ ] Multi-step proofs (visit multiple pages)
- [ ] Conditional logic (if X then screenshot Y)
- [ ] API call replay (exact headers/body)
- [ ] Video recording (not just screenshot)
- [ ] Proof chaining (build on previous proofs)

## Questions / Decisions

- **Cookie security:** Encrypt before sending to GitHub? Use GitHub Secrets API directly?
- **WebRTC vs ngrok:** Start with ngrok (simpler), upgrade to WebRTC later?
- **Proxy requirement:** Is IP masking always needed? Make it optional?
- **TLS replay:** Worth the complexity? Or screenshot + API JSON enough?
- **True zkTLS upgrade path:** How to migrate to TLSNotary/Reclaim if needed?

## Blockers

- Extension icon creation (need design skills or ImageMagick)
- GitHub personal access token permissions (need to document minimal scope)
- Docker on Linux (host.docker.internal workaround)

---

**Created:** 2026-02-01  
**Current phase:** Phase 1 - Local Testing  
**Status:** Core components created, testing not started yet
