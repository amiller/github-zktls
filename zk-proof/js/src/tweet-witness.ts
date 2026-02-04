// Tweet Attestation Witness Generator
// Generates circuit inputs from Sigstore attestation bundles for tweet captures

import { createHash } from 'crypto'
import { computePAE, decodeECDSASignature, parseCertificate } from './index'

const MAX_PAE_LENGTH = 2048
const MAX_URL_LENGTH = 256
const MAX_HANDLE_LENGTH = 64

export interface TweetCertificate {
  type: 'tweet-capture'
  tweet_url: string
  tweet_text: string
  author_handle: string
  author_name: string
  recipient_address: string
  logged_in_verified: boolean
  timestamp: string
  github_run_id?: string
  github_run_url?: string
}

export interface TweetCircuitInputs {
  // Private inputs
  pae_message: string[]
  pae_message_len: string
  signature: string[]
  leaf_pubkey_x: string[]
  leaf_pubkey_y: string[]
  tweet_url: string[]
  tweet_url_len: string
  author_handle: string[]
  author_handle_len: string
  recipient_bytes: string[]
  tweet_url_offset: string
  author_handle_offset: string
  recipient_offset: string

  // Public inputs
  tweet_hash: string[]
  author_hash: string[]
  recipient: string[]

  // Metadata (not circuit inputs)
  _meta: {
    tweet_url: string
    author_handle: string
    recipient_address: string
    tweet_text: string
  }
}

function padBuffer(buf: Buffer, len: number): Buffer {
  if (buf.length > len) throw new Error(`Buffer too long: ${buf.length} > ${len}`)
  if (buf.length === len) return buf
  const padded = Buffer.alloc(len)
  buf.copy(padded)
  return padded
}

function bufferToStringArray(buf: Buffer): string[] {
  return [...buf].map(b => b.toString())
}

function hexToBytes(hex: string): Buffer {
  if (hex.startsWith('0x')) hex = hex.slice(2)
  return Buffer.from(hex, 'hex')
}

// Find offset of a string in buffer (as JSON string with quotes)
function findJsonStringOffset(buf: Buffer, str: string): number {
  const searchStr = `"${str}"`
  const idx = buf.indexOf(searchStr)
  if (idx === -1) throw new Error(`String "${str}" not found in payload`)
  return idx
}

// Find offset of hex address in buffer (0x...)
function findHexAddressOffset(buf: Buffer, address: string): number {
  const idx = buf.indexOf(address.toLowerCase())
  if (idx === -1) {
    const idxUpper = buf.indexOf(address)
    if (idxUpper === -1) throw new Error(`Address ${address} not found in payload`)
    return idxUpper
  }
  return idx
}

export function generateTweetCircuitInputs(bundleJson: any): TweetCircuitInputs {
  const bundle = bundleJson.attestations?.[0]?.bundle || bundleJson
  const dsse = bundle.dsseEnvelope
  const cert = bundle.verificationMaterial.certificate

  // Decode and parse the payload (contains tweet certificate)
  const payloadBytes = Buffer.from(dsse.payload, 'base64')
  const payload = JSON.parse(payloadBytes.toString())

  // Extract certificate from in-toto statement
  const certificate: TweetCertificate = payload.predicate || payload

  if (certificate.type !== 'tweet-capture') {
    throw new Error(`Invalid certificate type: ${certificate.type}`)
  }

  // Compute PAE message
  const paeMessage = computePAE(dsse.payloadType, payloadBytes)
  const paeMessagePadded = padBuffer(paeMessage, MAX_PAE_LENGTH)

  // Decode signature
  const sigDer = Buffer.from(dsse.signatures[0].sig, 'base64')
  const { r, s } = decodeECDSASignature(sigDer)
  const signature = Buffer.concat([r, s])

  // Parse certificate for public key
  const { publicKey } = parseCertificate(cert.rawBytes)

  // Prepare tweet URL
  const tweetUrl = Buffer.from(certificate.tweet_url)
  const tweetUrlPadded = padBuffer(tweetUrl, MAX_URL_LENGTH)

  // Prepare author handle
  const authorHandle = Buffer.from(certificate.author_handle)
  const authorHandlePadded = padBuffer(authorHandle, MAX_HANDLE_LENGTH)

  // Prepare recipient address (20 bytes)
  const recipientBytes = hexToBytes(certificate.recipient_address)
  if (recipientBytes.length !== 20) {
    throw new Error(`Invalid recipient address length: ${recipientBytes.length}`)
  }

  // Find offsets in PAE message
  const tweetUrlOffset = findJsonStringOffset(paeMessage, certificate.tweet_url)
  const authorHandleOffset = findJsonStringOffset(paeMessage, certificate.author_handle)
  const recipientOffset = findHexAddressOffset(paeMessage, certificate.recipient_address)

  // Compute public input hashes
  const tweetHash = createHash('sha256').update(certificate.tweet_url).digest()
  const authorHash = createHash('sha256').update(certificate.author_handle).digest()

  return {
    pae_message: bufferToStringArray(paeMessagePadded),
    pae_message_len: paeMessage.length.toString(),
    signature: bufferToStringArray(signature),
    leaf_pubkey_x: bufferToStringArray(publicKey.x),
    leaf_pubkey_y: bufferToStringArray(publicKey.y),
    tweet_url: bufferToStringArray(tweetUrlPadded),
    tweet_url_len: tweetUrl.length.toString(),
    author_handle: bufferToStringArray(authorHandlePadded),
    author_handle_len: authorHandle.length.toString(),
    recipient_bytes: bufferToStringArray(recipientBytes),
    tweet_url_offset: tweetUrlOffset.toString(),
    author_handle_offset: authorHandleOffset.toString(),
    recipient_offset: recipientOffset.toString(),
    tweet_hash: bufferToStringArray(tweetHash),
    author_hash: bufferToStringArray(authorHash),
    recipient: bufferToStringArray(recipientBytes),
    _meta: {
      tweet_url: certificate.tweet_url,
      author_handle: certificate.author_handle,
      recipient_address: certificate.recipient_address,
      tweet_text: certificate.tweet_text
    }
  }
}

// Format for Noir Prover.toml
export function toTweetProverToml(inputs: TweetCircuitInputs): string {
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
