// AI Judge Service for Agent Escrow
// Listens for claims, evaluates tweets against prompts, submits judgments

import Anthropic from '@anthropic-ai/sdk'
import { ethers } from 'ethers'
import express from 'express'

const ESCROW_ABI = [
  'event ClaimSubmitted(uint256 indexed claimId, uint256 indexed bountyId, bytes32 tweetHash, bytes32 authorHash, address recipient)',
  'function judgeClaim(uint256 claimId, bool approved) external',
  'function getBounty(uint256 bountyId) view returns (tuple(address creator, uint256 amount, bytes32 promptHash, string promptUri, address judge, uint256 deadline, bool claimed))',
  'function getClaim(uint256 claimId) view returns (tuple(uint256 bountyId, bytes32 tweetHash, bytes32 authorHash, address recipient, bool approved, bool judged))'
]

const config = {
  rpcUrl: process.env.RPC_URL || 'https://sepolia.base.org',
  escrowAddress: process.env.ESCROW_ADDRESS,
  judgePrivateKey: process.env.JUDGE_PRIVATE_KEY,
  port: process.env.PORT || 3003
}

const anthropic = new Anthropic()

async function evaluateClaim(prompt, tweetText) {
  const response = await anthropic.messages.create({
    model: 'claude-sonnet-4-20250514',
    max_tokens: 100,
    messages: [{
      role: 'user',
      content: `You are a judge for a bounty marketplace. A buyer posted this prompt:

"${prompt}"

A seller submitted this tweet as their response:

"${tweetText}"

Does this tweet adequately satisfy the prompt? Consider:
- Does it address the topic requested?
- Is it a genuine attempt (not spam or off-topic)?

Answer with just "yes" or "no" followed by a brief reason.`
    }]
  })

  const answer = response.content[0].text.toLowerCase()
  return {
    approved: answer.startsWith('yes'),
    reason: response.content[0].text
  }
}

async function fetchFromIpfs(uri) {
  const cid = uri.replace('ipfs://', '')
  const response = await fetch(`https://ipfs.io/ipfs/${cid}`)
  return response.text()
}

async function main() {
  if (!config.escrowAddress) throw new Error('ESCROW_ADDRESS required')
  if (!config.judgePrivateKey) throw new Error('JUDGE_PRIVATE_KEY required')

  const provider = new ethers.JsonRpcProvider(config.rpcUrl)
  const wallet = new ethers.Wallet(config.judgePrivateKey, provider)
  const escrow = new ethers.Contract(config.escrowAddress, ESCROW_ABI, wallet)

  console.log(`Judge address: ${wallet.address}`)
  console.log(`Escrow contract: ${config.escrowAddress}`)

  // Express server for manual submissions and health checks
  const app = express()
  app.use(express.json())

  app.get('/health', (req, res) => {
    res.json({ status: 'ok', judge: wallet.address })
  })

  // Manual judgment endpoint (for testing)
  app.post('/judge', async (req, res) => {
    const { claimId, tweetText } = req.body

    try {
      const claim = await escrow.getClaim(claimId)
      if (claim.judged) {
        return res.status(400).json({ error: 'Already judged' })
      }

      const bounty = await escrow.getBounty(claim.bountyId)
      if (bounty.judge !== wallet.address) {
        return res.status(403).json({ error: 'Not authorized judge' })
      }

      const prompt = await fetchFromIpfs(bounty.promptUri)
      const evaluation = await evaluateClaim(prompt, tweetText)

      console.log(`Claim ${claimId}: ${evaluation.approved ? 'APPROVED' : 'REJECTED'}`)
      console.log(`Reason: ${evaluation.reason}`)

      const tx = await escrow.judgeClaim(claimId, evaluation.approved)
      await tx.wait()

      res.json({
        claimId,
        approved: evaluation.approved,
        reason: evaluation.reason,
        txHash: tx.hash
      })
    } catch (e) {
      console.error('Judge error:', e)
      res.status(500).json({ error: e.message })
    }
  })

  // Listen for ClaimSubmitted events
  escrow.on('ClaimSubmitted', async (claimId, bountyId, tweetHash, authorHash, recipient, event) => {
    console.log(`\nNew claim ${claimId} for bounty ${bountyId}`)

    try {
      const bounty = await escrow.getBounty(bountyId)

      // Only process if we're the judge
      if (bounty.judge !== wallet.address) {
        console.log('Not our bounty to judge')
        return
      }

      // Fetch prompt from IPFS
      const prompt = await fetchFromIpfs(bounty.promptUri)
      console.log(`Prompt: ${prompt}`)

      // For now, we need the tweet text to be submitted via the /judge endpoint
      // In production, we'd fetch it from the attestation bundle or on-chain data
      console.log('Waiting for tweet text submission via /judge endpoint...')

    } catch (e) {
      console.error('Error processing claim:', e)
    }
  })

  app.listen(config.port, () => {
    console.log(`Judge service listening on port ${config.port}`)
  })
}

main().catch(console.error)
