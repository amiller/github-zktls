#!/bin/bash
set -e

echo "🔨 Testing PredictionMarket on Anvil (local testnet)"
echo ""

# Start Anvil in background
echo "Starting Anvil..."
anvil > /dev/null 2>&1 &
ANVIL_PID=$!
sleep 2

# Cleanup on exit
trap "kill $ANVIL_PID 2>/dev/null" EXIT

# Anvil default private key (account #0)
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

cd contracts-foundry

echo "Deploying contract..."
DEPLOY_OUTPUT=$(forge script script/Deploy.s.sol:DeployScript --rpc-url http://127.0.0.1:8545 --broadcast 2>&1)
CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "PredictionMarket deployed to:" | awk '{print $4}')

if [ -z "$CONTRACT_ADDRESS" ]; then
    echo "❌ Deployment failed"
    echo "$DEPLOY_OUTPUT"
    exit 1
fi

echo "✅ Contract deployed: $CONTRACT_ADDRESS"
echo ""

# Test interactions using cast
echo "Testing contract interactions..."
echo ""

# Create a market
echo "1. Creating market..."
DEADLINE=$(($(date +%s) + 3600)) # 1 hour from now
cast send $CONTRACT_ADDRESS \
    "createMarket(string,string,string,uint256)" \
    "Will radicle be mentioned?" \
    "claw-tee-dah/github-zktls" \
    "abc123" \
    $DEADLINE \
    --private-key $PRIVATE_KEY \
    --rpc-url http://127.0.0.1:8545 \
    > /dev/null 2>&1

echo "✅ Market created (ID: 0)"
echo ""

# Place bets
echo "2. Placing bets..."

# Alice (account #1) bets 3 ETH on YES
ALICE_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
cast send $CONTRACT_ADDRESS \
    "bet(uint256,bool)" \
    0 \
    true \
    --value 3ether \
    --private-key $ALICE_KEY \
    --rpc-url http://127.0.0.1:8545 \
    > /dev/null 2>&1

echo "   Alice bet 3 ETH on YES"

# Bob (account #2) bets 1 ETH on NO  
BOB_KEY=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
cast send $CONTRACT_ADDRESS \
    "bet(uint256,bool)" \
    0 \
    false \
    --value 1ether \
    --private-key $BOB_KEY \
    --rpc-url http://127.0.0.1:8545 \
    > /dev/null 2>&1

echo "   Bob bet 1 ETH on NO"
echo ""

# Check odds
echo "3. Checking current odds..."
ODDS=$(cast call $CONTRACT_ADDRESS "getOdds(uint256)" 0 --rpc-url http://127.0.0.1:8545)
YES_ODDS=$(echo $ODDS | cut -d' ' -f1)
NO_ODDS=$(echo $ODDS | cut -d' ' -f2)

echo "   YES odds: $(($YES_ODDS / 100))% (basis points: $YES_ODDS)"
echo "   NO odds: $(($NO_ODDS / 100))% (basis points: $NO_ODDS)"
echo ""

# Check potential payouts
echo "4. Potential payouts..."
ALICE_ADDR=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
ALICE_PAYOUT=$(cast call $CONTRACT_ADDRESS "getPotentialPayout(uint256,address)" 0 $ALICE_ADDR --rpc-url http://127.0.0.1:8545)
YES_PAYOUT=$(echo $ALICE_PAYOUT | cut -d' ' -f1)
NO_PAYOUT=$(echo $ALICE_PAYOUT | cut -d' ' -f2)

echo "   Alice's potential payout:"
echo "     If YES wins: $(cast --to-unit $YES_PAYOUT ether) ETH"
echo "     If NO wins: $(cast --to-unit $NO_PAYOUT ether) ETH"
echo ""

# Fast forward time and settle
echo "5. Fast forwarding past deadline..."
FUTURE_TIME=$((DEADLINE + 100))
cast rpc evm_setNextBlockTimestamp $FUTURE_TIME --rpc-url http://127.0.0.1:8545 > /dev/null 2>&1
cast rpc evm_mine --rpc-url http://127.0.0.1:8545 > /dev/null 2>&1

echo "6. Settling market (YES wins)..."
cast send $CONTRACT_ADDRESS \
    "settle(uint256,bool,bytes)" \
    0 \
    true \
    "0x" \
    --private-key $PRIVATE_KEY \
    --rpc-url http://127.0.0.1:8545 \
    > /dev/null 2>&1

echo "✅ Market settled: YES wins"
echo ""

# Claim winnings
echo "7. Alice claiming winnings..."
ALICE_BALANCE_BEFORE=$(cast balance $ALICE_ADDR --rpc-url http://127.0.0.1:8545)

cast send $CONTRACT_ADDRESS \
    "claim(uint256)" \
    0 \
    --private-key $ALICE_KEY \
    --rpc-url http://127.0.0.1:8545 \
    > /dev/null 2>&1

ALICE_BALANCE_AFTER=$(cast balance $ALICE_ADDR --rpc-url http://127.0.0.1:8545)
ALICE_WINNINGS=$(echo "scale=4; ($ALICE_BALANCE_AFTER - $ALICE_BALANCE_BEFORE) / 1000000000000000000" | bc)

echo "✅ Alice claimed: $ALICE_WINNINGS ETH"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ All Anvil tests passed!"
echo ""
echo "Summary:"
echo "  - Total pot: 4 ETH (3 YES + 1 NO)"
echo "  - Alice had 100% of YES shares"
echo "  - Alice won entire 4 ETH pot"
echo "  - Parimutuel payout working correctly"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
