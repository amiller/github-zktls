#!/bin/bash
# Test wormhole with Docker simulating GitHub runner
set -e

cd "$(dirname "$0")"

echo "=== Building Docker image ==="
docker build -f Dockerfile.test -t wormhole-runner .

echo -e "\n=== Starting client to generate offer ==="
# Generate offer locally
export PATH="$HOME/.nvm/versions/node/v24.2.0/bin:$PATH"

node -e "
import nodeDataChannel from 'node-datachannel'
const { PeerConnection } = nodeDataChannel
const pc = new PeerConnection('client', { iceServers: ['stun:stun.l.google.com:19302'] })
pc.createDataChannel('proxy')
await new Promise(r => setTimeout(r, 1500))
const offer = pc.localDescription()
console.log(Buffer.from(JSON.stringify({ sdp: offer.sdp, type: offer.type })).toString('base64'))
pc.close()
" > /tmp/offer.b64

OFFER=$(cat /tmp/offer.b64)
echo "Offer generated: ${OFFER:0:50}..."

echo -e "\n=== Starting runner in Docker ==="
# Run runner container with offer, expose port 1080
docker run --rm -d --name wormhole-test \
  -e OFFER="$OFFER" \
  -p 1080:1080 \
  wormhole-runner

echo "Waiting for runner to start..."
sleep 5

echo -e "\n=== Checking runner logs ==="
docker logs wormhole-test 2>&1 | head -20

echo -e "\n=== Cleanup ==="
docker stop wormhole-test || true
