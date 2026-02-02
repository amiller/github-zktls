#!/usr/bin/env node
// Simple client: runs SOCKS5 server locally, exposes via ngrok, triggers workflow
import { execSync, spawn } from 'child_process'
import net from 'net'

async function main() {
  const repo = process.argv[2] || 'amiller/github-zktls'
  const profile = process.argv[3] || 'socrates1024'

  // Start local SOCKS5 server that makes real connections
  const sockets = new Map()
  const server = net.createServer(socket => {
    const id = Math.random().toString(36).slice(2, 8)
    socket.once('data', buf => {
      if (buf[0] !== 0x05) return socket.end()
      socket.write(Buffer.from([0x05, 0x00]))
      socket.once('data', req => {
        if (req[1] !== 0x01) return socket.end()
        let host, port
        if (req[3] === 0x01) { host = Array.from(req.slice(4, 8)).join('.'); port = req.readUInt16BE(8) }
        else if (req[3] === 0x03) { const len = req[4]; host = req.slice(5, 5 + len).toString(); port = req.readUInt16BE(5 + len) }
        else return socket.end()

        console.log(`← ${host}:${port}`)
        const remote = net.createConnection(port, host, () => {
          socket.write(Buffer.from([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]))
          socket.pipe(remote).pipe(socket)
        })
        remote.on('error', () => socket.end())
      })
    })
    socket.on('error', () => {})
  })

  await new Promise(r => server.listen(1080, '127.0.0.1', r))
  console.log('🧦 Local SOCKS5 server on 127.0.0.1:1080')

  // Start ngrok
  console.log('🚇 Starting ngrok tunnel...')
  const ngrok = spawn('ngrok', ['tcp', '1080', '--log=stdout'], { stdio: ['ignore', 'pipe', 'pipe'] })

  let ngrokUrl
  for await (const chunk of ngrok.stdout) {
    const line = chunk.toString()
    const match = line.match(/url=(tcp:\/\/[^\s]+)/)
    if (match) {
      ngrokUrl = match[1]
      break
    }
  }

  if (!ngrokUrl) throw new Error('Failed to get ngrok URL')
  console.log(`   Tunnel: ${ngrokUrl}`)

  // Parse ngrok URL for workflow
  const [, host, port] = ngrokUrl.match(/tcp:\/\/([^:]+):(\d+)/)

  console.log('🚀 Triggering workflow...')
  execSync(`gh workflow run ngrok-proof.yml -R ${repo} -f proxy_host=${host} -f proxy_port=${port} -f profile=${profile}`)

  console.log('🌐 Tunnel active! Press Ctrl+C to stop.\n')

  process.on('SIGINT', () => {
    ngrok.kill()
    server.close()
    process.exit(0)
  })

  await new Promise(() => {})
}

main().catch(e => { console.error(e); process.exit(1) })
