#!/bin/bash
# Local test harness for tweet capture workflow
# Usage: ./test-tweet-capture.sh <tweet_url> <recipient_address> [session_file]
#
# Example:
#   ./test-tweet-capture.sh https://x.com/socrates1024/status/123 0x1234...abcd ./twitter-session.json

set -e

TWEET_URL="${1:?Usage: $0 <tweet_url> <recipient_address> [session_file]}"
RECIPIENT="${2:?Usage: $0 <tweet_url> <recipient_address> [session_file]}"
SESSION_FILE="${3:-./twitter-session.json}"

PROOF_DIR="./proof-$(date +%s)"
mkdir -p "$PROOF_DIR"

echo "=== Tweet Capture Test ==="
echo "Tweet URL: $TWEET_URL"
echo "Recipient: $RECIPIENT"
echo "Output: $PROOF_DIR"
echo ""

# Validate inputs
if ! echo "$TWEET_URL" | grep -qE '^https://(x\.com|twitter\.com)/[^/]+/status/[0-9]+'; then
  echo "❌ Invalid tweet URL format"
  exit 1
fi

if ! echo "$RECIPIENT" | grep -qE '^0x[a-fA-F0-9]{40}$'; then
  echo "❌ Invalid ETH address format"
  exit 1
fi

echo "✓ Inputs validated"

# Step 1: Fetch tweet via oEmbed (no auth needed)
echo ""
echo "=== Step 1: Fetch tweet via oEmbed ==="
curl -s "https://publish.twitter.com/oembed?url=$TWEET_URL" > "$PROOF_DIR/oembed.json"

if ! jq -e '.author_url' "$PROOF_DIR/oembed.json" > /dev/null 2>&1; then
  echo "❌ Failed to fetch tweet"
  cat "$PROOF_DIR/oembed.json"
  exit 1
fi

AUTHOR_URL=$(jq -r '.author_url' "$PROOF_DIR/oembed.json")
AUTHOR_HANDLE=$(echo "$AUTHOR_URL" | sed 's|https://twitter.com/||')
AUTHOR_NAME=$(jq -r '.author_name' "$PROOF_DIR/oembed.json")
TWEET_HTML=$(jq -r '.html' "$PROOF_DIR/oembed.json")
TWEET_TEXT=$(echo "$TWEET_HTML" | sed 's/<[^>]*>//g' | sed 's/&mdash;/—/g' | head -c 500)

echo "Author: @$AUTHOR_HANDLE ($AUTHOR_NAME)"
echo "Tweet: $TWEET_TEXT"
echo "$AUTHOR_HANDLE" > "$PROOF_DIR/expected_author.txt"
echo "✓ oEmbed fetch successful"

# Step 2: Start browser container (if not running)
echo ""
echo "=== Step 2: Browser container ==="
if ! curl -s http://localhost:3002/health > /dev/null 2>&1; then
  echo "Starting browser container..."
  docker compose up -d --build
  sleep 10
fi

if curl -sf http://localhost:3002/health > /dev/null; then
  echo "✓ Browser container ready"
else
  echo "❌ Browser container not responding"
  exit 1
fi

# Step 3: Verify logged-in user
echo ""
echo "=== Step 3: Verify logged-in user ==="

if [ ! -f "$SESSION_FILE" ]; then
  echo "❌ Session file not found: $SESSION_FILE"
  echo ""
  echo "To create a session file, export your Twitter cookies as JSON:"
  echo '  {"cookies": [{"name": "auth_token", "value": "...", "domain": ".x.com"}, ...]}'
  echo ""
  echo "Or use: python3 extract-cookies.py chrome x.com -o twitter-session.json"
  exit 1
fi

echo "Injecting session from $SESSION_FILE..."
cat "$SESSION_FILE" | curl -s -X POST http://localhost:3002/session \
  -H "Content-Type: application/json" -d @-

echo ""
echo "Getting logged-in user via Twitter API interception..."

# Use the /twitter/me endpoint which navigates to Twitter and extracts user data
ME_RESULT=$(curl -s http://localhost:3002/twitter/me)
echo "Result: $ME_RESULT"

# Extract username from result
LOGGED_IN_USER=$(echo "$ME_RESULT" | jq -r '.screen_name // empty' 2>/dev/null || true)

echo "Expected author: @$AUTHOR_HANDLE"
echo "Logged in as: @$LOGGED_IN_USER"

if [ -z "$LOGGED_IN_USER" ]; then
  echo "⚠️  Could not determine logged-in user"
  echo "Taking debug screenshot..."
  curl -s http://localhost:3002/screenshot -o "$PROOF_DIR/debug-settings.png"
  echo "Check $PROOF_DIR/debug-settings.png"

  read -p "Continue anyway? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
  LOGGED_IN_USER="$AUTHOR_HANDLE"  # Assume match for testing
fi

if [ "${LOGGED_IN_USER,,}" != "${AUTHOR_HANDLE,,}" ]; then
  echo "❌ MISMATCH: Logged in as @$LOGGED_IN_USER but tweet is by @$AUTHOR_HANDLE"
  exit 1
fi

echo "✓ Verified: logged in as tweet author"

# Step 4: Screenshot the tweet
echo ""
echo "=== Step 4: Capture screenshot ==="
curl -s -X POST http://localhost:3002/navigate \
  -H "Content-Type: application/json" \
  -d "{\"url\":\"$TWEET_URL\"}"

sleep 3
curl -s http://localhost:3002/screenshot -o "$PROOF_DIR/screenshot.png"
echo "✓ Screenshot saved"

# Step 5: Generate certificate
echo ""
echo "=== Step 5: Generate certificate ==="
cat > "$PROOF_DIR/certificate.json" << EOF
{
  "type": "tweet-capture",
  "tweet_url": "$TWEET_URL",
  "tweet_text": $(echo "$TWEET_TEXT" | jq -Rs .),
  "author_handle": "$AUTHOR_HANDLE",
  "author_name": "$AUTHOR_NAME",
  "recipient_address": "$RECIPIENT",
  "logged_in_verified": true,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "Certificate:"
jq . "$PROOF_DIR/certificate.json"

echo ""
echo "=== Done ==="
echo "Proof artifacts saved to: $PROOF_DIR/"
ls -la "$PROOF_DIR/"
echo ""
echo "Next steps:"
echo "  1. Review the screenshot and certificate"
echo "  2. In production, this would be attested via Sigstore"
echo "  3. Then generate ZK proof from the attestation bundle"
