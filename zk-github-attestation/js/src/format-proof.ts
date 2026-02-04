import { readFileSync } from 'fs'

// Format proof for on-chain verification
const proofPath = '../circuits/proof.json'

function main() {
  const proofData = JSON.parse(readFileSync(proofPath, 'utf8'))

  // Decode base64 proof
  const proofBytes = Buffer.from(proofData.proof, 'base64')
  const proofHex = '0x' + proofBytes.toString('hex')

  // Format public inputs as bytes32 array
  const publicInputs = proofData.publicInputs.map((pi: string) => {
    // Each public input is a field element string
    const bigint = BigInt(pi)
    return '0x' + bigint.toString(16).padStart(64, '0')
  })

  console.log('=== On-Chain Verification Data ===\n')
  console.log('Proof (hex):')
  console.log(proofHex)
  console.log('\nPublic Inputs (' + publicInputs.length + ' elements):')
  console.log('[')
  publicInputs.forEach((pi: string, i: number) => {
    console.log(`  "${pi}"${i < publicInputs.length - 1 ? ',' : ''}`)
  })
  console.log(']')

  // Also output parsed public inputs
  console.log('\n=== Parsed Public Inputs ===')

  // First 32 bytes = artifact hash
  const artifactHash = publicInputs.slice(0, 32).map((pi: string) =>
    parseInt(pi, 16).toString(16).padStart(2, '0')
  ).join('')
  console.log('Artifact Hash:', '0x' + artifactHash)

  // Next 32 bytes = repo hash
  const repoHash = publicInputs.slice(32, 64).map((pi: string) =>
    parseInt(pi, 16).toString(16).padStart(2, '0')
  ).join('')
  console.log('Repo Hash:', '0x' + repoHash)

  // Next 20 bytes = commit SHA
  const commitSha = publicInputs.slice(64, 84).map((pi: string) =>
    parseInt(pi, 16).toString(16).padStart(2, '0')
  ).join('')
  console.log('Commit SHA:', commitSha)
}

main()
