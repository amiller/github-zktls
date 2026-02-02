# GitHub zkTLS - Development Guide

**Quick setup for local testing (no GitHub Actions yet)**

## Phase 1: Local Testing

### Step 1: Start Test Service

```bash
cd test-service
npm install
npm start
```

**Test service running at:** http://localhost:3000

**Test accounts:**
- alice / password123
- bob / password456

**Try it manually:**
1. Visit http://localhost:3000
2. Log in with alice/password123
3. You should see "Logged in as alice"
4. Visit http://localhost:3000/api/data to see JSON response

### Step 2: Install Browser Extension

```bash
# Open Chrome
chrome://extensions/

# Enable "Developer mode" (top right)
# Click "Load unpacked"
# Select: github-zktls/extension/ directory
```

**Test the extension:**
1. Log in to test service (alice/password123)
2. Click the extension icon
3. Click "Extract Cookies" 
4. You should see sessionId cookie
5. Click "Copy to Clipboard"

**Extension state:**
- ✅ Cookie extraction works
- ✅ Copy to clipboard works
- ⏳ GitHub Actions trigger not implemented yet

### Step 3: Run Proof Generation (Manually)

```bash
cd browser-container
npm install

# Test with extracted cookies (paste from clipboard)
export COOKIES='[{"name":"sessionId","value":"YOUR_SESSION_ID","domain":"localhost","path":"/"}]'
export TARGET_URL='http://localhost:3000/profile'
export OUTPUT_DIR='./proof-output'

node run-proof.js
```

**Expected output:**
```
🦞 GitHub zkTLS Proof Generator
================================

✓ Loaded 1 cookie(s)
Launching Chromium...
✓ Cookies injected into browser context

Navigating to: http://localhost:3000/profile
✓ Page loaded
✓ Screenshot saved: ./proof-output/proof-screenshot.png
✓ Page title: Profile - alice
✓ Final URL: http://localhost:3000/profile
✓ Authentication detected: true

Fetching API data from: http://localhost:3000/api/data
✓ API data retrieved: {
  "authenticated": true,
  "user": {
    "username": "alice",
    "bio": "Test user Alice",
    "verified": true
  },
  "timestamp": "2026-02-01T23:00:00.000Z",
  "sessionId": "..."
}

✓ Proof certificate saved: ./proof-output/proof-certificate.json
✓ Network log saved: ./proof-output/network-log.json
✓ Page HTML saved: ./proof-output/page-content.html

================================
🎉 Proof generation complete!

Output directory: ./proof-output
Authenticated: true
User: @alice
```

**Check the proof:**
```bash
cd proof-output
ls -la
# You should see:
# - proof-certificate.json (the proof)
# - proof-screenshot.png (visual evidence)
# - network-log.json (all HTTP requests)
# - page-content.html (full page HTML)

# View the certificate
cat proof-certificate.json | jq
```

### Step 4: Docker Container (Optional)

```bash
cd browser-container
docker build -t github-zktls-browser .

# Run with cookies from environment
docker run \
  --network host \
  -e COOKIES='[{"name":"sessionId","value":"YOUR_SESSION_ID","domain":"localhost","path":"/"}]' \
  -e TARGET_URL='http://host.docker.internal:3000/profile' \
  -v $(pwd)/proof-output:/app/proof-output \
  github-zktls-browser
```

**Note:** On Linux, use `--add-host=host.docker.internal:172.17.0.1` to access localhost from container.

## Testing Checklist

- [ ] Test service running
- [ ] Can log in manually (alice/password123)
- [ ] Extension loads without errors
- [ ] Extension extracts cookies correctly
- [ ] Copy to clipboard works
- [ ] Proof script runs with manual cookies
- [ ] Proof certificate generated
- [ ] Screenshot shows logged-in state
- [ ] API data correctly captured

## Next Steps (Phase 2)

### GitHub Actions Integration

**Create workflow file:**
```yaml
# .github/workflows/proof.yml
name: Generate zkTLS Proof

on:
  workflow_dispatch:
    inputs:
      cookies:
        description: 'Cookies JSON (from extension)'
        required: true
      target_url:
        description: 'Target URL to prove access'
        required: true

jobs:
  generate-proof:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '20'
      
      - name: Install dependencies
        working-directory: browser-container
        run: npm ci
      
      - name: Install Playwright browsers
        working-directory: browser-container
        run: npx playwright install chromium --with-deps
      
      - name: Generate proof
        working-directory: browser-container
        env:
          COOKIES: ${{ github.event.inputs.cookies }}
          TARGET_URL: ${{ github.event.inputs.target_url }}
        run: node run-proof.js
      
      - name: Upload proof artifacts
        uses: actions/upload-artifact@v3
        with:
          name: zkTLS-proof
          path: browser-container/proof-output/
```

**Trigger from command line:**
```bash
gh workflow run proof.yml \
  --field cookies='[{"name":"sessionId","value":"abc123","domain":"twitter.com","path":"/"}]' \
  --field target_url='https://twitter.com/settings/your_twitter_data'
```

### Extension Auto-Trigger (Phase 3)

**Update extension to trigger GitHub Actions:**
1. User clicks "Generate Proof"
2. Extension calls GitHub API to trigger workflow
3. Passes cookies as workflow input
4. Returns GitHub Actions run URL
5. User can view proof artifacts

**Required:**
- GitHub personal access token (in extension settings)
- Repo name where workflow exists
- OAuth flow for secure token storage

## Debugging

**Extension debugging:**
```bash
# Open extension popup
# Right-click → "Inspect"
# Check console for errors
```

**Playwright debugging:**
```bash
# Run with headed mode
export PWDEBUG=1
node run-proof.js

# Save trace
export PLAYWRIGHT_TRACE=on
node run-proof.js
# View: npx playwright show-trace trace.zip
```

**Test service debugging:**
```bash
# Check active sessions
curl http://localhost:3000/health
```

## Project Structure

```
github-zktls/
├── README.md                 # Project overview
├── DEVELOPMENT.md           # This file
├── test-service/            # Cookie-auth test service
│   ├── server.js
│   └── package.json
├── extension/               # Browser extension
│   ├── manifest.json
│   ├── popup.html
│   ├── popup.js
│   └── background.js
├── browser-container/       # Playwright proof generator
│   ├── Dockerfile
│   ├── run-proof.js
│   └── package.json
└── .github/
    └── workflows/
        └── proof.yml        # GitHub Actions workflow (TODO)
```

## Common Issues

**"No cookies found"**
- Make sure you're logged in to test service
- Check domain matches exactly (localhost vs 127.0.0.1)

**"Cannot access host.docker.internal"**
- Linux: Add `--add-host=host.docker.internal:172.17.0.1`
- Or use `--network host` mode

**Extension not loading**
- Disable/re-enable in chrome://extensions
- Check manifest.json is valid JSON
- Look for errors in extension console

**Proof shows "not authenticated"**
- Check cookie value is correct
- Verify cookie hasn't expired
- Test manually first (visit URL in browser)

## Security Notes

**For development:**
- Cookies in plaintext (environment variables)
- No encryption of cookies in extension storage
- Test service has no rate limiting

**For production:**
- Encrypt cookies before storage
- Use GitHub Secrets for cookie transmission
- Implement short cookie expiration
- Add rate limiting to prevent abuse

---

**Status:** Development setup complete  
**Next:** Test the full flow, then add GitHub Actions integration
