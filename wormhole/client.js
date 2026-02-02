#!/usr/bin/env node
// Client-side: runs on your laptop, accepts WebRTC connections, makes real TCP connections
import { execSync } from 'child_process'
import nodeDataChannel from 'node-datachannel'
import net from 'net'

const { PeerConnection } = nodeDataChannel

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
    return execSync(`gh gist view ${id} -f ${filename}`, { encoding: 'utf8', timeout: 10000 })
  } catch { return null }
}

async function gistPoll(id, filename, timeout = 180000) {
  const start = Date.now()
  while (Date.now() - start < timeout) {
    const content = gistRead(id, filename)
    if (content) return content
    await new Promise(r => setTimeout(r, 2000))
    process.stdout.write('.')
  }
  throw new Error(`Timeout waiting for ${filename}`)
}

async function main() {
  const repo = process.argv[2] || 'amiller/github-zktls'
  const profile = process.argv[3] || 'socrates1024'

  console.log('🔌 Creating WebRTC peer connection...')
  const pc = new PeerConnection('client', { iceServers: ['stun:stun.l.google.com:19302'] })

  const connections = new Map()
  let dc

  pc.onLocalDescription((sdp, type) => {
    console.log(`   Local ${type} ready`)
  })

  pc.onLocalCandidate((candidate, mid) => {
    console.log(`   ICE candidate: ${candidate.slice(0, 50)}...`)
  })

  // Create data channel
  dc = pc.createDataChannel('proxy')

  dc.onOpen(() => {
    console.log('✅ WebRTC data channel connected!')
    console.log('🌐 Proxy tunnel active! Runner traffic exits through your IP.')
    console.log('   Press Ctrl+C to stop.\n')
  })

  dc.onMessage(msg => {
    try {
      const data = JSON.parse(msg)
      if (data.type === 'connect') {
        console.log(`← ${data.host}:${data.port}`)
        const sock = net.createConnection(data.port, data.host, () => {
          connections.set(data.id, sock)
          dc.sendMessage(JSON.stringify({ type: 'connected', id: data.id }))
        })
        sock.on('data', buf => {
          dc.sendMessage(JSON.stringify({ type: 'data', id: data.id, data: buf.toString('base64') }))
        })
        sock.on('error', err => {
          console.log(`   error: ${err.message}`)
          dc.sendMessage(JSON.stringify({ type: 'error', id: data.id, error: err.message }))
          connections.delete(data.id)
        })
        sock.on('close', () => {
          dc.sendMessage(JSON.stringify({ type: 'close', id: data.id }))
          connections.delete(data.id)
        })
      } else if (data.type === 'data') {
        const sock = connections.get(data.id)
        if (sock) sock.write(Buffer.from(data.data, 'base64'))
      } else if (data.type === 'close') {
        const sock = connections.get(data.id)
        if (sock) sock.end()
        connections.delete(data.id)
      }
    } catch (e) {
      console.error('Message parse error:', e)
    }
  })

  // Wait a moment for ICE gathering
  await new Promise(r => setTimeout(r, 1000))

  const offer = pc.localDescription()
  console.log('📤 Creating signaling gist...')
  const gistId = gist(null, 'offer.json', JSON.stringify({ sdp: offer.sdp, type: offer.type }))
  console.log(`   Gist: https://gist.github.com/${gistId}`)

  console.log('🚀 Triggering workflow...')
  execSync(`gh workflow run wormhole-proof.yml -R ${repo} -f gist_id=${gistId} -f profile=${profile}`)

  console.log('⏳ Waiting for runner answer', '')
  const answerJson = await gistPoll(gistId, 'answer.json')
  const answer = JSON.parse(answerJson)
  console.log(' received!')

  pc.setRemoteDescription(answer.sdp, answer.type)

  // Keep alive
  process.on('SIGINT', () => {
    console.log('\n👋 Shutting down...')
    pc.close()
    process.exit(0)
  })

  await new Promise(() => {})
}

main().catch(e => { console.error(e); process.exit(1) })
