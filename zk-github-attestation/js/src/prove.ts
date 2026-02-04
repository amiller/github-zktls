import { readFileSync, writeFileSync } from 'fs'
import { gunzipSync } from 'zlib'
import { generateCircuitInputs, verifySignature } from './index.js'
import { Noir } from '@noir-lang/noir_js'
import { UltraHonkBackend, Barretenberg, BackendType } from '@aztec/bb.js'

const bundlePath = '../../docs/examples/sample-attestation-bundle.json'
const circuitPath = '../circuits/target/zk_github_attestation.json'

async function main() {
  console.log('=== ZK GitHub Attestation Prover ===\n')

  // Load bundle and generate inputs
  const bundle = JSON.parse(readFileSync(bundlePath, 'utf8'))
  const inputs = generateCircuitInputs(bundle)

  // Verify signature first (sanity check)
  if (!verifySignature(inputs)) throw new Error('Signature verification failed')
  console.log('JS signature verification: PASSED')

  // Load compiled circuit
  console.log('Loading circuit...')
  const circuit = JSON.parse(readFileSync(circuitPath, 'utf8'))

  // Initialize Noir and backend
  const noir = new Noir(circuit)
  console.log('Initializing Barretenberg (WASM)...')
  const api = await Barretenberg.new({ backend: BackendType.Wasm })
  const backend = new UltraHonkBackend(circuit.bytecode, api)

  // Prepare inputs (remove metadata)
  const circuitInputs: Record<string, any> = {}
  for (const [k, v] of Object.entries(inputs)) {
    if (k !== '_meta') circuitInputs[k] = v
  }

  // Execute circuit to get witness
  console.log('Generating witness...')
  const { witness } = await noir.execute(circuitInputs)
  console.log('Witness generated successfully')

  // Generate proof
  console.log('Generating proof (this may take a while)...')
  const proof = await backend.generateProof(witness)
  console.log('Proof generated!')
  console.log('Proof size:', proof.proof.length, 'bytes')

  // Verify proof
  console.log('\nVerifying proof...')
  const valid = await backend.verifyProof(proof)
  console.log('Proof valid:', valid)

  // Save proof
  writeFileSync('../circuits/proof.json', JSON.stringify({
    proof: Buffer.from(proof.proof).toString('base64'),
    publicInputs: proof.publicInputs.map(s => s.toString())
  }, null, 2))
  console.log('Proof saved to circuits/proof.json')
}

main().catch(console.error)
