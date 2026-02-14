# PredictionMarket V3 - Testnet Deployment

## Configuration

**Network:** Base Sepolia
**RPC:** https://sepolia.base.org
**SigstoreVerifier:** `0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725`
**Deployer Wallet:** `~/.openclaw-secrets/github-zktls-wallet.json`
**Etherscan API Key:** `GQG6MI5VZJMYSHE7GHJJ32EUPJF3INUPCX`

## Immediately Settleable Market

**Topic:** 27685 - "New ERC: Facet-Based Diamonds"
**Keyword:** "security"
**Oracle Type:** "first"
**First Comment:** Posted Feb 8, 2026 by radek
**Contains keyword:** ✅ YES (word "security" appears multiple times)

## Deployment Steps

1. Deploy PredictionMarket contract
2. Verify source code on Basescan
3. Create market for topic 27685
4. Run oracle workflow
5. Generate ZK proof
6. Settle market
7. Test claiming

## Expected Behavior

- Market should settle as **YES** (keyword found in first comment)
- Oracle will return `{settleable: true, found: true, result: "FOUND"}`
- Anyone can settle with valid proof
- No trustedSettler needed (trustless!)
