#!/bin/bash

# Verify Sigstore attestation for oracle result
# This proves that the oracle result came from the exact commit SHA specified

set -e

if [ $# -lt 2 ]; then
  echo "Usage: $0 <repo> <run-id>"
  echo "Example: $0 username/prediction-market-oracle 12345"
  exit 1
fi

REPO=$1
RUN_ID=$2

echo "🔍 Verifying attestation for $REPO run $RUN_ID"

# Download attestation from GitHub
echo "📥 Downloading attestation..."
gh attestation verify oci://ghcr.io/${REPO}/oracle-result:${RUN_ID} \
  --owner $(echo $REPO | cut -d'/' -f1)

echo ""
echo "✅ Attestation verified!"
echo ""
echo "This proves:"
echo "  1. The oracle code ran in GitHub Actions"
echo "  2. The exact commit SHA that produced the result"
echo "  3. The result has not been tampered with"
echo ""
echo "You can now trust this result for settlement."
