# Browser Extension - GitHub zkTLS

Cookie extraction extension for generating zkTLS proofs via GitHub Actions.

## Quick Install

1. Open Chrome
2. Go to `chrome://extensions/`
3. Enable "Developer mode"
4. Click "Load unpacked"
5. Select this `extension/` directory

## Icons

Icons are placeholders for now. To create proper icons:

```bash
# Create 16x16, 48x48, 128x128 PNG icons
# Suggested: Lobster (🦞) + lock (🔒) symbol
# Color: #0066ff on transparent background
```

For now, the extension works without icons (Chrome will show a default puzzle piece).

## Usage

1. Visit a site you're logged into (e.g., http://localhost:3000)
2. Click the extension icon
3. Domain auto-fills from current tab
4. Click "Extract Cookies"
5. Click "Copy to Clipboard"
6. Paste into GitHub Actions workflow input

## Permissions

- `cookies` - Read cookies from any domain
- `activeTab` - Get current tab URL
- `storage` - Save extracted cookies locally
- `host_permissions: <all_urls>` - Access cookies for all domains

**Privacy:** Cookies stay local. Nothing sent to external servers (only to GitHub Actions when you trigger manually).
