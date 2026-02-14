#!/usr/bin/env node

const { ethers } = require('ethers');
const fs = require('fs');
const https = require('https');

// Simple bytecode (will compile inline)
const PREDICTION_MARKET_SOURCE = fs.readFileSync('./foundry-tests/src/PredictionMarketV3.sol', 'utf8');

async function compileSolidity(source) {
  // Use solc-js to compile
  const solc = require('solc');
  
  const input = {
    language: 'Solidity',
    sources: {
      'PredictionMarketV3.sol': { content: source }
    },
    settings: {
      outputSelection: {
        '*': {
          '*': ['abi', 'evm.bytecode']
        }
      },
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  };
  
  const output = JSON.parse(solc.compile(JSON.stringify(input)));
  
  if (output.errors) {
    const errors = output.errors.filter(e => e.severity === 'error');
    if (errors.length > 0) {
      console.error('Compilation errors:');
      errors.forEach(e => console.error(e.formattedMessage));
      throw new Error('Compilation failed');
    }
  }
  
  const contract = output.contracts['PredictionMarketV3.sol']['PredictionMarket'];
  return {
    abi: contract.abi,
    bytecode: contract.evm.bytecode.object
  };
}

async function main() {
  console.log('📝 Compiling contract...');
  
  // Install solc if needed
  try {
    require('solc');
  } catch {
    console.log('Installing solc...');
    require('child_process').execSync('npm install solc@0.8.20 --no-save', { stdio: 'inherit' });
  }
  
  const compiled = await compileSolidity(PREDICTION_MARKET_SOURCE);
  
  // Load wallet
  const walletData = JSON.parse(fs.readFileSync(
    require('path').join(process.env.HOME, '.openclaw-secrets/github-zktls-wallet.json')
  ));
  
  const provider = new ethers.JsonRpcProvider('https://sepolia.base.org');
  const wallet = new ethers.Wallet(walletData.private_key, provider);
  
  console.log('\n💰 Deployer:', wallet.address);
  const balance = await provider.getBalance(wallet.address);
  console.log('Balance:', ethers.formatEther(balance), 'ETH');
  
  if (balance < ethers.parseEther('0.001')) {
    throw new Error('Insufficient balance for deployment');
  }
  
  const sigstoreVerifier = '0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725';
  
  console.log('\n📦 Deploying PredictionMarket V3...');
  const factory = new ethers.ContractFactory(compiled.abi, compiled.bytecode, wallet);
  const contract = await factory.deploy(sigstoreVerifier);
  
  console.log('TX:', contract.deploymentTransaction().hash);
  await contract.waitForDeployment();
  
  const address = await contract.getAddress();
  console.log('\n✅ Deployed at:', address);
  console.log('🔍 Basescan:', `https://sepolia.basescan.org/address/${address}`);
  
  // Save
  fs.writeFileSync('./deployment-v3.json', JSON.stringify({
    address,
    abi: compiled.abi,
    deployer: wallet.address,
    sigstoreVerifier,
    network: 'Base Sepolia',
    deployedAt: new Date().toISOString()
  }, null, 2));
  
  return { address, abi: compiled.abi };
}

main()
  .then(({ address }) => {
    console.log('\n🎉 Ready to create market!');
    process.exit(0);
  })
  .catch(error => {
    console.error('\n❌ Error:', error.message);
    process.exit(1);
  });
