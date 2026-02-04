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
console.log('TBS length:', inputs.cert_tbs_len, '(padded to 1800)')

console.log('\n--- OIDC Claim Offsets (NEW) ---')
console.log('Commit OID offset:', inputs.commit_oid_offset)
console.log('Repo OID offset:', inputs.repo_oid_offset)
console.log('Repo name:', Buffer.from(inputs.repo_name.slice(0, parseInt(inputs.repo_name_len)).map(s => parseInt(s))).toString())
console.log('Repo name length:', inputs.repo_name_len)
console.log('Artifact hash offset:', inputs.artifact_hash_offset)

// Verify OID bytes at offsets
console.log('\n--- OID Verification ---')
const tbs = Buffer.from(inputs.cert_tbs.map(s => parseInt(s)))
const commitOffset = parseInt(inputs.commit_oid_offset)
const repoOffset = parseInt(inputs.repo_oid_offset)

// OID prefix: 2b 06 01 04 01 83 bf 30 01
const expectedPrefix = Buffer.from([0x2b, 0x06, 0x01, 0x04, 0x01, 0x83, 0xbf, 0x30, 0x01])

const commitOidBytes = tbs.subarray(commitOffset, commitOffset + 10)
console.log('Commit OID bytes:', [...commitOidBytes].map(b => b.toString(16).padStart(2, '0')).join(' '))
console.log('Expected prefix:', [...expectedPrefix].map(b => b.toString(16).padStart(2, '0')).join(' '), '03')
const commitPrefixMatch = commitOidBytes.subarray(0, 9).equals(expectedPrefix) && commitOidBytes[9] === 0x03
console.log('Commit OID prefix match:', commitPrefixMatch)

const repoOidBytes = tbs.subarray(repoOffset, repoOffset + 10)
console.log('Repo OID bytes:', [...repoOidBytes].map(b => b.toString(16).padStart(2, '0')).join(' '))
console.log('Expected prefix:', [...expectedPrefix].map(b => b.toString(16).padStart(2, '0')).join(' '), '05')
const repoPrefixMatch = repoOidBytes.subarray(0, 9).equals(expectedPrefix) && repoOidBytes[9] === 0x05
console.log('Repo OID prefix match:', repoPrefixMatch)

// Verify artifact hash in PAE
console.log('\n--- Artifact Hash Verification ---')
const pae = Buffer.from(inputs.pae_message.map(s => parseInt(s)))
const hashOffset = parseInt(inputs.artifact_hash_offset)
const hashHex = pae.subarray(hashOffset, hashOffset + 64).toString()
console.log('Artifact hash at offset:', hashHex)
const expectedHash = inputs.artifact_hash.map(s => parseInt(s).toString(16).padStart(2, '0')).join('')
console.log('Expected hash:', expectedHash)
const hashMatch = hashHex === expectedHash
console.log('Artifact hash match:', hashMatch)

// Verify leaf signature
console.log('\n--- Leaf Signature Verification (P-256) ---')
const validLeaf = verifySignature(inputs)
console.log('Leaf signature valid:', validLeaf)

// Verify certificate chain
console.log('\n--- Certificate Chain Verification (P-384) ---')
const validChain = verifyCertChain(inputs)
console.log('Certificate chain valid:', validChain)

// Summary
console.log('\n=== Test Summary ===')
const allPassed = commitPrefixMatch && repoPrefixMatch && hashMatch && validLeaf && validChain
console.log('Commit OID prefix:', commitPrefixMatch ? '✓' : '✗')
console.log('Repo OID prefix:', repoPrefixMatch ? '✓' : '✗')
console.log('Artifact hash:', hashMatch ? '✓' : '✗')
console.log('Leaf signature:', validLeaf ? '✓' : '✗')
console.log('Cert chain:', validChain ? '✓' : '✗')
console.log('')
console.log(allPassed ? '=== All Tests Passed ===' : '=== TESTS FAILED ===')

if (!allPassed) process.exit(1)

// Output Prover.toml
console.log('\n--- Prover.toml Preview ---')
const toml = toProverToml(inputs)
console.log(toml.slice(0, 800) + '...')
