#!/usr/bin/env node
// Fetches faucet claims via RPC and generates leaderboard JSON

const FAUCET = process.env.FAUCET_ADDRESS || '0x72cd70d28284dD215257f73e1C5aD8e28847215B'
const RPC_URL = process.env.RPC_URL || 'https://base-sepolia-rpc.publicnode.com'
const CLAIMED_TOPIC = '0x9d2f14df77ba038ff6f9ba99bbdcfbc30f1650b9574e3b7bbae993df15a92f30'
const OUT_FILE = 'examples/leaderboard/claims.json'
const START_BLOCK = 37_314_000 // Just before faucet deployment
const CHUNK_SIZE = 50_000

async function rpc(method, params) {
  const res = await fetch(RPC_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params })
  })
  const data = await res.json()
  if (data.error) throw new Error(`RPC ${method}: ${data.error.message}`)
  return data.result
}

async function main() {
  const latest = parseInt(await rpc('eth_blockNumber', []), 16)
  console.log(`Scanning blocks ${START_BLOCK} to ${latest} (${latest - START_BLOCK} blocks)`)

  // Fetch logs in chunks (RPC providers limit range to ~50k blocks)
  const allLogs = []
  for (let from = START_BLOCK; from <= latest; from += CHUNK_SIZE) {
    const to = Math.min(from + CHUNK_SIZE - 1, latest)
    const logs = await rpc('eth_getLogs', [{
      address: FAUCET,
      topics: [CLAIMED_TOPIC],
      fromBlock: '0x' + from.toString(16),
      toBlock: '0x' + to.toString(16)
    }])
    if (logs.length) allLogs.push(...logs)
  }

  if (!allLogs.length) {
    console.log('No claims found')
    writeOutput({ claims: [], leaderboard: [], stats: { totalClaims: 0, uniqueUsers: 0, totalEth: '0.000000' } })
    return
  }

  console.log(`Found ${allLogs.length} Claimed events`)

  const txCache = {}
  const blockCache = {}
  const claims = []

  for (const log of allLogs) {
    const recipient = '0x' + log.topics[1].slice(26)
    const amount = BigInt(log.data)

    let username = 'unknown'
    if (!txCache[log.transactionHash]) {
      txCache[log.transactionHash] = await rpc('eth_getTransactionByHash', [log.transactionHash])
      await sleep(100)
    }

    const tx = txCache[log.transactionHash]
    if (tx?.input) {
      try { username = decodeClaimCalldata(tx.input).username }
      catch (e) { console.error(`Failed to decode tx ${log.transactionHash}:`, e.message) }
    }

    if (!blockCache[log.blockNumber]) {
      const block = await rpc('eth_getBlockByNumber', [log.blockNumber, false])
      blockCache[log.blockNumber] = parseInt(block.timestamp, 16)
    }

    claims.push({
      username, recipient,
      amount: amount.toString(),
      amountEth: formatEth(amount),
      txHash: log.transactionHash,
      timestamp: new Date(blockCache[log.blockNumber] * 1000).toISOString(),
      block: parseInt(log.blockNumber, 16).toString()
    })
  }

  claims.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp))

  const userCounts = {}
  const userTotals = {}
  let totalWei = 0n
  for (const c of claims) {
    userCounts[c.username] = (userCounts[c.username] || 0) + 1
    userTotals[c.username] = (userTotals[c.username] || 0n) + BigInt(c.amount)
    totalWei += BigInt(c.amount)
  }

  const leaderboard = Object.entries(userTotals)
    .map(([username, total]) => ({ username, claims: userCounts[username], totalWei: total.toString(), totalEth: formatEth(total) }))
    .sort((a, b) => BigInt(b.totalWei) > BigInt(a.totalWei) ? 1 : -1)

  writeOutput({
    claims: claims.slice(0, 100), leaderboard,
    stats: { totalClaims: claims.length, uniqueUsers: Object.keys(userCounts).length, totalEth: formatEth(totalWei) }
  })
  console.log(`Stats: ${claims.length} claims, ${Object.keys(userCounts).length} users, ${formatEth(totalWei)} ETH`)
}

function writeOutput(data) {
  require('fs').mkdirSync(require('path').dirname(OUT_FILE), { recursive: true })
  require('fs').writeFileSync(OUT_FILE, JSON.stringify({ ...data, updatedAt: new Date().toISOString() }, null, 2))
  console.log(`Wrote ${OUT_FILE}`)
}

function formatEth(wei) {
  const remainder = wei % BigInt(1e18)
  return (wei / BigInt(1e18)).toString() + '.' + remainder.toString().padStart(18, '0').slice(0, 6)
}

function decodeClaimCalldata(input) {
  const data = input.slice(10)
  const wordToInt = (i) => parseInt(data.slice(i * 64, (i + 1) * 64), 16)
  const usernameOffset = wordToInt(3)
  const usernameLen = parseInt(data.slice(usernameOffset * 2, usernameOffset * 2 + 64), 16)
  const usernameHex = data.slice(usernameOffset * 2 + 64, usernameOffset * 2 + 64 + usernameLen * 2)
  return { username: Buffer.from(usernameHex, 'hex').toString('utf8') }
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)) }

main().catch(e => { console.error(e); process.exit(1) })
