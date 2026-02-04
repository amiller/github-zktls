#!/bin/bash
# Verify Twitter login by hitting a simple API endpoint
# Usage: ./verify-twitter-login.sh <session_file>

set -e

SESSION_FILE="${1:?Usage: $0 <session_file>}"

if [ ! -f "$SESSION_FILE" ]; then
  echo "Session file not found: $SESSION_FILE" >&2
  exit 1
fi

# Extract auth_token and ct0 from session file
AUTH_TOKEN=$(jq -r '.cookies[] | select(.name == "auth_token") | .value' "$SESSION_FILE")
CT0=$(jq -r '.cookies[] | select(.name == "ct0") | .value' "$SESSION_FILE")

if [ -z "$AUTH_TOKEN" ] || [ "$AUTH_TOKEN" = "null" ]; then
  echo "auth_token not found in session file" >&2
  exit 1
fi

if [ -z "$CT0" ] || [ "$CT0" = "null" ]; then
  echo "ct0 not found in session file" >&2
  exit 1
fi

# Bearer token (this is public, used by Twitter web client)
BEARER="AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"

# Try the settings endpoint - returns current user info
RESPONSE=$(curl -s "https://api.x.com/1.1/account/settings.json" \
  -H "Authorization: Bearer $BEARER" \
  -H "X-Csrf-Token: $CT0" \
  -H "Cookie: auth_token=$AUTH_TOKEN; ct0=$CT0")

# Debug output
echo "Response: $RESPONSE" >&2

# Extract screen_name from settings
USERNAME=$(echo "$RESPONSE" | jq -r '.screen_name // empty')

if [ -z "$USERNAME" ]; then
  echo "Could not extract username" >&2
  exit 1
fi

echo "$USERNAME"
