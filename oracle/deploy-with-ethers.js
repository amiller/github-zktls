#!/usr/bin/env node

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

async function compileContract() {
  const solc = require('solc');
  
  // Read both source files
  const pmSource = fs.readFileSync('./foundry-tests/src/PredictionMarketV3.sol', 'utf8');
  const interfaceSource = fs.readFileSync('./foundry-tests/src/ISigstoreVerifier.sol', 'utf8');
  
  const input = {
    language: 'Solidity',
    sources: {
      'PredictionMarketV3.sol': { content: pmSource },
      'ISigstoreVerifier.sol': { content: interfaceSource }
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
      },
      viaIR: true
    }
  };
  
  console.log('📝 Compiling contract...');
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
    bytecode: '0x' + contract.evm.bytecode.object
  };
}

async function main() {
  // Ensure solc is installed
  try {
    require('solc');
  } catch {
    console.log('Installing solc...');
    require('child_process').execSync('npm install solc@0.8.20 --no-save', { stdio: 'inherit' });
  }
  
  const compiled = await compileContract();
  console.log('✅ Compilation successful');
  
  // Load wallet
  const walletData = JSON.parse(fs.readFileSync(
    path.join(process.env.HOME, '.openclaw-secrets/github-zktls-wallet.json')
  ));
  
  const provider = new ethers.JsonRpcProvider('https://sepolia.base.org');
  const wallet = new ethers.Wallet(walletData.private_key, provider);
  
  console.log('\n💰 Deployer:', wallet.address);
  const balance = await provider.getBalance(wallet.address);
  console.log('Balance:', ethers.formatEther(balance), 'ETH');
  
  if (balance < ethers.parseEther('0.0005')) {
    throw new Error('Insufficient balance for deployment');
  }
  
  const sigstoreVerifier = '0x0Af922925AE3602b0dC23c4cFCf54FABe2F54725';
  
  console.log('\n📦 Deploying PredictionMarket V3...');
  console.log('Using SigstoreVerifier:', sigstoreVerifier);
  
  const factory = new ethers.ContractFactory(compiled.abi, compiled.bytecode, wallet);
  const contract = await factory.deploy(sigstoreVerifier, {
    gasLimit: 3000000
  });
  
  console.log('Deploy TX:', contract.deploymentTransaction().hash);
  console.log('Waiting for confirmation...');
  
  await contract.waitForDeployment();
  
  const address = await contract.getAddress();
  console.log('\n✅ PredictionMarket V3 deployed!');
  console.log('Address:', address);
  console.log('Basescan:', `https://sepolia.basescan.org/address/${address}`);
  
  // Save deployment info
  const deploymentInfo = {
    address,
    abi: compiled.abi,
    deployer: wallet.address,
    sigstoreVerifier,
    network: 'Base Sepolia',
    chainId: 84532,
    deployedAt: new Date().toISOString(),
    txHash: contract.deploymentTransaction().hash
  };
  
  fs.writeFileSync(
    './deployment-v3.json',
    JSON.stringify(deploymentInfo, null, 2)
  );
  
  console.log('\n💾 Deployment info saved to deployment-v3.json');
  
  return { address, abi: compiled.abi };
}

main()
  .then(({ address }) => {
    console.log('\n🎉 Deployment complete!');
    console.log('\nNext steps:');
    console.log('1. Create market for topic 27685 (keyword: "security")');
    console.log('2. Place small bet on YES');
    console.log('3. Run oracle workflow');
    console.log('4. Settle and claim');
    process.exit(0);
  })
  .catch(error => {
    console.error('\n❌ Error:', error.message);
    if (error.stack) console.error(error.stack);
    process.exit(1);
  });
