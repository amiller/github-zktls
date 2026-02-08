#!/usr/bin/env node

/**
 * Settlement Script for Prediction Markets
 * 
 * Downloads workflow artifacts and calls contract settle() with correct parameters
 * 
 * Usage:
 *   node settle-market.js <market_id> <run_id>
 * 
 * Example:
 *   node settle-market.js 0 12345678
 */

const fs = require('fs');
const { exec } = require('child_process');
const util = require('util');
const execPromise = util.promisify(exec);

async function downloadArtifacts(runId) {
  console.log(`📥 Downloading artifacts from run ${runId}...`);
  
  try {
    // Download using gh CLI
    await execPromise(`gh run download ${runId}`);
    
    // Find the oracle-result directory
    const dirs = fs.readdirSync('.');
    const resultDir = dirs.find(d => d.startsWith('oracle-result-'));
    
    if (!resultDir) {
      throw new Error('Oracle result directory not found');
    }
    
    return resultDir;
  } catch (error) {
    throw new Error(`Failed to download artifacts: ${error.message}`);
  }
}

async function loadSettlementData(resultDir) {
  console.log(`📂 Loading settlement data from ${resultDir}...`);
  
  // Load metadata
  const metadataPath = `${resultDir}/attestation/metadata.json`;
  const oracleResultPath = `${resultDir}/oracle-result.json`;
  
  if (!fs.existsSync(metadataPath)) {
    throw new Error('metadata.json not found');
  }
  
  if (!fs.existsSync(oracleResultPath)) {
    throw new Error('oracle-result.json not found');
  }
  
  const metadata = JSON.parse(fs.readFileSync(metadataPath, 'utf8'));
  const oracleResult = JSON.parse(fs.readFileSync(oracleResultPath, 'utf8'));
  
  return {
    topicId: metadata.topic_id,
    keyword: metadata.keyword,
    oracleType: metadata.oracle_type,
    settleable: metadata.settleable === 'true' || metadata.settleable === true,
    resultFound: metadata.result_found === 'true' || metadata.result_found === true,
    commitSha: metadata.commit_sha,
    runId: metadata.run_id,
    timestamp: metadata.timestamp,
    oracleResult
  };
}

async function settleMarket(marketId, settlementData) {
  console.log(`\n📋 Settlement Parameters:`);
  console.log(`   Market ID: ${marketId}`);
  console.log(`   Topic ID: ${settlementData.topicId}`);
  console.log(`   Keyword: ${settlementData.keyword}`);
  console.log(`   Oracle Type: ${settlementData.oracleType}`);
  console.log(`   Settleable: ${settlementData.settleable}`);
  console.log(`   Result Found: ${settlementData.resultFound}`);
  console.log(`   Commit SHA: ${settlementData.commitSha}`);
  console.log(``);
  
  if (!settlementData.settleable) {
    throw new Error('Cannot settle: oracle returned NOT_SETTLEABLE (first comment missing)');
  }
  
  console.log(`🔧 Cast command:`);
  console.log(``);
  console.log(`cast send <CONTRACT_ADDRESS> \\`);
  console.log(`  "settle(uint256,string,string,string,bool,bool,bytes)" \\`);
  console.log(`  ${marketId} \\`);
  console.log(`  "${settlementData.topicId}" \\`);
  console.log(`  "${settlementData.keyword}" \\`);
  console.log(`  "${settlementData.oracleType}" \\`);
  console.log(`  ${settlementData.settleable} \\`);
  console.log(`  ${settlementData.resultFound} \\`);
  console.log(`  "0x" \\`);
  console.log(`  --private-key $PRIVATE_KEY \\`);
  console.log(`  --rpc-url https://sepolia.base.org`);
  console.log(``);
  
  console.log(`\n✅ Parameters verified from attestation!`);
  console.log(`   Oracle run: ${settlementData.runId}`);
  console.log(`   Timestamp: ${settlementData.timestamp}`);
  console.log(``);
  console.log(`To settle, copy the cast command above and run it.`);
}

async function main() {
  const [,, marketId, runId] = process.argv;
  
  if (!marketId || !runId) {
    console.error('Usage: node settle-market.js <market_id> <run_id>');
    console.error('');
    console.error('Example:');
    console.error('  node settle-market.js 0 12345678');
    console.error('');
    console.error('Get run_id from GitHub Actions URL or `gh run list`');
    process.exit(1);
  }
  
  try {
    // Download artifacts
    const resultDir = await downloadArtifacts(runId);
    
    // Load settlement data
    const settlementData = await loadSettlementData(resultDir);
    
    // Generate settlement command
    await settleMarket(marketId, settlementData);
    
  } catch (error) {
    console.error(`\n❌ Error: ${error.message}`);
    process.exit(1);
  }
}

main();
