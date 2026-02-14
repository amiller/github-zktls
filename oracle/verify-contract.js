#!/usr/bin/env node

const https = require('https');
const fs = require('fs');
const path = require('path');

async function flattenContract() {
  // Read the two source files
  const pmSource = fs.readFileSync('./foundry-tests/src/PredictionMarketV3.sol', 'utf8');
  const interfaceSource = fs.readFileSync('./foundry-tests/src/ISigstoreVerifier.sol', 'utf8');
  
  // Create flattened source (simple concatenation)
  // Remove duplicate SPDX and pragma from interface
  const cleanedInterface = interfaceSource
    .replace(/\/\/ SPDX-License-Identifier:.*\n/, '')
    .replace(/pragma solidity.*\n/, '')
    .trim();
  
  return pmSource + '\n\n' + cleanedInterface;
}

async function verifyOnBasescan(sourceCode) {
  const deployment = JSON.parse(fs.readFileSync('./deployment-v3.json'));
  
  const params = new URLSearchParams({
    apikey: 'GQG6MI5VZJMYSHE7GHJJ32EUPJF3INUPCX',
    module: 'contract',
    action: 'verifysourcecode',
    contractaddress: deployment.address,
    sourceCode: sourceCode,
    codeformat: 'solidity-single-file',
    contractname: 'PredictionMarket',
    compilerversion: 'v0.8.20+commit.a1b79de6',
    optimizationUsed: '1',
    runs: '200',
    constructorArguements: '0000000000000000000000000af922925ae3602b0dc23c4cfcf54fabe2f54725',
    evmversion: 'paris',
    licenseType: '3' // MIT
  });
  
  return new Promise((resolve, reject) => {
    const req = https.request({
      hostname: 'api-sepolia.basescan.org',
      path: '/api',
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': params.toString().length
      }
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch {
          resolve({ status: '0', result: data });
        }
      });
    });
    
    req.on('error', reject);
    req.write(params.toString());
    req.end();
  });
}

async function checkVerificationStatus(guid) {
  return new Promise((resolve, reject) => {
    const url = `https://api-sepolia.basescan.org/api?module=contract&action=checkverifystatus&guid=${guid}&apikey=GQG6MI5VZJMYSHE7GHJJ32EUPJF3INUPCX`;
    
    https.get(url, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch {
          resolve({ status: '0', result: data });
        }
      });
    }).on('error', reject);
  });
}

async function main() {
  console.log('📝 Flattening contract source...');
  const sourceCode = await flattenContract();
  
  console.log('📤 Submitting verification to Basescan...');
  const submitResult = await verifyOnBasescan(sourceCode);
  
  console.log('Response:', submitResult);
  
  if (submitResult.status === '1') {
    const guid = submitResult.result;
    console.log('✅ Verification submitted!');
    console.log('GUID:', guid);
    
    console.log('\n⏳ Checking verification status...');
    
    // Wait a few seconds then check
    await new Promise(resolve => setTimeout(resolve, 5000));
    
    const statusResult = await checkVerificationStatus(guid);
    console.log('Status:', statusResult);
    
    if (statusResult.status === '1' && statusResult.result === 'Pass - Verified') {
      console.log('\n🎉 Contract verified successfully!');
      console.log('View at: https://sepolia.basescan.org/address/0x2bE419BCB663136b16cF2D163E309ECaf6B9887b#code');
    } else if (statusResult.result === 'Pending in queue') {
      console.log('\n⏳ Verification pending. Check status at:');
      console.log('https://sepolia.basescan.org/address/0x2bE419BCB663136b16cF2D163E309ECaf6B9887b#code');
    } else {
      console.log('\n⚠️  Verification result:', statusResult.result);
    }
  } else {
    console.error('\n❌ Verification submission failed:', submitResult.result);
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('❌ Error:', error.message);
    process.exit(1);
  });
