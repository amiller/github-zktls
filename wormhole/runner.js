#!/usr/bin/env node
// Runner-side: runs in GitHub Actions, SOCKS5 server that forwards through data channel to client
import { RTCPeerConnection } from 'wrtc'
import { execSync } from 'child_process'
import net from 'net'

const STUN = { urls: 'stun:stun.l.google.com:19302' }
const GIST_POLL_MS = 2000

function gist(id, filename, content) {
  execSync(`gh gist edit ${id} -f ${filename} -`, { input: content })
}

function gistRead(id, filename) {
  try {
    return execSync(`gh gist view ${id} -f ${filename}`, { encoding: 'utf8' })
  } catch { return null }
}

async function main() {
  const gistId = process.env.GIST_ID
  if (!gistId) throw new Error('GIST_ID env required')

  console.log('📥 Reading offer from gist...')
  const offerJson = gistRead(gistId, 'offer.json')
  if (!offerJson) throw new Error('No offer found in gist')
  const { sdp: offerSdp, candidates: remoteCandidates } = JSON.parse(offerJson)

  console.log('🔌 Creating WebRTC peer connection...')
  const pc = new RTCPeerConnection({ iceServers: [STUN] })

  let dc
  pc.ondatachannel = e => { dc = e.channel }

  const iceCandidates = []
  pc.onicecandidate = e => {
    if (e.candidate) iceCandidates.push(e.candidate)
  }

  await pc.setRemoteDescription(offerSdp)
  for (const c of remoteCandidates) await pc.addIceCandidate(c)

  const answer = await pc.createAnswer()
  await pc.setLocalDescription(answer)

  // Wait for ICE gathering
  await new Promise(r => {
    if (pc.iceGatheringState === 'complete') r()
    else pc.onicegatheringchange = () => pc.iceGatheringState === 'complete' && r()
  })

  console.log('📤 Posting answer to gist...')
  gist(gistId, 'answer.json', JSON.stringify({
    sdp: pc.localDescription,
    candidates: iceCandidates
  }))

  // Wait for data channel
  console.log('⏳ Waiting for data channel...')
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('DataChannel timeout')), 60000)
    const check = () => {
      if (dc && dc.readyState === 'open') { clearTimeout(timeout); resolve() }
    }
    pc.ondatachannel = e => {
      dc = e.channel
      dc.onopen = check
      if (dc.readyState === 'open') check()
    }
  })
  console.log('✅ WebRTC connected!')

  // SOCKS5 server - browser connects here, we forward through data channel
  const sockets = new Map()
  const socksPort = 1080

  // Handle responses from client
  dc.onmessage = e => {
    const msg = JSON.parse(e.data)
    const sock = sockets.get(msg.id)
    if (!sock) return

    if (msg.type === 'connected') {
      sock.write(Buffer.from([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0])) // SOCKS5 success
    } else if (msg.type === 'data') {
      sock.write(Buffer.from(msg.data, 'base64'))
    } else if (msg.type === 'close') {
      sock.end()
      sockets.delete(msg.id)
    } else if (msg.type === 'error') {
      sock.write(Buffer.from([0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0])) // SOCKS5 failure
      sock.end()
      sockets.delete(msg.id)
    }
  }

  const server = net.createServer(socket => {
    const id = Math.random().toString(36).slice(2, 8)
    sockets.set(id, socket)

    socket.once('data', buf => {
      if (buf[0] !== 0x05) return socket.end()
      socket.write(Buffer.from([0x05, 0x00])) // no auth

      socket.once('data', req => {
        if (req[1] !== 0x01) return socket.end() // only CONNECT

        let host, port
        if (req[3] === 0x01) { // IPv4
          host = Array.from(req.slice(4, 8)).join('.')
          port = req.readUInt16BE(8)
        } else if (req[3] === 0x03) { // Domain
          const len = req[4]
          host = req.slice(5, 5 + len).toString()
          port = req.readUInt16BE(5 + len)
        } else return socket.end()

        console.log(`→ ${host}:${port}`)
        dc.send(JSON.stringify({ type: 'connect', id, host, port }))

        socket.on('data', data => {
          dc.send(JSON.stringify({ type: 'data', id, data: data.toString('base64') }))
        })
      })
    })

    socket.on('error', () => {})
    socket.on('close', () => {
      dc.send(JSON.stringify({ type: 'close', id }))
      sockets.delete(id)
    })
  })

  server.listen(socksPort, '127.0.0.1', () => {
    console.log(`🧦 SOCKS5 proxy listening on 127.0.0.1:${socksPort}`)
    // Signal ready
    console.log('::set-output name=proxy_ready::true')
  })

  // Keep alive
  await new Promise(() => {})
}

main().catch(e => { console.error(e); process.exit(1) })
