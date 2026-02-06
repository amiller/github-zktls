import { p256 } from '@noble/curves/p256'
import { p384 } from '@noble/curves/p384'
import { createHash } from 'crypto'

// Sigstore bundle types
export interface SigstoreBundle {
  mediaType: string
  verificationMaterial: {
    certificate: { rawBytes: string }
    tlogEntries: any[]
  }
  dsseEnvelope: {
    payload: string
    payloadType: string
    signatures: { sig: string; keyid?: string }[]
  }
}

const MAX_REPO_LENGTH = 64
const MAX_PAE_LENGTH = 2048
const MAX_TBS_LENGTH = 1800

export interface CircuitInputs {
  // DSSE envelope (what gets signed)
  pae_message: string[]
  pae_message_len: string

  // Leaf ECDSA P-256 signature over PAE (r||s)
  leaf_signature: string[]

  // Leaf certificate TBS (To Be Signed)
  leaf_tbs: string[]
  leaf_tbs_len: string

  // Intermediate's P-384 signature over leaf TBS
  intermediate_signature_r: string[]
  intermediate_signature_s: string[]

  // Offset in leaf_tbs where P-256 pubkey starts (at 0x04 prefix)
  leaf_pubkey_offset: string

  // OIDC claim extraction hints
  commit_oid_offset: string
  repo_oid_offset: string
  repo_name: string[]
  repo_name_len: string
  artifact_hash_offset: string

  // Public inputs
  artifact_hash: string[]
  repo_hash: string[]
  commit_sha: string[]

  // Extra metadata (not circuit inputs)
  _meta: {
    oidc_issuer: string
    oidc_repo: string
    oidc_workflow: string
    oidc_commit: string
    leaf_pubkey_x: string
    leaf_pubkey_y: string
  }
}

// DSSE PAE (Pre-Authentication Encoding)
export function computePAE(payloadType: string, payload: Buffer): Buffer {
  const SP = Buffer.from(' ')
  const prefix = Buffer.from('DSSEv1')
  const typeBytes = Buffer.from(payloadType)
  const typeLen = Buffer.from(typeBytes.length.toString())
  const payloadLen = Buffer.from(payload.length.toString())

  return Buffer.concat([
    prefix, SP,
    typeLen, SP, typeBytes, SP,
    payloadLen, SP, payload
  ])
}

// P-256 curve order
const P256_ORDER = BigInt('0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551')
const P256_HALF_ORDER = P256_ORDER / 2n

// Decode DER-encoded ECDSA signature to (r, s) with low-s normalization
export function decodeECDSASignature(derSig: Buffer): { r: Buffer; s: Buffer } {
  let offset = 0
  if (derSig[offset++] !== 0x30) throw new Error('Invalid DER signature')
  offset++ // skip total length

  if (derSig[offset++] !== 0x02) throw new Error('Invalid DER signature (r)')
  const rLen = derSig[offset++]
  let r = derSig.subarray(offset, offset + rLen)
  offset += rLen

  if (derSig[offset++] !== 0x02) throw new Error('Invalid DER signature (s)')
  const sLen = derSig[offset++]
  let s = derSig.subarray(offset, offset + sLen)

  r = padTo32Bytes(r)
  s = padTo32Bytes(s)

  // Normalize s to low-s form
  const sBigInt = BigInt('0x' + s.toString('hex'))
  if (sBigInt > P256_HALF_ORDER) {
    const normalizedS = P256_ORDER - sBigInt
    s = Buffer.from(normalizedS.toString(16).padStart(64, '0'), 'hex')
    console.log('Normalized high-s signature to low-s form')
  }

  return { r, s }
}

function padTo32Bytes(buf: Buffer): Buffer {
  if (buf.length === 33 && buf[0] === 0) buf = buf.subarray(1)
  if (buf.length > 32) throw new Error('Value too large')
  if (buf.length === 32) return buf
  const padded = Buffer.alloc(32)
  buf.copy(padded, 32 - buf.length)
  return padded
}

// P-384 curve order for signature normalization
const P384_ORDER = BigInt('0xffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973')
const P384_HALF_ORDER = P384_ORDER / 2n

// Parse X.509 certificate
export function parseCertificate(derBase64: string): {
  publicKey: { x: Buffer; y: Buffer }
  pubkeyOffset: number  // Offset in TBS where pubkey starts (at 0x04 prefix)
  oidcClaims: Record<string, string>
  tbs: Buffer
  issuerSignature: { r: Buffer; s: Buffer }
  oidOffsets: { commit: number; repo: number }
} {
  const der = Buffer.from(derBase64, 'base64')

  // Parse outer SEQUENCE
  if (der[0] !== 0x30) throw new Error('Invalid certificate: not a SEQUENCE')
  const { length: certLen, headerLen: certHeaderLen } = parseDERLength(der, 1)

  // Parse TBSCertificate
  const tbsStart = certHeaderLen
  if (der[tbsStart] !== 0x30) throw new Error('Invalid TBSCertificate')
  const { length: tbsBodyLen, headerLen: tbsHeaderLen } = parseDERLength(der, tbsStart + 1)
  const tbsLen = tbsHeaderLen + tbsBodyLen
  const tbs = der.subarray(tbsStart, tbsStart + tbsLen)

  // Skip AlgorithmIdentifier to get signature
  let sigAlgStart = tbsStart + tbsLen
  if (der[sigAlgStart] !== 0x30) throw new Error('Invalid signatureAlgorithm')
  const { length: sigAlgLen, headerLen: sigAlgHeaderLen } = parseDERLength(der, sigAlgStart + 1)

  // Parse signature BIT STRING
  const sigBitStringStart = sigAlgStart + sigAlgHeaderLen + sigAlgLen
  if (der[sigBitStringStart] !== 0x03) throw new Error('Invalid signature BIT STRING')
  const { length: sigBitLen, headerLen: sigBitHeaderLen } = parseDERLength(der, sigBitStringStart + 1)

  const sigDerStart = sigBitStringStart + sigBitHeaderLen + 1
  const sigDer = der.subarray(sigDerStart, sigBitStringStart + sigBitHeaderLen + sigBitLen)
  const issuerSignature = decodeECDSASignatureP384(sigDer)

  // Find P-256 public key in TBS
  // OID for prime256v1/secp256r1: 06 08 2a 86 48 ce 3d 03 01 07
  const p256OID = Buffer.from([0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07])
  const oidIndex = tbs.indexOf(p256OID)
  if (oidIndex === -1) throw new Error('P-256 OID not found in certificate')

  // Public key follows: 03 42 00 04 [x 32 bytes] [y 32 bytes]
  let pubkeyOffset = -1
  for (let i = oidIndex; i < tbs.length - 66; i++) {
    if (tbs[i] === 0x03 && tbs[i + 1] === 0x42 && tbs[i + 2] === 0x00 && tbs[i + 3] === 0x04) {
      pubkeyOffset = i + 3  // Point to 0x04 prefix
      break
    }
  }
  if (pubkeyOffset === -1) throw new Error('Public key not found in certificate')

  const x = tbs.subarray(pubkeyOffset + 1, pubkeyOffset + 33)
  const y = tbs.subarray(pubkeyOffset + 33, pubkeyOffset + 65)

  // Parse OIDC extensions
  const oidcClaims: Record<string, string> = {}
  const oidcPrefix = Buffer.from([0x2b, 0x06, 0x01, 0x04, 0x01, 0x83, 0xbf, 0x30, 0x01])

  let commitOidOffset = -1
  let repoOidOffset = -1

  let searchPos = 0
  while (searchPos < tbs.length) {
    const idx = tbs.indexOf(oidcPrefix, searchPos)
    if (idx === -1) break

    const extNum = tbs[idx + oidcPrefix.length]
    const valueStart = findUTF8StringAfter(tbs, idx + oidcPrefix.length + 1)
    if (valueStart) {
      const oidName = getOIDName(extNum)
      oidcClaims[oidName] = valueStart.value

      if (extNum === 0x03) commitOidOffset = idx
      if (extNum === 0x05) repoOidOffset = idx
    }
    searchPos = idx + 1
  }

  if (commitOidOffset === -1) throw new Error('Commit SHA OID not found in certificate')
  if (repoOidOffset === -1) throw new Error('Repository OID not found in certificate')

  return {
    publicKey: { x, y },
    pubkeyOffset,
    oidcClaims,
    tbs,
    issuerSignature,
    oidOffsets: { commit: commitOidOffset, repo: repoOidOffset }
  }
}

function parseDERLength(buf: Buffer, offset: number): { length: number; headerLen: number } {
  const firstByte = buf[offset]
  if (firstByte < 0x80) {
    return { length: firstByte, headerLen: 2 }
  }
  const numBytes = firstByte & 0x7f
  let length = 0
  for (let i = 0; i < numBytes; i++) {
    length = (length << 8) | buf[offset + 1 + i]
  }
  return { length, headerLen: 2 + numBytes }
}

function decodeECDSASignatureP384(derSig: Buffer): { r: Buffer; s: Buffer } {
  let offset = 0
  if (derSig[offset++] !== 0x30) throw new Error('Invalid DER signature: expected SEQUENCE')

  let totalLen = derSig[offset++]
  if (totalLen & 0x80) {
    const numBytes = totalLen & 0x7f
    totalLen = 0
    for (let i = 0; i < numBytes; i++) {
      totalLen = (totalLen << 8) | derSig[offset++]
    }
  }

  if (derSig[offset++] !== 0x02) throw new Error('Invalid DER signature (r)')
  const rLen = derSig[offset++]
  let r = derSig.subarray(offset, offset + rLen)
  offset += rLen

  if (derSig[offset++] !== 0x02) throw new Error('Invalid DER signature (s)')
  const sLen = derSig[offset++]
  let s = derSig.subarray(offset, offset + sLen)

  r = padTo48Bytes(r)
  s = padTo48Bytes(s)

  // Normalize s to low-s form
  const sBigInt = BigInt('0x' + s.toString('hex'))
  if (sBigInt > P384_HALF_ORDER) {
    const normalizedS = P384_ORDER - sBigInt
    s = Buffer.from(normalizedS.toString(16).padStart(96, '0'), 'hex')
    console.log('Normalized P-384 high-s signature to low-s form')
  }

  return { r, s }
}

function padTo48Bytes(buf: Buffer): Buffer {
  if (buf.length === 49 && buf[0] === 0) buf = buf.subarray(1)
  if (buf.length > 48) throw new Error('Value too large for P-384')
  if (buf.length === 48) return buf
  const padded = Buffer.alloc(48)
  buf.copy(padded, 48 - buf.length)
  return padded
}

function findUTF8StringAfter(der: Buffer, start: number): { value: string } | null {
  for (let i = start; i < Math.min(start + 20, der.length - 2); i++) {
    if (der[i] === 0x04 || der[i] === 0x0c || der[i] === 0x16) {
      const len = der[i + 1]
      if (len < 0x80 && i + 2 + len <= der.length) {
        return { value: der.subarray(i + 2, i + 2 + len).toString('utf8') }
      }
    }
  }
  return null
}

function getOIDName(num: number): string {
  const names: Record<number, string> = {
    1: 'issuer', 2: 'trigger', 3: 'sha', 4: 'workflow_name', 5: 'repository',
    6: 'ref', 11: 'runner_environment', 12: 'repository_uri', 15: 'repository_id',
    17: 'owner_id', 21: 'run_url', 22: 'visibility',
  }
  return names[num] || `oid_${num}`
}

export function parseInTotoStatement(payloadBase64: string): {
  artifactName: string
  artifactHash: string
  repo: string
  workflow: string
  commit: string
} {
  const payload = JSON.parse(Buffer.from(payloadBase64, 'base64').toString())
  const subject = payload.subject?.[0] || {}
  const buildDef = payload.predicate?.buildDefinition || {}
  const workflow = buildDef.externalParameters?.workflow || {}
  const deps = buildDef.resolvedDependencies?.[0] || {}

  return {
    artifactName: subject.name || '',
    artifactHash: subject.digest?.sha256 || '',
    repo: workflow.repository?.replace('https://github.com/', '') || '',
    workflow: workflow.path || '',
    commit: deps.digest?.gitCommit || '',
  }
}

function padBuffer(buf: Buffer, len: number): Buffer {
  if (buf.length > len) throw new Error(`Buffer too long: ${buf.length} > ${len}`)
  if (buf.length === len) return buf
  const padded = Buffer.alloc(len)
  buf.copy(padded)
  return padded
}

function findArtifactHashOffset(paeMessage: Buffer): number {
  const marker = Buffer.from('"sha256":"')
  const idx = paeMessage.indexOf(marker)
  if (idx === -1) throw new Error('Artifact hash marker not found in PAE message')
  return idx + marker.length
}

function bufferToStringArray(buf: Buffer): string[] {
  return [...buf].map(b => b.toString())
}

// Main function: generate circuit inputs from Sigstore bundle
export function generateCircuitInputs(bundleJson: any): CircuitInputs {
  const bundle = bundleJson.attestations?.[0]?.bundle || bundleJson
  const dsse = bundle.dsseEnvelope
  const cert = bundle.verificationMaterial.certificate

  // 1. Decode payload and compute PAE
  const payloadBytes = Buffer.from(dsse.payload, 'base64')
  const paeMessage = computePAE(dsse.payloadType, payloadBytes)
  const paeMessagePadded = padBuffer(paeMessage, MAX_PAE_LENGTH)

  // 2. Decode ECDSA signature
  const sigDer = Buffer.from(dsse.signatures[0].sig, 'base64')
  const { r, s } = decodeECDSASignature(sigDer)
  const leafSignature = Buffer.concat([r, s])

  // 3. Parse certificate
  const { publicKey, pubkeyOffset, oidcClaims, tbs, issuerSignature, oidOffsets } = parseCertificate(cert.rawBytes)
  const tbsPadded = padBuffer(tbs, MAX_TBS_LENGTH)

  // 4. Parse in-toto statement
  const statement = parseInTotoStatement(dsse.payload)

  // 5. Compute hashes
  const artifactHash = Buffer.from(statement.artifactHash, 'hex')
  // Use OIDC claim from certificate (not in-toto statement) to match what circuit verifies
  const repoNameStr = oidcClaims.repository || statement.repo
  const repoName = Buffer.from(repoNameStr)
  const repoNamePadded = padBuffer(repoName, MAX_REPO_LENGTH)
  const repoHash = createHash('sha256').update(repoNameStr).digest()
  const commitSha = Buffer.from(statement.commit, 'hex')

  // 6. Find artifact hash offset
  const artifactHashOffset = findArtifactHashOffset(paeMessage)

  return {
    pae_message: bufferToStringArray(paeMessagePadded),
    pae_message_len: paeMessage.length.toString(),

    leaf_signature: bufferToStringArray(leafSignature),

    leaf_tbs: bufferToStringArray(tbsPadded),
    leaf_tbs_len: tbs.length.toString(),

    intermediate_signature_r: bufferToStringArray(issuerSignature.r),
    intermediate_signature_s: bufferToStringArray(issuerSignature.s),

    leaf_pubkey_offset: pubkeyOffset.toString(),

    commit_oid_offset: oidOffsets.commit.toString(),
    repo_oid_offset: oidOffsets.repo.toString(),
    repo_name: bufferToStringArray(repoNamePadded),
    repo_name_len: repoName.length.toString(),
    artifact_hash_offset: artifactHashOffset.toString(),

    artifact_hash: bufferToStringArray(artifactHash),
    repo_hash: bufferToStringArray(repoHash),
    commit_sha: bufferToStringArray(commitSha),

    _meta: {
      oidc_issuer: oidcClaims.issuer || '',
      oidc_repo: oidcClaims.repository || statement.repo,
      oidc_workflow: oidcClaims.workflow_name || '',
      oidc_commit: oidcClaims.sha || statement.commit,
      leaf_pubkey_x: publicKey.x.toString('hex'),
      leaf_pubkey_y: publicKey.y.toString('hex'),
    }
  }
}

// Fulcio Intermediate CA Public Key (P-384)
const FULCIO_INTERMEDIATE_X = Buffer.from([
  0xf1, 0x15, 0x52, 0xff, 0x2b, 0x07, 0xf8, 0xd3, 0xaf, 0xb8, 0x36, 0x72,
  0x3c, 0x86, 0x6d, 0x8a, 0x58, 0x14, 0x17, 0xd3, 0x65, 0x6a, 0xb6, 0x29,
  0x01, 0xdf, 0x47, 0x3f, 0x5b, 0xc1, 0x04, 0x7d, 0x54, 0xe4, 0x25, 0x7b,
  0xec, 0xb4, 0x92, 0xee, 0xcd, 0x19, 0x88, 0x7e, 0x27, 0x13, 0xb1, 0xef
])
const FULCIO_INTERMEDIATE_Y = Buffer.from([
  0xee, 0x9b, 0x52, 0xe8, 0xbb, 0xef, 0x47, 0xf4, 0x93, 0x93, 0xbf, 0x7c,
  0x2d, 0x58, 0x0c, 0xcc, 0xb9, 0x49, 0xe0, 0x77, 0x88, 0x7c, 0x5d, 0xed,
  0x1d, 0x26, 0x9e, 0xc4, 0xb7, 0x18, 0xa5, 0x20, 0x12, 0xaf, 0x59, 0x12,
  0xd0, 0xdf, 0xd1, 0x80, 0x12, 0x73, 0xff, 0xd8, 0xd6, 0x0a, 0x25, 0xe7
])

// Verify leaf signature using noble/curves (for testing)
export function verifySignature(inputs: CircuitInputs): boolean {
  const paeLen = parseInt(inputs.pae_message_len)
  const paeMessage = Buffer.from(inputs.pae_message.slice(0, paeLen).map(s => parseInt(s)))
  const msgHash = createHash('sha256').update(paeMessage).digest()

  const sig = Buffer.from(inputs.leaf_signature.map(s => parseInt(s)))

  // Extract pubkey from TBS at offset
  const tbsLen = parseInt(inputs.leaf_tbs_len)
  const tbs = Buffer.from(inputs.leaf_tbs.slice(0, tbsLen).map(s => parseInt(s)))
  const offset = parseInt(inputs.leaf_pubkey_offset)
  const pubX = tbs.subarray(offset + 1, offset + 33)
  const pubY = tbs.subarray(offset + 33, offset + 65)
  const pubkey = Buffer.concat([Buffer.from([0x04]), pubX, pubY])

  return p256.verify(sig, msgHash, pubkey)
}

// Verify certificate chain (Fulcio signed the leaf cert)
export function verifyCertChain(inputs: CircuitInputs): boolean {
  const tbsLen = parseInt(inputs.leaf_tbs_len)
  const tbs = Buffer.from(inputs.leaf_tbs.slice(0, tbsLen).map(s => parseInt(s)))

  // SHA-384 hash of TBS
  const tbsHash = createHash('sha384').update(tbs).digest()

  const sigR = Buffer.from(inputs.intermediate_signature_r.map(s => parseInt(s)))
  const sigS = Buffer.from(inputs.intermediate_signature_s.map(s => parseInt(s)))
  const sig = Buffer.concat([sigR, sigS])

  const pubkey = Buffer.concat([Buffer.from([0x04]), FULCIO_INTERMEDIATE_X, FULCIO_INTERMEDIATE_Y])

  return p384.verify(sig, tbsHash, pubkey)
}

// Format for Prover.toml
export function toProverToml(inputs: CircuitInputs): string {
  const lines: string[] = []
  for (const [key, value] of Object.entries(inputs)) {
    if (key === '_meta') continue
    if (Array.isArray(value)) {
      lines.push(`${key} = [${value.map(v => `'${v}'`).join(', ')}]`)
    } else {
      lines.push(`${key} = '${value}'`)
    }
  }
  return lines.join('\n')
}

// CLI entry point
import { readFileSync, writeFileSync } from 'fs'
import { fileURLToPath } from 'url'

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const cmd = process.argv[2]
  if (cmd === 'witness') {
    const bundlePath = process.argv[3]
    if (!bundlePath) {
      console.error('Usage: node index.js witness <bundle.json>')
      process.exit(1)
    }
    const bundle = JSON.parse(readFileSync(bundlePath, 'utf8'))
    const inputs = generateCircuitInputs(bundle)
    const toml = toProverToml(inputs)
    writeFileSync('../circuits/Prover.toml', toml)
    console.log('Generated Prover.toml')
  }
}
