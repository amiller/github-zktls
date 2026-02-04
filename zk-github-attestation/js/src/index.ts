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

export interface CircuitInputs {
  // DSSE envelope (what gets signed) - padded to MAX_PAE_LENGTH
  pae_message: string[]       // PAE-encoded message bytes (2048 padded)
  pae_message_len: string

  // ECDSA P-256 signature (concatenated r||s)
  signature: string[]         // 64 bytes

  // Leaf certificate public key (P-256)
  leaf_pubkey_x: string[]     // 32 bytes
  leaf_pubkey_y: string[]     // 32 bytes

  // Certificate TBS for chain verification (padded to MAX_TBS_LENGTH)
  cert_tbs: string[]          // TBS portion of certificate (1800 padded)
  cert_tbs_len: string

  // Issuer (Fulcio) P-384 signature over TBS
  issuer_sig_r: string[]      // 48 bytes
  issuer_sig_s: string[]      // 48 bytes

  // OIDC claim extraction hints
  commit_oid_offset: string   // Offset in TBS where commit OID starts
  repo_oid_offset: string     // Offset in TBS where repo OID starts
  repo_name: string[]         // Repo name bytes (64 padded)
  repo_name_len: string
  artifact_hash_offset: string // Offset in PAE where artifact hash hex string starts

  // Public inputs (to be revealed on-chain)
  artifact_hash: string[]     // 32 bytes sha256
  repo_hash: string[]         // 32 bytes sha256 of repo string
  commit_sha: string[]        // 20 bytes git commit

  // Extra metadata (not circuit inputs)
  _meta: {
    oidc_issuer: string
    oidc_repo: string
    oidc_workflow: string
    oidc_commit: string
  }
}

// DSSE PAE (Pre-Authentication Encoding)
// Format: "DSSEv1" SP LEN(type) SP type SP LEN(payload) SP payload
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

// Decode DER-encoded ECDSA signature to (r, s) 32-byte values
// Normalizes s to low-s form (s <= order/2) as required by Noir stdlib
export function decodeECDSASignature(derSig: Buffer): { r: Buffer; s: Buffer } {
  // DER: 0x30 [total-len] 0x02 [r-len] [r] 0x02 [s-len] [s]
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

  // Remove leading zeros and pad to 32 bytes
  r = padTo32Bytes(r)
  s = padTo32Bytes(s)

  // Normalize s to low-s form (required by Noir's ecdsa_secp256r1)
  const sBigInt = BigInt('0x' + s.toString('hex'))
  if (sBigInt > P256_HALF_ORDER) {
    const normalizedS = P256_ORDER - sBigInt
    s = Buffer.from(normalizedS.toString(16).padStart(64, '0'), 'hex')
    console.log('Normalized high-s signature to low-s form')
  }

  return { r, s }
}

function padTo32Bytes(buf: Buffer): Buffer {
  // Remove leading zero if present (DER uses it for positive numbers)
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

// Parse X.509 certificate to extract public key, OIDC extensions, TBS, issuer signature, and OID offsets
export function parseCertificate(derBase64: string): {
  publicKey: { x: Buffer; y: Buffer }
  oidcClaims: Record<string, string>
  tbs: Buffer
  issuerSignature: { r: Buffer; s: Buffer }
  oidOffsets: { commit: number; repo: number }  // Offsets relative to TBS start
} {
  const der = Buffer.from(derBase64, 'base64')

  // X.509 structure: SEQUENCE { TBSCertificate, AlgorithmIdentifier, BIT STRING (signature) }
  // Parse the outer SEQUENCE
  if (der[0] !== 0x30) throw new Error('Invalid certificate: not a SEQUENCE')
  const { length: certLen, headerLen: certHeaderLen } = parseDERLength(der, 1)

  // Parse TBSCertificate (first element)
  const tbsStart = certHeaderLen
  if (der[tbsStart] !== 0x30) throw new Error('Invalid TBSCertificate')
  const { length: tbsBodyLen, headerLen: tbsHeaderLen } = parseDERLength(der, tbsStart + 1)
  const tbsLen = tbsHeaderLen + tbsBodyLen
  const tbs = der.subarray(tbsStart, tbsStart + tbsLen)

  // Skip AlgorithmIdentifier to get to signature BIT STRING
  let sigAlgStart = tbsStart + tbsLen
  if (der[sigAlgStart] !== 0x30) throw new Error('Invalid signatureAlgorithm')
  const { length: sigAlgLen, headerLen: sigAlgHeaderLen } = parseDERLength(der, sigAlgStart + 1)

  // Parse signature BIT STRING
  const sigBitStringStart = sigAlgStart + sigAlgHeaderLen + sigAlgLen
  if (der[sigBitStringStart] !== 0x03) throw new Error('Invalid signature BIT STRING')
  const { length: sigBitLen, headerLen: sigBitHeaderLen } = parseDERLength(der, sigBitStringStart + 1)

  // BIT STRING has a leading byte for unused bits (should be 0)
  const sigDerStart = sigBitStringStart + sigBitHeaderLen + 1  // +1 for unused bits byte
  const sigDer = der.subarray(sigDerStart, sigBitStringStart + sigBitHeaderLen + sigBitLen)

  // Decode the DER ECDSA signature (P-384)
  const issuerSignature = decodeECDSASignatureP384(sigDer)

  // Find the public key (P-256 uncompressed point after OID 1.2.840.10045.3.1.7)
  // OID for prime256v1/secp256r1: 06 08 2a 86 48 ce 3d 03 01 07
  const p256OID = Buffer.from([0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07])
  const oidIndex = der.indexOf(p256OID)
  if (oidIndex === -1) throw new Error('P-256 OID not found in certificate')

  // Public key follows: 03 42 00 04 [x 32 bytes] [y 32 bytes]
  // Search for BIT STRING (03) with length 66 (0x42) containing uncompressed point
  let pubkeyIndex = -1
  for (let i = oidIndex; i < der.length - 66; i++) {
    if (der[i] === 0x03 && der[i + 1] === 0x42 && der[i + 2] === 0x00 && der[i + 3] === 0x04) {
      pubkeyIndex = i + 4
      break
    }
  }
  if (pubkeyIndex === -1) throw new Error('Public key not found in certificate')

  const x = der.subarray(pubkeyIndex, pubkeyIndex + 32)
  const y = der.subarray(pubkeyIndex + 32, pubkeyIndex + 64)

  // Parse OIDC extensions (OID prefix 1.3.6.1.4.1.57264.1.*)
  // Full OID encoding: 06 0b 2b 06 01 04 01 83 bf 30 01 XX
  // We search for the value bytes (after tag 06 and length 0b)
  const oidcClaims: Record<string, string> = {}
  const oidcPrefix = Buffer.from([0x2b, 0x06, 0x01, 0x04, 0x01, 0x83, 0xbf, 0x30, 0x01])

  // Track offsets for specific OIDs (relative to TBS start)
  let commitOidOffset = -1
  let repoOidOffset = -1

  // Search within TBS buffer
  let searchPos = 0
  while (searchPos < tbs.length) {
    const idx = tbs.indexOf(oidcPrefix, searchPos)
    if (idx === -1) break

    const extNum = tbs[idx + oidcPrefix.length]
    // Find the UTF8String value after this OID
    const valueStart = findUTF8StringAfter(tbs, idx + oidcPrefix.length + 1)
    if (valueStart) {
      const oidName = getOIDName(extNum)
      oidcClaims[oidName] = valueStart.value

      // Track offsets for circuit (relative to TBS start, pointing at OID prefix)
      if (extNum === 0x03) commitOidOffset = idx  // .3 = sha/commit
      if (extNum === 0x05) repoOidOffset = idx    // .5 = repository
    }
    searchPos = idx + 1
  }

  if (commitOidOffset === -1) throw new Error('Commit SHA OID not found in certificate')
  if (repoOidOffset === -1) throw new Error('Repository OID not found in certificate')

  return { publicKey: { x, y }, oidcClaims, tbs, issuerSignature, oidOffsets: { commit: commitOidOffset, repo: repoOidOffset } }
}

// Parse DER length field (handles multi-byte lengths)
function parseDERLength(buf: Buffer, offset: number): { length: number; headerLen: number } {
  const firstByte = buf[offset]
  if (firstByte < 0x80) {
    return { length: firstByte, headerLen: 2 }  // 1 byte tag + 1 byte length
  }
  const numBytes = firstByte & 0x7f
  let length = 0
  for (let i = 0; i < numBytes; i++) {
    length = (length << 8) | buf[offset + 1 + i]
  }
  return { length, headerLen: 2 + numBytes }  // 1 byte tag + 1 byte length indicator + numBytes
}

// Decode P-384 ECDSA signature with low-s normalization
function decodeECDSASignatureP384(derSig: Buffer): { r: Buffer; s: Buffer } {
  // DER: 0x30 [total-len] 0x02 [r-len] [r] 0x02 [s-len] [s]
  let offset = 0
  if (derSig[offset++] !== 0x30) throw new Error('Invalid DER signature: expected SEQUENCE')

  // Parse length (could be multi-byte)
  let totalLen = derSig[offset++]
  if (totalLen & 0x80) {
    const numBytes = totalLen & 0x7f
    totalLen = 0
    for (let i = 0; i < numBytes; i++) {
      totalLen = (totalLen << 8) | derSig[offset++]
    }
  }

  if (derSig[offset++] !== 0x02) throw new Error('Invalid DER signature (r): expected INTEGER')
  const rLen = derSig[offset++]
  let r = derSig.subarray(offset, offset + rLen)
  offset += rLen

  if (derSig[offset++] !== 0x02) throw new Error('Invalid DER signature (s): expected INTEGER')
  const sLen = derSig[offset++]
  let s = derSig.subarray(offset, offset + sLen)

  // Remove leading zeros and pad to 48 bytes (P-384)
  r = padTo48Bytes(r)
  s = padTo48Bytes(s)

  // Normalize s to low-s form (required by zkpassport ECDSA)
  const sBigInt = BigInt('0x' + s.toString('hex'))
  if (sBigInt > P384_HALF_ORDER) {
    const normalizedS = P384_ORDER - sBigInt
    s = Buffer.from(normalizedS.toString(16).padStart(96, '0'), 'hex')
    console.log('Normalized P-384 high-s signature to low-s form')
  }

  return { r, s }
}

function padTo48Bytes(buf: Buffer): Buffer {
  // Remove leading zero if present
  if (buf.length === 49 && buf[0] === 0) buf = buf.subarray(1)
  if (buf.length > 48) throw new Error('Value too large for P-384')
  if (buf.length === 48) return buf
  const padded = Buffer.alloc(48)
  buf.copy(padded, 48 - buf.length)
  return padded
}

function findUTF8StringAfter(der: Buffer, start: number): { value: string } | null {
  // Look for OCTET STRING (0x04), UTF8String (0x0C), or IA5String (0x16) within next 20 bytes
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
    1: 'issuer',
    2: 'trigger',
    3: 'sha',
    4: 'workflow_name',
    5: 'repository',
    6: 'ref',
    11: 'runner_environment',
    12: 'repository_uri',
    15: 'repository_id',
    17: 'owner_id',
    21: 'run_url',
    22: 'visibility',
  }
  return names[num] || `oid_${num}`
}

// Parse in-toto statement to get artifact info
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

// Pad buffer to fixed length
function padBuffer(buf: Buffer, len: number): Buffer {
  if (buf.length > len) throw new Error(`Buffer too long: ${buf.length} > ${len}`)
  if (buf.length === len) return buf
  const padded = Buffer.alloc(len)
  buf.copy(padded)
  return padded
}

const MAX_PAE_LENGTH = 2048
const MAX_TBS_LENGTH = 1800  // Sigstore certs have many OIDC extensions

// Find artifact hash offset in PAE message (the hex string after "sha256":")
function findArtifactHashOffset(paeMessage: Buffer): number {
  const marker = Buffer.from('"sha256":"')
  const idx = paeMessage.indexOf(marker)
  if (idx === -1) throw new Error('Artifact hash marker not found in PAE message')
  return idx + marker.length
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

  // 2. Decode ECDSA signature and concatenate r||s
  const sigDer = Buffer.from(dsse.signatures[0].sig, 'base64')
  const { r, s } = decodeECDSASignature(sigDer)
  const signature = Buffer.concat([r, s])

  // 3. Parse certificate (includes TBS, issuer signature, and OID offsets)
  const { publicKey, oidcClaims, tbs, issuerSignature, oidOffsets } = parseCertificate(cert.rawBytes)

  // Pad TBS to MAX_TBS_LENGTH
  const tbsPadded = padBuffer(tbs, MAX_TBS_LENGTH)

  // 4. Parse in-toto statement
  const statement = parseInTotoStatement(dsse.payload)

  // 5. Compute hashes for public inputs
  const artifactHash = Buffer.from(statement.artifactHash, 'hex')
  const repoName = Buffer.from(statement.repo)
  const repoNamePadded = padBuffer(repoName, MAX_REPO_LENGTH)
  const repoHash = createHash('sha256').update(statement.repo).digest()
  const commitSha = Buffer.from(statement.commit, 'hex')

  // 6. Find artifact hash offset in PAE
  const artifactHashOffset = findArtifactHashOffset(paeMessage)

  return {
    pae_message: bufferToStringArray(paeMessagePadded),
    pae_message_len: paeMessage.length.toString(),

    signature: bufferToStringArray(signature),

    leaf_pubkey_x: bufferToStringArray(publicKey.x),
    leaf_pubkey_y: bufferToStringArray(publicKey.y),

    cert_tbs: bufferToStringArray(tbsPadded),
    cert_tbs_len: tbs.length.toString(),

    issuer_sig_r: bufferToStringArray(issuerSignature.r),
    issuer_sig_s: bufferToStringArray(issuerSignature.s),

    // OIDC claim extraction hints
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
    }
  }
}

function bufferToStringArray(buf: Buffer): string[] {
  return [...buf].map(b => b.toString())
}

// Fulcio Intermediate CA Public Key (P-384)
const FULCIO_INTERMEDIATE_X = Buffer.from([
  241, 21, 82, 255, 43, 7, 248, 211, 175, 184, 54, 114, 60, 134, 109, 138,
  88, 20, 23, 211, 101, 106, 182, 41, 1, 223, 71, 63, 91, 193, 4, 125,
  84, 228, 37, 123, 236, 180, 146, 238, 205, 25, 136, 126, 39, 19, 177, 239
])
const FULCIO_INTERMEDIATE_Y = Buffer.from([
  238, 155, 82, 232, 187, 239, 71, 244, 147, 147, 191, 124, 45, 88, 12, 204,
  185, 73, 224, 119, 136, 124, 93, 237, 29, 38, 158, 196, 183, 24, 165, 32,
  18, 175, 89, 18, 208, 223, 209, 128, 18, 115, 255, 216, 214, 10, 37, 231
])

// Verify leaf signature using noble/curves (for testing)
export function verifySignature(inputs: CircuitInputs): boolean {
  // Get actual PAE message length (not padded)
  const paeLen = parseInt(inputs.pae_message_len)
  const paeMessage = Buffer.from(inputs.pae_message.slice(0, paeLen).map(s => parseInt(s)))
  const msgHash = createHash('sha256').update(paeMessage).digest()

  const sig = Buffer.from(inputs.signature.map(s => parseInt(s)))

  const pubX = Buffer.from(inputs.leaf_pubkey_x.map(s => parseInt(s)))
  const pubY = Buffer.from(inputs.leaf_pubkey_y.map(s => parseInt(s)))
  // Uncompressed point: 04 || x || y
  const pubkey = Buffer.concat([Buffer.from([0x04]), pubX, pubY])

  return p256.verify(sig, msgHash, pubkey)
}

// Verify certificate chain (Fulcio signed the leaf cert)
export function verifyCertChain(inputs: CircuitInputs): boolean {
  // Get actual TBS length (not padded)
  const tbsLen = parseInt(inputs.cert_tbs_len)
  const tbs = Buffer.from(inputs.cert_tbs.slice(0, tbsLen).map(s => parseInt(s)))

  // SHA-384 hash of TBS
  const tbsHash = createHash('sha384').update(tbs).digest()

  // Reconstruct signature (r || s -> DER would be complex, use raw for noble)
  const sigR = Buffer.from(inputs.issuer_sig_r.map(s => parseInt(s)))
  const sigS = Buffer.from(inputs.issuer_sig_s.map(s => parseInt(s)))
  const sig = Buffer.concat([sigR, sigS])

  // Fulcio intermediate public key (uncompressed)
  const pubkey = Buffer.concat([Buffer.from([0x04]), FULCIO_INTERMEDIATE_X, FULCIO_INTERMEDIATE_Y])

  return p384.verify(sig, tbsHash, pubkey)
}

// Format for Prover.toml
export function toProverToml(inputs: CircuitInputs): string {
  const lines: string[] = []

  for (const [key, value] of Object.entries(inputs)) {
    if (key === '_meta') continue // Skip metadata
    if (Array.isArray(value)) {
      lines.push(`${key} = [${value.map(v => `'${v}'`).join(', ')}]`)
    } else {
      lines.push(`${key} = '${value}'`)
    }
  }

  return lines.join('\n')
}
