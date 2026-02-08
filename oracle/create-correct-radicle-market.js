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
  
  console.log('📝 Creating CORRECT "radicle" market...');
  console.log('Topic: 27661 (GitHub Actions Attestation Verification - your ERC proposal)');
  
  // Market parameters for the ACTUAL github-zktls post
  const description = 'Will "radicle" appear in the first comment of topic 27661 (GitHub Actions ERC)?';
  const topicId = '27661'; // The actual github-zktls topic
  const keyword = 'radicle';
  const oracleType = 'first';
  const oracleCommitSha = '0x0000000000000000000000000000000000000000';
  const deadline = Math.floor(Date.now() / 1000) + (7 * 86400); // 1 week from now
  
  console.log('Topic ID:', topicId);
  console.log('Keyword:', keyword);
  console.log('Deadline:', new Date(deadline * 1000).toLocaleString());
  console.log('\n⚠️  Note: Topic has NO comments yet (not settleable until first comment posted)');
  
  const createTx = await contract.createMarket(
    description,
    topicId,
    keyword,
    oracleType,
    oracleCommitSha,
    deadline
  );
  
  console.log('\nCreate market TX:', createTx.hash);
  const createReceipt = await createTx.wait();
  
  // Get market ID from event
  const marketCreatedEvent = createReceipt.logs.find(
    log => log.topics[0] === ethers.id('MarketCreated(uint256,string,bytes32,bytes20,uint256)')
  );
  
  const marketId = parseInt(marketCreatedEvent.topics[1], 16);
  console.log('✅ Market created! ID:', marketId);
  
  // Place small bet
  console.log('\n💰 Placing 0.0001 ETH bet on YES (radicle will be mentioned)...');
  
  const betTx = await contract.bet(marketId, true, {
    value: ethers.parseEther('0.0001')
  });
  
  console.log('Bet TX:', betTx.hash);
  await betTx.wait();
  
  console.log('✅ Bet placed on YES!');
  
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
    description,
    topicTitle: 'ERC Proposal: GitHub Actions Attestation Verification',
    topicUrl: `https://ethereum-magicians.org/t/27661`,
    currentStatus: 'NO_COMMENTS (not settleable until first comment posted)',
    deadline: new Date(deadline * 1000).toISOString(),
    createdAt: new Date().toISOString()
  };
  
  fs.writeFileSync('./radicle-market-27661.json', JSON.stringify(marketInfo, null, 2));
  
  console.log('\n📝 Market info saved to radicle-market-27661.json');
  console.log('\n✨ Correct radicle market created!');
  console.log('Contract:', deployment.address);
  console.log('Market ID:', marketId);
  console.log('\nWaiting for first comment on topic 27661...');
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('❌ Error:', error.message);
    process.exit(1);
  });
