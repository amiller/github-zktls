#!/bin/bash
# Generate claim JSON from proof files
# Usage: ./make-claim.sh <proof_dir> <recipient_address>

PROOF_DIR="${1:-.}"
RECIPIENT="${2:-0x_YOUR_ADDRESS_HERE}"

if [ ! -f "$PROOF_DIR/proof.hex" ] || [ ! -f "$PROOF_DIR/inputs.json" ]; then
  echo "Error: proof.hex and inputs.json not found in $PROOF_DIR"
  echo "Usage: $0 <proof_dir> <recipient_address>"
  exit 1
fi

PROOF="0x$(cat "$PROOF_DIR/proof.hex" | tr -d '\n')"
INPUTS=$(cat "$PROOF_DIR/inputs.json")

cat << EOF
{
  "proof": "$PROOF",
  "inputs": $INPUTS,
  "recipient": "$RECIPIENT"
}
EOF
