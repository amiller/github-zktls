#!/usr/bin/env bash
# sealed-box.sh — Full end-to-end sealed box from the terminal.
#
# Usage:
#   ./sealed-box.sh "my secret message"           # dispatch + submit + verify
#   ./sealed-box.sh --submit <run-id> "message"   # submit to an existing run
#   ./sealed-box.sh --verify <run-id>             # verify attestation linkage
#
# Prerequisites: openssl, gh (authenticated), jq

set -euo pipefail

REPO="${REPO:-amiller/github-zktls}"
REF="${REF:-sealed-box}"
WINDOW="${WINDOW:-5}"

# --- helpers ---

poll_run_id() {
  echo "Waiting for workflow run to start..." >&2
  for i in $(seq 1 60); do
    RUN=$(gh run list -R "$REPO" -w "Sealed Box" -L1 --json databaseId,status -q '.[] | select(.status=="in_progress" or .status=="queued") | .databaseId' 2>/dev/null || true)
    if [ -n "$RUN" ]; then
      echo "Run started: $RUN" >&2
      echo "$RUN"
      return 0
    fi
    sleep 2
  done
  echo "Timed out waiting for run to start" >&2
  return 1
}

poll_artifact() {
  local run_id="$1"
  local name="$2"
  echo "Waiting for $name artifact..."
  for i in $(seq 1 60); do
    ARTIFACT_ID=$(gh api "repos/$REPO/actions/runs/$run_id/artifacts" --jq ".artifacts[] | select(.name==\"$name\") | .id" 2>/dev/null || true)
    if [ -n "$ARTIFACT_ID" ]; then
      echo "Artifact ready: $name ($ARTIFACT_ID)"
      return 0
    fi
    sleep 5
  done
  echo "Timed out waiting for artifact $name" >&2
  return 1
}

poll_issue() {
  local run_id="$1"
  echo "Waiting for message bus issue..." >&2
  for i in $(seq 1 60); do
    ISSUE=$(gh issue list -R "$REPO" -l sealed-box --json number,title -q ".[] | select(.title | contains(\"$run_id\")) | .number" 2>/dev/null || true)
    if [ -n "$ISSUE" ]; then
      echo "Message bus: issue #$ISSUE" >&2
      echo "$ISSUE"
      return 0
    fi
    sleep 5
  done
  echo "Timed out waiting for issue" >&2
  return 1
}

download_pubkey() {
  local run_id="$1"
  local dir="$2"
  mkdir -p "$dir"
  gh run download "$run_id" -R "$REPO" -n sealed-box-pubkey -D "$dir"
  echo "Downloaded pubkey.json to $dir/"
}

verify_attestation() {
  local file="$1"
  echo "Verifying attestation for $file..."
  gh attestation verify "$file" -R "$REPO" 2>&1 || true
}

encrypt_and_submit() {
  local pubkey_pem="$1"
  local issue="$2"
  local message="$3"
  echo "Encrypting message..."
  CIPHER_B64=$(echo -n "$message" | openssl pkeyutl -encrypt -pubin -inkey "$pubkey_pem" -pkeyopt rsa_padding_mode:oaep | base64 -w0)
  BODY="-----BEGIN SEALED BOX MESSAGE-----
$CIPHER_B64
-----END SEALED BOX MESSAGE-----"
  echo "$BODY" | gh issue comment "$issue" -R "$REPO" --body-file -
  echo "Submitted encrypted message to issue #$issue"
}

verify_linkage() {
  local run_id="$1"
  echo ""
  echo "=== Attestation Linkage Verification ==="
  echo ""

  # Get all attestations for the repo and find ones from this run
  ATTESTATIONS=$(gh api "repos/$REPO/attestations" --paginate --jq '.attestations[]' 2>/dev/null)

  echo "$ATTESTATIONS" | jq -c '.' | while read -r att; do
    CERT_B64=$(echo "$att" | jq -r '.bundle.verificationMaterial.certificate.rawBytes // empty')
    [ -z "$CERT_B64" ] && continue

    CERT_PEM=$(echo "$CERT_B64" | base64 -d | openssl x509 -inform DER -outform PEM 2>/dev/null || true)
    [ -z "$CERT_PEM" ] && continue

    RUN_URL=$(echo "$CERT_PEM" | openssl x509 -noout -text 2>/dev/null | \
      grep -oP 'https://github.com/[^/]+/[^/]+/actions/runs/\d+/attempts/\d+' | head -1 || true)
    [ -z "$RUN_URL" ] && continue

    if echo "$RUN_URL" | grep -q "/runs/${run_id}/"; then
      SHA=$(echo "$CERT_PEM" | openssl x509 -noout -text 2>/dev/null | \
        grep -A1 "1.3.6.1.4.1.57264.1.3:" | tail -1 | sed 's/^ *//' || true)
      PAYLOAD_B64=$(echo "$att" | jq -r '.bundle.dsseEnvelope.payload // empty')
      SUBJECT=""
      [ -n "$PAYLOAD_B64" ] && SUBJECT=$(echo "$PAYLOAD_B64" | base64 -d 2>/dev/null | jq -r '.subject[0].name // empty' 2>/dev/null || true)
      echo "  $SUBJECT  run_url=$RUN_URL  sha=$SHA"
    fi
  done

  echo ""
  echo "If both attestations show the same run_url and sha, the private key"
  echo "only existed during that single execution."
}

# --- commands ---

cmd_full() {
  local message="$1"

  echo "=== Sealed Box ==="
  echo "Message: $message"
  echo "Window: ${WINDOW} minutes"
  echo ""

  # 1. Dispatch
  echo "Dispatching workflow..."
  gh workflow run sealed-box.yml -R "$REPO" --ref "$REF" -f window_minutes="$WINDOW"

  sleep 3

  # 2. Wait for run
  RUN_ID=$(poll_run_id)

  # 3. Wait for pubkey artifact
  poll_artifact "$RUN_ID" "sealed-box-pubkey"

  # 4. Download and verify pubkey
  WORKDIR=$(mktemp -d)
  download_pubkey "$RUN_ID" "$WORKDIR"

  jq -r .pubkey_pem "$WORKDIR/pubkey.json" > "$WORKDIR/pubkey.pem"
  echo ""
  echo "Pubkey: $WORKDIR/pubkey.pem"
  verify_attestation "$WORKDIR/pubkey.json"

  # 5. Find the message bus issue
  ISSUE=$(poll_issue "$RUN_ID")

  # 6. Encrypt and submit
  encrypt_and_submit "$WORKDIR/pubkey.pem" "$ISSUE" "$message"

  # 7. Wait for run to complete
  echo ""
  echo "Waiting for sealed box to close..."
  gh run watch "$RUN_ID" -R "$REPO" || true

  # 8. Download result
  echo ""
  gh run download "$RUN_ID" -R "$REPO" -n sealed-box-result -D "$WORKDIR"
  echo "Result:"
  jq . "$WORKDIR/result.json"

  # 9. Verify
  verify_attestation "$WORKDIR/result.json"
  verify_linkage "$RUN_ID"

  echo ""
  echo "Artifacts saved to: $WORKDIR"
}

cmd_submit() {
  local run_id="$1"
  local message="$2"

  # Download pubkey
  WORKDIR=$(mktemp -d)
  download_pubkey "$run_id" "$WORKDIR"
  jq -r .pubkey_pem "$WORKDIR/pubkey.json" > "$WORKDIR/pubkey.pem"
  echo "Pubkey: $WORKDIR/pubkey.pem"
  verify_attestation "$WORKDIR/pubkey.json"

  # Find issue
  ISSUE=$(poll_issue "$run_id")

  # Submit
  encrypt_and_submit "$WORKDIR/pubkey.pem" "$ISSUE" "$message"
}

cmd_verify() {
  local run_id="$1"

  WORKDIR=$(mktemp -d)
  gh run download "$run_id" -R "$REPO" -n sealed-box-pubkey -D "$WORKDIR" 2>/dev/null || true
  gh run download "$run_id" -R "$REPO" -n sealed-box-result -D "$WORKDIR" 2>/dev/null || true

  [ -f "$WORKDIR/pubkey.json" ] && verify_attestation "$WORKDIR/pubkey.json"
  [ -f "$WORKDIR/result.json" ] && verify_attestation "$WORKDIR/result.json"
  verify_linkage "$run_id"
}

# --- main ---

for cmd in openssl gh jq; do
  command -v "$cmd" >/dev/null || { echo "Missing: $cmd"; exit 1; }
done

case "${1:-}" in
  --submit)
    [ $# -lt 3 ] && { echo "Usage: $0 --submit <run-id> <message>"; exit 1; }
    cmd_submit "$2" "$3"
    ;;
  --verify)
    [ $# -lt 2 ] && { echo "Usage: $0 --verify <run-id>"; exit 1; }
    cmd_verify "$2"
    ;;
  -h|--help|"")
    echo "Usage:"
    echo "  $0 \"message\"                    Full flow: dispatch + submit + verify"
    echo "  $0 --submit <run-id> \"message\"  Submit to existing run"
    echo "  $0 --verify <run-id>            Verify attestation linkage"
    echo ""
    echo "Environment:"
    echo "  REPO=$REPO  REF=$REF  WINDOW=$WINDOW"
    ;;
  --*)
    echo "Unknown flag: $1" >&2; exit 1
    ;;
  *)
    cmd_full "$1"
    ;;
esac
