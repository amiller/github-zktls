import { readFileSync, writeFileSync } from 'fs'
import { UltraHonkBackend, Barretenberg, BackendType } from '@aztec/bb.js'

const circuitPath = '../circuits/target/zk_github_attestation.json'

async function main() {
  console.log('=== Generating Solidity Verifier ===\n')

  // Load compiled circuit
  console.log('Loading circuit...')
  const circuit = JSON.parse(readFileSync(circuitPath, 'utf8'))

  // Initialize backend
  console.log('Initializing Barretenberg (WASM)...')
  const api = await Barretenberg.new({ backend: BackendType.Wasm })
  const backend = new UltraHonkBackend(circuit.bytecode, api)

  // Get verification key
  console.log('Generating verification key...')
  const vk = await backend.getVerificationKey({ verifierTarget: 'evm' })
  console.log('VK size:', vk.length, 'bytes')

  // Generate Solidity verifier
  console.log('Generating Solidity verifier...')
  const solidity = await backend.getSolidityVerifier(vk, { verifierTarget: 'evm' })

  // Save to file
  const outputPath = '../contracts/GitHubAttestationVerifier.sol'
  writeFileSync(outputPath, solidity)
  console.log('Solidity verifier saved to:', outputPath)
}

main().catch(console.error)
