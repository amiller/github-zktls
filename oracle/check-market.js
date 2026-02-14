#!/usr/bin/env node

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

async function main() {
  const deployment = JSON.parse(fs.readFileSync('./deployment-v3.json'));
  const provider = new ethers.JsonRpcProvider('https://sepolia.base.org');
  const contract = new ethers.Contract(deployment.address, deployment.abi, provider);
  
  const marketId = 2;
  
  console.log('Checking market', marketId);
  const market = await contract.getMarket(marketId);
  
  console.log('\nMarket Details:');
  console.log('Description:', market[0]);
  console.log('Deadline:', new Date(Number(market[3]) * 1000).toLocaleString());
  console.log('Deadline timestamp:', Number(market[3]));
  console.log('Current timestamp:', Math.floor(Date.now() / 1000));
  console.log('Settled:', market[4]);
  console.log('Result:', market[5]);
  console.log('YES pool:', ethers.formatEther(market[6]), 'ETH');
  console.log('NO pool:', ethers.formatEther(market[7]), 'ETH');
  
  if (Number(market[3]) < Math.floor(Date.now() / 1000)) {
    console.log('\n⚠️  Deadline has PASSED! Cannot bet anymore.');
  } else {
    console.log('\n✅ Deadline is in the future. Betting should work.');
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('Error:', error.message);
    process.exit(1);
  });
