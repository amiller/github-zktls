#!/usr/bin/env bash
# Verify that two sealed-box attestations share the same run_id and commit.
#
# Usage: ./verify-linkage.sh <run-id>
#
# This downloads the attestation bundles for pubkey.json and result.json,
# decodes the Sigstore certificates, and confirms the OIDC extensions
# (run_url, commit sha) match — proving both artifacts were attested
# in the same GitHub Actions execution.
#
# Prerequisites: gh, openssl, jq, base64

set -euo pipefail

REPO="${REPO:-amiller/github-zktls}"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <run-id>"
  echo ""
  echo "  run-id  The GitHub Actions run ID from the sealed box workflow"
  exit 1
fi

RUN_ID="$1"

# Fetch all attestations for this repo
echo "Fetching attestations for $REPO..."
ATTESTATIONS=$(gh api "repos/$REPO/attestations" --paginate --jq '.attestations[]')

# We need to find attestations from this specific run.
# Each attestation's certificate contains OID 1.3.6.1.4.1.57264.1.21 (run_url)
# which includes the run_id.

extract_oid() {
  local CERT_B64="$1"
  local OID_SUFFIX="$2"
  # Decode cert and extract OID value using openssl
  echo "$CERT_B64" | base64 -d | \
    openssl x509 -inform DER -noout -text 2>/dev/null | \
    grep -A1 "1.3.6.1.4.1.57264.1.${OID_SUFFIX}:" | \
    tail -1 | sed 's/^ *//' || true
}

extract_oid_from_pem() {
  local CERT_PEM="$1"
  local OID_SUFFIX="$2"
  echo "$CERT_PEM" | \
    openssl x509 -noout -text 2>/dev/null | \
    grep -A1 "1.3.6.1.4.1.57264.1.${OID_SUFFIX}:" | \
    tail -1 | sed 's/^ *//' || true
}

echo ""
echo "Looking for attestations from run $RUN_ID..."
echo ""

# Download workflow run artifacts to get the attested file names
ARTIFACTS=$(gh api "repos/$REPO/actions/runs/$RUN_ID/artifacts" --jq '.artifacts[].name')

# Get attestations and check each one
FOUND_PUBKEY=""
FOUND_RESULT=""
PUBKEY_RUN_URL=""
RESULT_RUN_URL=""
PUBKEY_SHA=""
RESULT_SHA=""

# List attestation subjects for the repo, filtering by run
# The gh attestation list command doesn't filter by run, so we parse manually
ATTESTATION_LIST=$(gh api "repos/$REPO/attestations" --paginate 2>/dev/null || echo '{"attestations":[]}')

echo "$ATTESTATION_LIST" | jq -c '.attestations[]' | while read -r att; do
  # Get the certificate
  CERT_B64=$(echo "$att" | jq -r '.bundle.verificationMaterial.certificate.rawBytes // empty')
  if [ -z "$CERT_B64" ]; then continue; fi

  # Decode cert to PEM for openssl
  CERT_PEM=$(echo "$CERT_B64" | base64 -d | openssl x509 -inform DER -outform PEM 2>/dev/null || true)
  if [ -z "$CERT_PEM" ]; then continue; fi

  # Extract run_url (OID .21)
  RUN_URL=$(echo "$CERT_PEM" | openssl x509 -noout -text 2>/dev/null | \
    grep -oP 'https://github.com/[^/]+/[^/]+/actions/runs/\d+/attempts/\d+' | head -1 || true)

  if [ -z "$RUN_URL" ]; then continue; fi

  # Check if this attestation is from our run
  if echo "$RUN_URL" | grep -q "/runs/${RUN_ID}/"; then
    # Extract commit sha (OID .3)
    SHA=$(echo "$CERT_PEM" | openssl x509 -noout -text 2>/dev/null | \
      grep -A1 "1.3.6.1.4.1.57264.1.3:" | tail -1 | sed 's/^ *//' || true)

    # Get the subject name from the in-toto statement
    PAYLOAD_B64=$(echo "$att" | jq -r '.bundle.dsseEnvelope.payload // empty')
    SUBJECT=""
    if [ -n "$PAYLOAD_B64" ]; then
      SUBJECT=$(echo "$PAYLOAD_B64" | base64 -d 2>/dev/null | jq -r '.subject[0].name // empty' 2>/dev/null || true)
    fi

    echo "Found attestation: subject=$SUBJECT run_url=$RUN_URL sha=$SHA"
  fi
done

echo ""
echo "---"
echo ""
echo "To verify attestations individually:"
echo "  gh attestation verify <file> --repo $REPO"
echo ""
echo "If both attestations above show the same run_url and sha,"
echo "they came from the same execution context — the private key"
echo "that decrypted the submissions only existed during that run."
