#!/usr/bin/env node
// Client-side: runs on your laptop, accepts WebRTC connections, makes real TCP connections
import { execSync } from 'child_process'
import { RTCPeerConnection } from 'wrtc'
import net from 'net'

const STUN = { urls: 'stun:stun.l.google.com:19302' }
const GIST_POLL_MS = 2000

function gist(id, filename, content) {
  if (id) {
    execSync(`gh gist edit ${id} -f ${filename} -`, { input: content })
    return id
  }
  const out = execSync(`gh gist create -f ${filename} -`, { input: content, encoding: 'utf8' })
  return out.trim().split('/').pop()
}

function gistRead(id, filename) {
  try {
    return execSync(`gh gist view ${id} -f ${filename}`, { encoding: 'utf8' })
  } catch { return null }
}

async function gistPoll(id, filename, timeout = 120000) {
  const start = Date.now()
  while (Date.now() - start < timeout) {
    const content = gistRead(id, filename)
    if (content) return content
    await new Promise(r => setTimeout(r, GIST_POLL_MS))
    process.stdout.write('.')
  }
  throw new Error(`Timeout waiting for ${filename}`)
}

async function main() {
  const repo = process.argv[2] || 'amiller/github-zktls'
  const profile = process.argv[3] || 'socrates1024'

  console.log('🔌 Creating WebRTC peer connection...')
  const pc = new RTCPeerConnection({ iceServers: [STUN] })

  // Create data channel
  const dc = pc.createDataChannel('proxy', { ordered: true })

  const iceCandidates = []
  pc.onicecandidate = e => {
    if (e.candidate) iceCandidates.push(e.candidate)
  }

  const offer = await pc.createOffer()
  await pc.setLocalDescription(offer)

  // Wait for ICE gathering
  await new Promise(r => {
    if (pc.iceGatheringState === 'complete') r()
    else pc.onicegatheringchange = () => pc.iceGatheringState === 'complete' && r()
  })

  console.log('📤 Creating signaling gist...')
  const gistId = gist(null, 'offer.json', JSON.stringify({
    sdp: pc.localDescription,
    candidates: iceCandidates
  }))
  console.log(`   Gist: https://gist.github.com/${gistId}`)

  console.log('🚀 Triggering workflow...')
  execSync(`gh workflow run wormhole-proof.yml -R ${repo} -f gist_id=${gistId} -f profile=${profile}`)

  console.log('⏳ Waiting for runner answer', '')
  const answerJson = await gistPoll(gistId, 'answer.json')
  const { sdp: answerSdp, candidates: remoteCandidates } = JSON.parse(answerJson)
  console.log(' received!')

  await pc.setRemoteDescription(answerSdp)
  for (const c of remoteCandidates) await pc.addIceCandidate(c)

  // Wait for data channel
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('DataChannel timeout')), 60000)
    dc.onopen = () => { clearTimeout(timeout); resolve() }
    dc.onerror = e => { clearTimeout(timeout); reject(e) }
  })
  console.log('✅ WebRTC data channel connected!')

  // Handle proxy requests from runner - we make the actual TCP connections
  const connections = new Map()

  dc.onmessage = e => {
    const msg = JSON.parse(e.data)

    if (msg.type === 'connect') {
      console.log(`← ${msg.host}:${msg.port}`)
      const sock = net.createConnection(msg.port, msg.host, () => {
        connections.set(msg.id, sock)
        dc.send(JSON.stringify({ type: 'connected', id: msg.id }))
      })

      sock.on('data', data => {
        dc.send(JSON.stringify({ type: 'data', id: msg.id, data: data.toString('base64') }))
      })

      sock.on('error', err => {
        console.log(`   error: ${err.message}`)
        dc.send(JSON.stringify({ type: 'error', id: msg.id, error: err.message }))
        connections.delete(msg.id)
      })

      sock.on('close', () => {
        dc.send(JSON.stringify({ type: 'close', id: msg.id }))
        connections.delete(msg.id)
      })
    } else if (msg.type === 'data') {
      const sock = connections.get(msg.id)
      if (sock) sock.write(Buffer.from(msg.data, 'base64'))
    } else if (msg.type === 'close') {
      const sock = connections.get(msg.id)
      if (sock) sock.end()
      connections.delete(msg.id)
    }
  }

  console.log('🌐 Proxy tunnel active! Runner browser traffic will exit through your IP.')
  console.log('   Press Ctrl+C to stop.')

  // Keep alive
  process.on('SIGINT', () => {
    console.log('\n👋 Shutting down...')
    pc.close()
    process.exit(0)
  })

  await new Promise(() => {})
}

main().catch(e => { console.error(e); process.exit(1) })
