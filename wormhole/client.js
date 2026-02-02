#!/usr/bin/env node
// Client: creates offer, passes via workflow input, watches logs for answer
import { execSync, spawn } from 'child_process'
import nodeDataChannel from 'node-datachannel'
import net from 'net'

const { PeerConnection } = nodeDataChannel

async function getCloudflareIceServers() {
  const res = await fetch('https://speed.cloudflare.com/turn-creds')
  const { urls, username, credential } = await res.json()
  // Convert to node-datachannel format
  return urls.map(url => {
    if (url.startsWith('stun:')) return url
    // turn:user:pass@host format
    const match = url.match(/(turns?):([^?]+)(\?.*)?/)
    if (match) {
      const [, proto, hostPort, params] = match
      return `${proto}:${username}:${credential}@${hostPort}`
    }
    return url
  })
}

async function main() {
  const repo = process.argv[2] || 'amiller/github-zktls'
  const profile = process.argv[3] || 'socrates1024'

  console.log('🔌 Fetching Cloudflare TURN credentials...')
  const iceServers = await getCloudflareIceServers()
  console.log(`   Got ${iceServers.length} ICE servers`)

  console.log('🔌 Creating WebRTC peer connection (with TURN relay)...')
  const pc = new PeerConnection('client', { iceServers })
  const iceCandidates = []

  pc.onLocalCandidate(candidate => {
    iceCandidates.push(candidate)
  })

  pc.onGatheringStateChange(state => {
    console.log(`   ICE gathering: ${state}`)
  })

  const connections = new Map()
  const dc = pc.createDataChannel('proxy')

  dc.onOpen(() => {
    console.log('✅ WebRTC data channel connected!')
    console.log('🌐 Proxy tunnel active! Runner traffic exits through your IP.')
    console.log('   Press Ctrl+C to stop.\n')
  })

  dc.onMessage(msg => {
    const data = JSON.parse(msg)
    if (data.type === 'connect') {
      console.log(`← ${data.host}:${data.port}`)
      const sock = net.createConnection(data.port, data.host, () => {
        connections.set(data.id, sock)
        dc.sendMessage(JSON.stringify({ type: 'connected', id: data.id }))
      })
      sock.on('data', buf => dc.sendMessage(JSON.stringify({ type: 'data', id: data.id, data: buf.toString('base64') })))
      sock.on('error', err => {
        dc.sendMessage(JSON.stringify({ type: 'error', id: data.id }))
        connections.delete(data.id)
      })
      sock.on('close', () => {
        dc.sendMessage(JSON.stringify({ type: 'close', id: data.id }))
        connections.delete(data.id)
      })
    } else if (data.type === 'data') {
      connections.get(data.id)?.write(Buffer.from(data.data, 'base64'))
    } else if (data.type === 'close') {
      connections.get(data.id)?.end()
      connections.delete(data.id)
    }
  })

  // Wait for ICE gathering (5s for TURN relay)
  console.log('⏳ Gathering ICE candidates (5s)...')
  await new Promise(r => setTimeout(r, 5000))

  console.log(`   Gathered ${iceCandidates.length} candidates`)
  const types = iceCandidates.map(c => c.match(/typ (\w+)/)?.[1])
  console.log(`   Types: ${[...new Set(types)].join(', ')}`)
  if (!types.includes('relay')) console.log('   ⚠️  No relay candidates!')

  const offer = pc.localDescription()

  // Base64 encode offer for workflow input
  const offerB64 = Buffer.from(JSON.stringify({ sdp: offer.sdp, type: offer.type })).toString('base64')

  console.log('🚀 Triggering workflow with offer in input...')
  execSync(`gh workflow run wormhole-proof.yml -R ${repo} -f offer=${offerB64} -f profile=${profile}`)

  // Get the run ID
  await new Promise(r => setTimeout(r, 3000))
  const runId = execSync(`gh run list -R ${repo} --workflow=wormhole-proof.yml -L1 --json databaseId -q '.[0].databaseId'`, { encoding: 'utf8' }).trim()
  console.log(`   Run: https://github.com/${repo}/actions/runs/${runId}`)

  // Watch logs for answer
  console.log('⏳ Watching logs for answer...')
  const { answer, punchTime } = await watchForAnswer(repo, runId)
  console.log('   Got answer!')

  pc.setRemoteDescription(answer.sdp, answer.type)

  // Wait for synchronized hole punch time
  const waitMs = punchTime - Date.now()
  if (waitMs > 0) {
    console.log(`🕐 Hole punch in ${Math.round(waitMs/1000)}s at ${new Date(punchTime).toISOString()}`)
    await new Promise(r => setTimeout(r, waitMs))
  }
  console.log('🔓 Punching now!')

  process.on('SIGINT', () => { pc.close(); process.exit(0) })
  await new Promise(() => {})
}

async function watchForAnswer(repo, runId) {
  // Poll logs looking for ANSWER_START...ANSWER_END markers
  const start = Date.now()
  while (Date.now() - start < 180000) {
    try {
      const logs = execSync(`gh run view ${runId} -R ${repo} --log 2>/dev/null || true`, { encoding: 'utf8', maxBuffer: 10 * 1024 * 1024 })
      const match = logs.match(/ANSWER_START(.+?)\|(\d+)ANSWER_END/)
      if (match) {
        const answer = JSON.parse(Buffer.from(match[1], 'base64').toString())
        const punchTime = parseInt(match[2])
        return { answer, punchTime }
      }
    } catch {}
    await new Promise(r => setTimeout(r, 2000))
    process.stdout.write('.')
  }
  throw new Error('Timeout waiting for answer in logs')
}

main().catch(e => { console.error(e); process.exit(1) })
