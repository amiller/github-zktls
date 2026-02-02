#!/usr/bin/env node
// Runner: reads offer from env, prints answer to logs, SOCKS5 proxy over data channel
import nodeDataChannel from 'node-datachannel'
import net from 'net'

const { PeerConnection } = nodeDataChannel

async function main() {
  const offerB64 = process.env.OFFER
  if (!offerB64) throw new Error('OFFER env required')

  const offer = JSON.parse(Buffer.from(offerB64, 'base64').toString())
  console.log('📥 Got offer from workflow input')

  const pc = new PeerConnection('runner', { iceServers: ['stun:stun.l.google.com:19302'] })
  const sockets = new Map()
  let dc

  pc.onDataChannel(channel => {
    dc = channel
    dc.onOpen(() => {
      console.log('✅ Data channel open!')
      startSocksServer()
    })
    dc.onMessage(msg => {
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

          console.log(`→ ${host}:${port}`)
          dc.sendMessage(JSON.stringify({ type: 'connect', id, host, port }))
          socket.on('data', d => dc.sendMessage(JSON.stringify({ type: 'data', id, data: d.toString('base64') })))
        })
      })
      socket.on('error', () => {})
      socket.on('close', () => { dc?.sendMessage(JSON.stringify({ type: 'close', id })); sockets.delete(id) })
    }).listen(1080, '127.0.0.1', () => console.log('🧦 SOCKS5 proxy on 127.0.0.1:1080'))
  }

  pc.setRemoteDescription(offer.sdp, offer.type)
  await new Promise(r => setTimeout(r, 2000))

  const answer = pc.localDescription()
  const answerB64 = Buffer.from(JSON.stringify({ sdp: answer.sdp, type: answer.type })).toString('base64')

  // Calculate next 5-second boundary for synchronized hole punch
  const now = Date.now()
  const punchTime = Math.ceil((now + 5000) / 5000) * 5000  // next %5=0 boundary, at least 5s from now

  // Print answer + punch time with markers for client to find in logs
  console.log(`ANSWER_START${answerB64}|${punchTime}ANSWER_END`)
  console.log(`🕐 Hole punch scheduled for ${new Date(punchTime).toISOString()}`)

  // Wait until punch time, then both sides should attempt simultaneously
  await new Promise(r => setTimeout(r, punchTime - Date.now()))
  console.log('🔓 Punching now!')

  console.log('⏳ Waiting for connection...')
  await new Promise(() => {})
}

main().catch(e => { console.error(e); process.exit(1) })
