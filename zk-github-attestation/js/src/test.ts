import { readFileSync } from 'fs'
import { generateCircuitInputs, verifySignature, verifyCertChain, toProverToml } from './index.js'

const bundlePath = '../../docs/examples/sample-attestation-bundle.json'

console.log('=== ZK GitHub Attestation Witness Generator Test ===\n')

// Load sample bundle
const bundle = JSON.parse(readFileSync(bundlePath, 'utf8'))
console.log('Loaded bundle from:', bundlePath)

// Generate inputs
const inputs = generateCircuitInputs(bundle)

console.log('\n--- Metadata ---')
console.log('OIDC Issuer:', inputs._meta.oidc_issuer)
console.log('Repository:', inputs._meta.oidc_repo)
console.log('Workflow:', inputs._meta.oidc_workflow)
console.log('Commit SHA:', inputs._meta.oidc_commit)

console.log('\n--- Circuit Inputs ---')
console.log('PAE message length:', inputs.pae_message_len, '(padded to 2048)')
console.log('Signature (first 8 bytes):', inputs.signature.slice(0, 8).join(', '))
console.log('Pubkey X (first 8 bytes):', inputs.leaf_pubkey_x.slice(0, 8).join(', '))
console.log('Pubkey Y (first 8 bytes):', inputs.leaf_pubkey_y.slice(0, 8).join(', '))
console.log('TBS length:', inputs.cert_tbs_len, '(padded to 700)')
console.log('Issuer sig R (first 8 bytes):', inputs.issuer_sig_r.slice(0, 8).join(', '))
console.log('Issuer sig S (first 8 bytes):', inputs.issuer_sig_s.slice(0, 8).join(', '))
console.log('Artifact hash (first 8 bytes):', inputs.artifact_hash.slice(0, 8).join(', '))
console.log('Commit SHA (20 bytes):', inputs.commit_sha.join(', '))

// Verify leaf signature
console.log('\n--- Leaf Signature Verification (P-256) ---')
const validLeaf = verifySignature(inputs)
console.log('Leaf signature valid:', validLeaf)

if (!validLeaf) {
  console.error('ERROR: Leaf signature verification failed!')
  process.exit(1)
}

// Verify certificate chain
console.log('\n--- Certificate Chain Verification (P-384) ---')
const validChain = verifyCertChain(inputs)
console.log('Certificate chain valid:', validChain)

if (!validChain) {
  console.error('ERROR: Certificate chain verification failed!')
  process.exit(1)
}

console.log('\n=== All Tests Passed ===')

// Optionally output Prover.toml preview
console.log('\n--- Prover.toml Preview (first 500 chars) ---')
const toml = toProverToml(inputs)
console.log(toml.slice(0, 500) + '...')
