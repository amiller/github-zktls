#!/usr/bin/env node
// Fetches faucet claims from Basescan and generates leaderboard JSON

const FAUCET = process.env.FAUCET_ADDRESS || '0x72cd70d28284dD215257f73e1C5aD8e28847215B'
const CHAIN_ID = process.env.CHAIN_ID || '84532' // Base Sepolia
const API_KEY = process.env.BASESCAN_API_KEY
const CLAIMED_TOPIC = '0x9d2f14df77ba038ff6f9ba99bbdcfbc30f1650b9574e3b7bbae993df15a92f30'
const OUT_FILE = 'examples/leaderboard/claims.json'

// Etherscan V2 API base
const API_BASE = `https://api.etherscan.io/v2/api?chainid=${CHAIN_ID}`

async function main() {
  if (!API_KEY) throw new Error('BASESCAN_API_KEY required')

  // Fetch Claimed event logs
  const logsUrl = `${API_BASE}&module=logs&action=getLogs&address=${FAUCET}&topic0=${CLAIMED_TOPIC}&fromBlock=0&toBlock=latest&apikey=${API_KEY}`
  const logsRes = await fetch(logsUrl)
  const logsData = await logsRes.json()

  if (logsData.status !== '1' || !logsData.result?.length) {
    console.log('No claims found or API error:', logsData.message)
    require('fs').writeFileSync(OUT_FILE, JSON.stringify({
      claims: [], leaderboard: [],
      stats: { totalClaims: 0, uniqueUsers: 0, totalEth: '0.000000' },
      updatedAt: new Date().toISOString()
    }, null, 2))
    return
  }

  console.log(`Found ${logsData.result.length} Claimed events`)

  // For each log, fetch the tx to decode username from calldata
  const txCache = {}
  const claims = []

  for (const log of logsData.result) {
    // Decode log: topic1=recipient (indexed), topic2=keccak(username) (indexed), data=amount
    const recipient = '0x' + log.topics[1].slice(26)
    const amount = BigInt(log.data)

    // Get tx to decode username
    let username = 'unknown'
    if (!txCache[log.transactionHash]) {
      const txUrl = `${API_BASE}&module=proxy&action=eth_getTransactionByHash&txhash=${log.transactionHash}&apikey=${API_KEY}`
      const txRes = await fetch(txUrl)
      const txData = await txRes.json()
      txCache[log.transactionHash] = txData.result
      await sleep(200) // Rate limit
    }

    const tx = txCache[log.transactionHash]
    if (tx?.input) {
      try {
        const decoded = decodeClaimCalldata(tx.input)
        username = decoded.username
      } catch (e) {
        console.error(`Failed to decode tx ${log.transactionHash}:`, e.message)
      }
    }

    claims.push({
      username,
      recipient,
      amount: amount.toString(),
      amountEth: formatEth(amount),
      txHash: log.transactionHash,
      timestamp: new Date(parseInt(log.timeStamp, 16) * 1000).toISOString(),
      block: parseInt(log.blockNumber, 16).toString()
    })
  }

  // Sort by timestamp descending
  claims.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp))

  // Calculate stats
  const userCounts = {}
  const userTotals = {}
  let totalWei = 0n
  for (const c of claims) {
    userCounts[c.username] = (userCounts[c.username] || 0) + 1
    userTotals[c.username] = (userTotals[c.username] || 0n) + BigInt(c.amount)
    totalWei += BigInt(c.amount)
  }

  // Build leaderboard sorted by total claimed
  const leaderboard = Object.entries(userTotals)
    .map(([username, total]) => ({
      username,
      claims: userCounts[username],
      totalWei: total.toString(),
      totalEth: formatEth(total)
    }))
    .sort((a, b) => BigInt(b.totalWei) > BigInt(a.totalWei) ? 1 : -1)

  const output = {
    claims: claims.slice(0, 100),
    leaderboard,
    stats: {
      totalClaims: claims.length,
      uniqueUsers: Object.keys(userCounts).length,
      totalEth: formatEth(totalWei)
    },
    updatedAt: new Date().toISOString()
  }

  require('fs').writeFileSync(OUT_FILE, JSON.stringify(output, null, 2))
  console.log(`Wrote ${OUT_FILE}`)
  console.log(`Stats: ${output.stats.totalClaims} claims, ${output.stats.uniqueUsers} users, ${output.stats.totalEth} ETH`)
}

function formatEth(wei) {
  const eth = wei / BigInt(1e18)
  const remainder = wei % BigInt(1e18)
  return eth.toString() + '.' + remainder.toString().padStart(18, '0').slice(0, 6)
}

function decodeClaimCalldata(input) {
  // claim(bytes proof, bytes32[] inputs, bytes certificate, string username, address recipient)
  const data = input.slice(10) // Skip selector
  const wordToInt = (i) => parseInt(data.slice(i * 64, (i + 1) * 64), 16)

  // Word 3 = offset to username
  const usernameOffset = wordToInt(3)
  const usernameLen = parseInt(data.slice(usernameOffset * 2, usernameOffset * 2 + 64), 16)
  const usernameHex = data.slice(usernameOffset * 2 + 64, usernameOffset * 2 + 64 + usernameLen * 2)
  const username = Buffer.from(usernameHex, 'hex').toString('utf8')
  return { username }
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)) }

main().catch(e => { console.error(e); process.exit(1) })
