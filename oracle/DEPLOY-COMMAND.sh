#!/bin/bash
# Deploy PredictionMarket V3 to Base Sepolia

cd oracle/foundry-tests

# Step 1: Deploy contract
echo "Deploying PredictionMarket V3..."
forge create src/PredictionMarketV3.sol:PredictionMarket \
  --rpc-url https://sepolia.base.org \
  --private-key $(jq -r '.private_key' ~/.openclaw-secrets/github-zktls-wallet.json) \
  --constructor-args 0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725 \
  --json | tee deploy-output.json

# Extract deployed address
CONTRACT=$(jq -r '.deployedTo' deploy-output.json)
echo "Deployed to: $CONTRACT"

# Step 2: Verify on Basescan
echo "Verifying contract..."
forge verify-contract \
  $CONTRACT \
  src/PredictionMarketV3.sol:PredictionMarket \
  --chain-id 84532 \
  --etherscan-api-key GQG6MI5VZJMYSHE7GHJJ32EUPJF3INUPCX \
  --constructor-args $(cast abi-encode "constructor(address)" 0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725)

echo "Contract deployed and verified at: $CONTRACT"
echo "SigstoreVerifier: 0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725"
echo ""
echo "Next: Create market for topic 27685 with keyword 'security'"
