#!/usr/bin/env node
// Runner-side: runs in GitHub Actions, SOCKS5 server that forwards through data channel to client
import nodeDataChannel from 'node-datachannel'
import { execSync } from 'child_process'
import net from 'net'

const { PeerConnection } = nodeDataChannel

function gist(id, filename, content) {
  execSync(`gh gist edit ${id} -f ${filename} -`, { input: content })
}

function gistRead(id, filename) {
  try {
    return execSync(`gh gist view ${id} -f ${filename}`, { encoding: 'utf8', timeout: 10000 })
  } catch { return null }
}

async function main() {
  const gistId = process.env.GIST_ID
  if (!gistId) throw new Error('GIST_ID env required')

  console.log('📥 Reading offer from gist...')
  const offerJson = gistRead(gistId, 'offer.json')
  if (!offerJson) throw new Error('No offer found in gist')
  const offer = JSON.parse(offerJson)

  console.log('🔌 Creating WebRTC peer connection...')
  const pc = new PeerConnection('runner', { iceServers: ['stun:stun.l.google.com:19302'] })

  const sockets = new Map()
  let dc

  pc.onLocalDescription((sdp, type) => {
    console.log(`   Local ${type} ready`)
  })

  pc.onLocalCandidate((candidate, mid) => {
    console.log(`   ICE candidate: ${candidate.slice(0, 50)}...`)
  })

  pc.onDataChannel(channel => {
    console.log('   Data channel received!')
    dc = channel
    setupDataChannel()
  })

  function setupDataChannel() {
    dc.onOpen(() => {
      console.log('✅ Data channel open!')
      startSocksServer()
    })

    dc.onMessage(msg => {
      try {
        const data = JSON.parse(msg)
        const sock = sockets.get(data.id)
        if (!sock) return

        if (data.type === 'connected') {
          sock.write(Buffer.from([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0])) // SOCKS5 success
        } else if (data.type === 'data') {
          sock.write(Buffer.from(data.data, 'base64'))
        } else if (data.type === 'close') {
          sock.end()
          sockets.delete(data.id)
        } else if (data.type === 'error') {
          sock.write(Buffer.from([0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0])) // SOCKS5 failure
          sock.end()
          sockets.delete(data.id)
        }
      } catch (e) {
        console.error('Message parse error:', e)
      }
    })
  }

  function startSocksServer() {
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
          dc.sendMessage(JSON.stringify({ type: 'connect', id, host, port }))

          socket.on('data', data => {
            dc.sendMessage(JSON.stringify({ type: 'data', id, data: data.toString('base64') }))
          })
        })
      })

      socket.on('error', () => {})
      socket.on('close', () => {
        dc.sendMessage(JSON.stringify({ type: 'close', id }))
        sockets.delete(id)
      })
    })

    server.listen(1080, '127.0.0.1', () => {
      console.log('🧦 SOCKS5 proxy listening on 127.0.0.1:1080')
    })
  }

  // Set remote offer and create answer
  pc.setRemoteDescription(offer.sdp, offer.type)

  // Wait for ICE gathering
  await new Promise(r => setTimeout(r, 2000))

  const answer = pc.localDescription()
  console.log('📤 Posting answer to gist...')
  gist(gistId, 'answer.json', JSON.stringify({ sdp: answer.sdp, type: answer.type }))

  console.log('⏳ Waiting for connection...')

  // Keep alive
  await new Promise(() => {})
}

main().catch(e => { console.error(e); process.exit(1) })
