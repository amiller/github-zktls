#!/usr/bin/env node

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

async function main() {
  // Load deployment info
  const deployment = JSON.parse(fs.readFileSync('./deployment-v3.json'));
  
  // Load wallet
  const walletData = JSON.parse(fs.readFileSync(
    path.join(process.env.HOME, '.openclaw-secrets/github-zktls-wallet.json')
  ));
  
  const provider = new ethers.JsonRpcProvider('https://sepolia.base.org');
  const wallet = new ethers.Wallet(walletData.private_key, provider);
  
  const contract = new ethers.Contract(deployment.address, deployment.abi, wallet);
  
  console.log('📝 Creating market...');
  console.log('Topic: 27685 (Facet-Based Diamonds)');
  console.log('Keyword: security');
  console.log('Oracle: first comment');
  
  // Market parameters
  const description = 'Will "security" appear in the first comment of topic 27685?';
  const topicId = '27685';
  const keyword = 'security';
  const oracleType = 'first';
  const oracleCommitSha = '0x0000000000000000000000000000000000000000'; // Use any commit for testing
  const deadline = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
  
  const createTx = await contract.createMarket(
    description,
    topicId,
    keyword,
    oracleType,
    oracleCommitSha,
    deadline
  );
  
  console.log('Create market TX:', createTx.hash);
  const createReceipt = await createTx.wait();
  
  // Get market ID from event
  const marketCreatedEvent = createReceipt.logs.find(
    log => log.topics[0] === ethers.id('MarketCreated(uint256,string,bytes32,bytes20,uint256)')
  );
  
  const marketId = parseInt(marketCreatedEvent.topics[1], 16);
  console.log('✅ Market created! ID:', marketId);
  
  // Place bet on YES (keyword will be found)
  console.log('\n💰 Placing 0.0001 ETH bet on YES...');
  
  const betTx = await contract.bet(marketId, true, {
    value: ethers.parseEther('0.0001')
  });
  
  console.log('Bet TX:', betTx.hash);
  await betTx.wait();
  
  console.log('✅ Bet placed!');
  
  // Get market details
  const market = await contract.getMarket(marketId);
  console.log('\n📊 Market status:');
  console.log('Description:', market[0]);
  console.log('Deadline:', new Date(Number(market[3]) * 1000).toLocaleString());
  console.log('YES pool:', ethers.formatEther(market[6]), 'ETH');
  console.log('NO pool:', ethers.formatEther(market[7]), 'ETH');
  
  // Save market info
  const marketInfo = {
    marketId,
    topicId,
    keyword,
    oracleType,
    contractAddress: deployment.address,
    betAmount: '0.0001',
    position: 'YES',
    expectedResult: 'YES (keyword found in first comment)',
    createdAt: new Date().toISOString()
  };
  
  fs.writeFileSync('./market-info.json', JSON.stringify(marketInfo, null, 2));
  
  console.log('\n📝 Market info saved to market-info.json');
  console.log('\n✨ Ready to settle!');
  console.log('\nNext: Run oracle to check topic 27685');
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('❌ Error:', error.message);
    process.exit(1);
  });
