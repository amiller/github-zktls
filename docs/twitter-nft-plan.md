# Plan: Twitter Follower NFT via ZK Proof

## Goal
Create an NFT that proves you have X+ Twitter followers, claimed via a ZK proof of a GitHub Actions attestation.

## Current State
- Browser container captures screenshots via Playwright
- Workflows create attestations with basic metadata
- ZK circuit verifies Sigstore attestations
- Solidity verifier deployed

## Problem
The current flow is complex:
1. Screenshot captured but not parsed
2. No follower count extracted
3. Manual proof generation required
4. No attestation on twitter-proof workflow

## Proposed Solution

### 1. Enhance Twitter Workflow
**File**: `.github/workflows/twitter-proof.yml`

Changes:
- Add page extraction step to parse follower count from DOM
- Add Sigstore attestation (`actions/attest-build-provenance@v2`)
- Output structured JSON with: `username`, `follower_count`, `timestamp`

```yaml
# New step to extract follower count
- name: Extract follower data
  run: |
    curl -X POST http://localhost:3002/extract \
      -H "Content-Type: application/json" \
      -d '{"selector": "a[href$=\"/verified_followers\"] span", "type": "number"}'
```

### 2. Add Extract Endpoint to Bridge
**File**: `browser-container/bridge.js`

Add `/extract` endpoint that:
- Takes CSS selector and extraction type
- Returns parsed value from page DOM
- Supports: number, text, attribute

### 3. New Twitter Follower Circuit
**File**: `zk-github-attestation/circuits/src/twitter_followers.nr`

Simple circuit that proves:
- Public inputs: `username`, `min_followers`, `timestamp`
- Private inputs: `pae_message`, `signature`, `pubkey`, `follower_count`
- Verifies: Sigstore signature, follower_count >= min_followers, username matches

### 4. Twitter NFT Contract
**File**: `zk-github-attestation/contracts/TwitterFollowerNFT.sol`

```solidity
contract TwitterFollowerNFT is ERC721 {
    HonkVerifier public verifier;

    // Mint NFT proving >= minFollowers
    function claim(
        bytes calldata proof,
        string calldata username,
        uint256 minFollowers,
        uint256 timestamp
    ) external returns (uint256 tokenId);

    // Metadata includes follower threshold
    function tokenURI(uint256 tokenId) view returns (string);
}
```

### 5. Claim Flow
1. User runs `twitter-proof` workflow with their username
2. Workflow captures page, extracts follower count, creates attestation
3. User downloads attestation bundle
4. Frontend/CLI generates ZK proof locally
5. User calls `TwitterFollowerNFT.claim()` with proof
6. NFT minted with badge tier based on follower count

## Key Files to Modify

| File | Change |
|------|--------|
| `.github/workflows/twitter-proof.yml` | Add extraction + attestation |
| `browser-container/bridge.js` | Add `/extract` endpoint |
| `browser-container/proof-extension/content.js` | Add selector extraction |
| `zk-github-attestation/circuits/src/twitter_followers.nr` | New circuit |
| `zk-github-attestation/js/src/twitter.ts` | Witness generator |
| `zk-github-attestation/contracts/TwitterFollowerNFT.sol` | NFT contract |

## Circuit Design

```
Public Inputs (on-chain):
- username: [u8; 32] (Twitter username, public for verification)
- min_followers: u32 (threshold proven, e.g., 1000)
- timestamp: u64 (attestation time)

Private Inputs (witness):
- pae_message: [u8; 2048] (DSSE envelope)
- signature: [u8; 64] (ECDSA P-256)
- pubkey_x/y: [u8; 32] each
- follower_count: u32 (actual count from attestation)

Constraints:
1. Verify ECDSA signature over PAE hash
2. Extract username from certificate.json in PAE payload
3. Verify username matches public input
4. Extract follower_count from PAE payload
5. Verify follower_count >= min_followers
```

## NFT Tiers

| Tier | Followers | Badge |
|------|-----------|-------|
| Bronze | 100+ | 🥉 |
| Silver | 1,000+ | 🥈 |
| Gold | 10,000+ | 🥇 |
| Diamond | 100,000+ | 💎 |

## Verification Steps

1. Run workflow locally: `gh workflow run twitter-proof.yml -f profile=socrates1024`
2. Download attestation: `gh run download <run-id>`
3. Generate proof: `npx tsx src/twitter-prove.ts`
4. Deploy contract to testnet
5. Call `claim()` with proof
6. Verify NFT metadata shows correct tier

## Decisions Made

- Username is **public** in the NFT for easy verification

## Open Questions

- [ ] How to handle Twitter rate limiting / bot detection?
- [ ] Should we support proving "exactly N followers" vs "at least N"?

## Working Toolchain (from previous sessions)

| Component | Version |
|-----------|---------|
| nargo | `1.0.0-beta.17` |
| bb.js | `3.0.0-rc.5` |
| noir_js | `1.0.0-beta.17` |

Commands:
```bash
noirup -v 1.0.0-beta.17
cd zk-github-attestation/circuits && ~/.nargo/bin/nargo compile
cd ../js && npm install && npx tsx src/prove.ts
```
