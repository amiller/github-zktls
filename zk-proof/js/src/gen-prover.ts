import { readFileSync, writeFileSync } from 'fs'
import { generateCircuitInputs, toProverToml } from './index.js'

const bundlePath = '../../docs/examples/sample-attestation-bundle.json'
const proverTomlPath = '../circuits/Prover.toml'

const bundle = JSON.parse(readFileSync(bundlePath, 'utf8'))
const inputs = generateCircuitInputs(bundle)
const toml = toProverToml(inputs)

writeFileSync(proverTomlPath, toml)
console.log('Generated', proverTomlPath)
console.log('Inputs:')
console.log('  commit_oid_offset:', inputs.commit_oid_offset)
console.log('  repo_oid_offset:', inputs.repo_oid_offset)
console.log('  repo_name_len:', inputs.repo_name_len)
console.log('  artifact_hash_offset:', inputs.artifact_hash_offset)
