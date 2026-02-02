#!/usr/bin/env node
// Local test: runs both client and runner in same process to test WebRTC + SOCKS5
import nodeDataChannel from 'node-datachannel'
import net from 'net'

const { PeerConnection } = nodeDataChannel

async function main() {
  console.log('🧪 Local WebRTC + SOCKS5 test\n')

  // === CLIENT SIDE ===
  console.log('CLIENT: Creating peer connection...')
  const clientPc = new PeerConnection('client', { iceServers: ['stun:stun.l.google.com:19302'] })
  const connections = new Map()

  const dc = clientPc.createDataChannel('proxy')

  dc.onOpen(() => console.log('CLIENT: Data channel open!'))

  dc.onMessage(msg => {
    const data = JSON.parse(msg)
    if (data.type === 'connect') {
      console.log(`CLIENT: ← connect ${data.host}:${data.port}`)
      const sock = net.createConnection(data.port, data.host, () => {
        connections.set(data.id, sock)
        dc.sendMessage(JSON.stringify({ type: 'connected', id: data.id }))
      })
      sock.on('data', buf => dc.sendMessage(JSON.stringify({ type: 'data', id: data.id, data: buf.toString('base64') })))
      sock.on('error', () => dc.sendMessage(JSON.stringify({ type: 'error', id: data.id })))
      sock.on('close', () => { dc.sendMessage(JSON.stringify({ type: 'close', id: data.id })); connections.delete(data.id) })
    } else if (data.type === 'data') {
      connections.get(data.id)?.write(Buffer.from(data.data, 'base64'))
    } else if (data.type === 'close') {
      connections.get(data.id)?.end(); connections.delete(data.id)
    }
  })

  await new Promise(r => setTimeout(r, 1000))
  const offer = clientPc.localDescription()
  console.log(`CLIENT: Offer ready (${offer.type})\n`)

  // === RUNNER SIDE ===
  console.log('RUNNER: Creating peer connection...')
  const runnerPc = new PeerConnection('runner', { iceServers: ['stun:stun.l.google.com:19302'] })
  const sockets = new Map()
  let runnerDc

  runnerPc.onDataChannel(channel => {
    runnerDc = channel
    runnerDc.onOpen(() => {
      console.log('RUNNER: Data channel open!')
      startSocksServer()
    })
    runnerDc.onMessage(msg => {
      const data = JSON.parse(msg)
      const sock = sockets.get(data.id)
      if (!sock) return
      if (data.type === 'connected') sock.write(Buffer.from([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]))
      else if (data.type === 'data') sock.write(Buffer.from(data.data, 'base64'))
      else if (data.type === 'close' || data.type === 'error') { sock.end(); sockets.delete(data.id) }
    })
  })

  function startSocksServer() {
    net.createServer(socket => {
      const id = Math.random().toString(36).slice(2, 8)
      sockets.set(id, socket)
      socket.once('data', buf => {
        if (buf[0] !== 0x05) return socket.end()
        socket.write(Buffer.from([0x05, 0x00]))
        socket.once('data', req => {
          if (req[1] !== 0x01) return socket.end()
          let host, port
          if (req[3] === 0x01) { host = Array.from(req.slice(4, 8)).join('.'); port = req.readUInt16BE(8) }
          else if (req[3] === 0x03) { const len = req[4]; host = req.slice(5, 5 + len).toString(); port = req.readUInt16BE(5 + len) }
          else return socket.end()
          console.log(`RUNNER: → ${host}:${port}`)
          runnerDc.sendMessage(JSON.stringify({ type: 'connect', id, host, port }))
          socket.on('data', d => runnerDc.sendMessage(JSON.stringify({ type: 'data', id, data: d.toString('base64') })))
        })
      })
      socket.on('error', () => {})
      socket.on('close', () => { runnerDc?.sendMessage(JSON.stringify({ type: 'close', id })); sockets.delete(id) })
    }).listen(1080, '127.0.0.1', () => {
      console.log('\n✅ SOCKS5 proxy ready on 127.0.0.1:1080')
      console.log('   Test: curl --socks5 127.0.0.1:1080 https://api.ipify.org\n')
    })
  }

  // Exchange SDP
  runnerPc.setRemoteDescription(offer.sdp, offer.type)
  await new Promise(r => setTimeout(r, 1000))

  const answer = runnerPc.localDescription()
  console.log(`RUNNER: Answer ready (${answer.type})\n`)

  clientPc.setRemoteDescription(answer.sdp, answer.type)

  console.log('⏳ Waiting for connection...\n')

  // Keep alive
  process.on('SIGINT', () => process.exit(0))
  await new Promise(() => {})
}

main().catch(e => { console.error(e); process.exit(1) })
