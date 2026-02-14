# Contract Verification Guide

## Contract Details

**Address:** `0x2bE419BCB663136b16cF2D163E309ECaf6B9887b`  
**Network:** Base Sepolia (Chain ID: 84532)  
**Basescan:** https://sepolia.basescan.org/address/0x2bE419BCB663136b16cF2D163E309ECaf6B9887b

## Verification Parameters

### Compiler Settings
- **Compiler Version:** v0.8.20+commit.a1b79de6
- **Optimization:** Enabled (200 runs)
- **License:** MIT (SPDX-License-Identifier: MIT)
- **EVM Version:** paris (default for 0.8.20)

### Constructor Arguments (ABI-encoded)
```
0000000000000000000000000af922925ae3602b0dc23c4cfcf54fabe2f54725
```

Decoded:
- `address _verifier`: `0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725` (SigstoreVerifier)

## Manual Verification Steps

1. **Go to Basescan:**
   https://sepolia.basescan.org/verifyContract?a=0x2bE419BCB663136b16cF2D163E309ECaf6B9887b

2. **Select Verification Method:**
   - Compiler Type: Solidity (Single file)
   - Compiler Version: v0.8.20+commit.a1b79de6
   - Open Source License Type: MIT License (MIT)

3. **Compiler Settings:**
   - Optimization: Yes
   - Runs: 200
   - EVM Version: paris (default)

4. **Contract Source:**
   Copy contents from: `oracle/PredictionMarketV3-flattened.sol`
   
   Or use the flattened source in this repo:
   https://github.com/claw-tee-dah/github-zktls/blob/feature/prediction-market-oracle/oracle/PredictionMarketV3-flattened.sol

5. **Constructor Arguments:**
   Paste:
   ```
   0000000000000000000000000af922925ae3602b0dc23c4cfcf54fabe2f54725
   ```

6. **Click "Verify and Publish"**

## Alternative: API Verification

Using etherscan-verify API (requires API key):

```bash
curl -X POST \
  "https://api-sepolia.basescan.org/api" \
  -d "apikey=YOUR_API_KEY" \
  -d "module=contract" \
  -d "action=verifysourcecode" \
  -d "contractaddress=0x2bE419BCB663136b16cF2D163E309ECaf6B9887b" \
  -d "sourceCode=$(cat PredictionMarketV3-flattened.sol)" \
  -d "codeformat=solidity-single-file" \
  -d "contractname=PredictionMarket" \
  -d "compilerversion=v0.8.20+commit.a1b79de6" \
  -d "optimizationUsed=1" \
  -d "runs=200" \
  -d "constructorArguements=0000000000000000000000000af922925ae3602b0dc23c4cfcf54fabe2f54725"
```

## Verification Checklist

- [ ] Compiler version matches (v0.8.20+commit.a1b79de6)
- [ ] Optimization enabled (200 runs)
- [ ] Constructor arguments correct (SigstoreVerifier address)
- [ ] Source code matches deployed bytecode
- [ ] License type set to MIT

## Expected Result

After successful verification, the contract will show:
- ✅ Source code tab with readable Solidity
- ✅ "Contract Source Code Verified" badge
- ✅ Read Contract and Write Contract tabs enabled
- ✅ Constructor arguments decoded and displayed

## Troubleshooting

**"Bytecode mismatch":**
- Ensure compiler version is exact (including commit hash)
- Verify optimization settings (must be enabled with 200 runs)
- Check that viaIR was used during compilation

**"Constructor arguments invalid":**
- Verify hex encoding is correct (no 0x prefix needed)
- Ensure address is padded to 32 bytes (64 hex chars)

## Files

- **Flattened Source:** `PredictionMarketV3-flattened.sol`
- **Original Source:** `foundry-tests/src/PredictionMarketV3.sol`
- **Interface:** `foundry-tests/src/ISigstoreVerifier.sol`
