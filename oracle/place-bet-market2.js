#!/usr/bin/env node

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

async function main() {
  const deployment = JSON.parse(fs.readFileSync('./deployment-v3.json'));
  const walletData = JSON.parse(fs.readFileSync(
    path.join(process.env.HOME, '.openclaw-secrets/github-zktls-wallet.json')
  ));
  
  const provider = new ethers.JsonRpcProvider('https://sepolia.base.org');
  const wallet = new ethers.Wallet(walletData.private_key, provider);
  const contract = new ethers.Contract(deployment.address, deployment.abi, wallet);
  
  const balance = await provider.getBalance(wallet.address);
  console.log('Wallet balance:', ethers.formatEther(balance), 'ETH');
  
  if (balance < ethers.parseEther('0.0001')) {
    console.log('❌ Insufficient balance');
    return;
  }
  
  console.log('\n💰 Placing bet on market 2 (YES)...');
  
  try {
    const betTx = await contract.bet(2, true, {
      value: ethers.parseEther('0.00005'), // Try smaller amount
      gasLimit: 200000
    });
    
    console.log('TX:', betTx.hash);
    await betTx.wait();
    console.log('✅ Bet placed!');
  } catch (error) {
    console.error('Bet failed:', error.message);
    if (error.data) {
      console.error('Error data:', error.data);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('Error:', error.message);
    process.exit(1);
  });
