#!/bin/bash
# Verify a GitHub Actions proof
# Usage: ./verify-proof.sh https://github.com/user/repo/actions/runs/123456789

set -e

RUN_URL=$1

if [ -z "$RUN_URL" ]; then
  echo "Usage: $0 <github-actions-run-url>"
  echo "Example: $0 https://github.com/user/repo/actions/runs/123456789"
  exit 1
fi

# Parse URL
RUN_ID=$(echo "$RUN_URL" | grep -oE '[0-9]+$')
REPO=$(echo "$RUN_URL" | sed 's|https://github.com/||' | sed 's|/actions/runs/.*||')

echo "=== Proof Verification ==="
echo "Repository: $REPO"
echo "Run ID: $RUN_ID"
echo ""

echo "=== Run Metadata ==="
gh run view "$RUN_ID" --repo "$REPO" --json headSha,workflowName,conclusion,createdAt,updatedAt

COMMIT=$(gh run view "$RUN_ID" --repo "$REPO" --json headSha -q .headSha)
CONCLUSION=$(gh run view "$RUN_ID" --repo "$REPO" --json conclusion -q .conclusion)
echo ""

echo "=== Execution Result ==="
echo "Conclusion: $CONCLUSION"
echo "Commit: $COMMIT"
echo ""

# Download artifacts
TMPDIR=$(mktemp -d)
echo "=== Downloading Artifacts ==="
gh run download "$RUN_ID" --repo "$REPO" --dir "$TMPDIR"
echo "Downloaded to: $TMPDIR"
echo ""

echo "=== Proof Certificate ==="
find "$TMPDIR" -name "certificate.json" -exec cat {} \;
echo ""

echo "=== To Audit The Code ==="
echo "git clone https://github.com/$REPO /tmp/audit-repo"
echo "cd /tmp/audit-repo && git checkout $COMMIT"
echo "cat .github/workflows/*.yml"
echo ""

echo "=== Artifact Files ==="
find "$TMPDIR" -type f
