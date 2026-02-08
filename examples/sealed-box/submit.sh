#!/usr/bin/env bash
# Submit an encrypted message to a running sealed box.
#
# Usage: ./submit.sh <run-id> <message>
#        ./submit.sh <run-id> -          # read from stdin
#
# Prerequisites: openssl, gh (authenticated), jq
#
# Downloads the attested pubkey from the run, verifies it, encrypts
# the message (RSA-OAEP), and posts it to the message bus issue.

set -euo pipefail

REPO="${REPO:-amiller/github-zktls}"

if [ $# -lt 2 ]; then
  echo "Usage: $0 <run-id> <message|->"
  exit 1
fi

RUN_ID="$1"
MESSAGE="$2"

for cmd in openssl gh jq; do
  command -v "$cmd" >/dev/null || { echo "Missing: $cmd"; exit 1; }
done

# Download pubkey artifact
WORKDIR=$(mktemp -d)
gh run download "$RUN_ID" -R "$REPO" -n sealed-box-pubkey -D "$WORKDIR"
jq -r .pubkey_pem "$WORKDIR/pubkey.json" > "$WORKDIR/pubkey.pem"
echo "Pubkey: $WORKDIR/pubkey.pem"

# Verify attestation
echo "Verifying attestation..."
gh attestation verify "$WORKDIR/pubkey.json" -R "$REPO" 2>&1 || true

# Find message bus issue
ISSUE=$(gh issue list -R "$REPO" -l sealed-box --json number,title -q ".[] | select(.title | contains(\"$RUN_ID\")) | .number")
[ -z "$ISSUE" ] && { echo "No message bus issue found for run $RUN_ID"; exit 1; }

# Encrypt and submit (RSA-OAEP)
if [ "$MESSAGE" = "-" ]; then
  CIPHER_B64=$(openssl pkeyutl -encrypt -pubin -inkey "$WORKDIR/pubkey.pem" -pkeyopt rsa_padding_mode:oaep | base64 -w0)
else
  CIPHER_B64=$(echo -n "$MESSAGE" | openssl pkeyutl -encrypt -pubin -inkey "$WORKDIR/pubkey.pem" -pkeyopt rsa_padding_mode:oaep | base64 -w0)
fi

BODY="-----BEGIN SEALED BOX MESSAGE-----
$CIPHER_B64
-----END SEALED BOX MESSAGE-----"
echo "$BODY" | gh issue comment "$ISSUE" -R "$REPO" --body-file -
echo "Submitted to issue #$ISSUE"
