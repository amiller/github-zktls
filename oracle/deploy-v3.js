#!/usr/bin/env node

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

async function main() {
  // Load wallet
  const walletData = JSON.parse(fs.readFileSync(
    path.join(process.env.HOME, '.openclaw-secrets/github-zktls-wallet.json')
  ));
  
  // Connect to Base Sepolia
  const provider = new ethers.JsonRpcProvider('https://sepolia.base.org');
  const wallet = new ethers.Wallet(walletData.private_key, provider);
  
  console.log('Deploying from:', wallet.address);
  
  const balance = await provider.getBalance(wallet.address);
  console.log('Balance:', ethers.formatEther(balance), 'ETH');
  
  // Load compiled contract
  const artifactPath = path.join(__dirname, 'foundry-tests/out/PredictionMarketV3.sol/PredictionMarket.json');
  const artifact = JSON.parse(fs.readFileSync(artifactPath));
  
  const sigstoreVerifier = '0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725';
  
  console.log('\n📦 Deploying PredictionMarket V3...');
  console.log('SigstoreVerifier:', sigstoreVerifier);
  
  const factory = new ethers.ContractFactory(
    artifact.abi,
    artifact.bytecode.object,
    wallet
  );
  
  const contract = await factory.deploy(sigstoreVerifier);
  console.log('Deploy TX:', contract.deploymentTransaction().hash);
  
  await contract.waitForDeployment();
  const address = await contract.getAddress();
  
  console.log('\n✅ PredictionMarket V3 deployed at:', address);
  console.log('Basescan:', `https://sepolia.basescan.org/address/${address}`);
  
  // Save deployment info
  const deploymentInfo = {
    address,
    deployer: wallet.address,
    sigstoreVerifier,
    network: 'Base Sepolia',
    deployedAt: new Date().toISOString(),
    txHash: contract.deploymentTransaction().hash
  };
  
  fs.writeFileSync(
    path.join(__dirname, 'deployment-v3.json'),
    JSON.stringify(deploymentInfo, null, 2)
  );
  
  console.log('\nDeployment info saved to deployment-v3.json');
  
  return address;
}

main()
  .then(address => {
    console.log('\n🎉 Deployment complete!');
    process.exit(0);
  })
  .catch(error => {
    console.error('Error:', error);
    process.exit(1);
  });
