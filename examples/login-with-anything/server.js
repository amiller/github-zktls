import express from 'express'
import Anthropic from '@anthropic-ai/sdk'
import { execSync } from 'child_process'
import fs from 'fs'
import { PROOF_CATALOG, getRandomProofs, getTotalProofCount } from './proofs.js'

const app = express()
app.use(express.json())
app.use(express.static('public'))

const anthropic = process.env.ANTHROPIC_API_KEY ? new Anthropic() : null
const sessions = new Map()  // runId -> { proof, screenshot, messages: [] }
const wall = []  // public message wall
const proofCache = new Map()  // proofId -> cached workflow run URLs
const workflowCache = new Map()  // proofId -> generated workflow YAML

// Example workflows for LLM context
const EXAMPLE_WORKFLOWS = {
  'twitter-followers': `name: Twitter Follower Proof

on:
  workflow_dispatch:
    inputs:
      profile:
        description: 'Twitter/X username to prove (without @)'
        required: true

jobs:
  prove:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Start browser container
        run: |
          cd browser-container
          docker compose up -d --build
          sleep 10
          curl -f http://localhost:3002/health
      - name: Inject session and capture proof
        env:
          SESSION_JSON: \${{ secrets.TWITTER_COM_SESSION }}
        run: |
          mkdir -p proof
          echo "$SESSION_JSON" | curl -X POST http://localhost:3002/session -H "Content-Type: application/json" -d @-
          curl -X POST http://localhost:3002/navigate -H "Content-Type: application/json" -d '{"url":"https://x.com/\${{ inputs.profile }}"}'
          sleep 5
          curl http://localhost:3002/screenshot -o proof/screenshot.png
          cat > proof/certificate.json << EOF
          {
            "type": "twitter-followers",
            "profile": "\${{ inputs.profile }}",
            "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
            "github_run_id": "\${{ github.run_id }}",
            "github_run_url": "\${{ github.server_url }}/\${{ github.repository }}/actions/runs/\${{ github.run_id }}"
          }
          EOF
      - uses: actions/upload-artifact@v4
        with:
          name: twitter-proof
          path: proof/
          retention-days: 90
      - if: always()
        run: cd browser-container && docker compose down`,

  'github-contributions': `name: GitHub Contributions Proof

on:
  workflow_dispatch:
    inputs:
      username:
        description: 'GitHub username'
        required: true

jobs:
  prove:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Start browser container
        run: |
          cd browser-container
          docker compose up -d --build
          sleep 10
          curl -f http://localhost:3002/health
      - name: Inject session and capture proof
        env:
          SESSION_JSON: \${{ secrets.GITHUB_COM_SESSION }}
        run: |
          mkdir -p proof
          echo "$SESSION_JSON" | curl -X POST http://localhost:3002/session -H "Content-Type: application/json" -d @-
          curl -X POST http://localhost:3002/navigate -H "Content-Type: application/json" -d '{"url":"https://github.com/\${{ inputs.username }}"}'
          sleep 5
          curl http://localhost:3002/screenshot -o proof/screenshot.png
          cat > proof/certificate.json << EOF
          {
            "type": "github-contributions",
            "username": "\${{ inputs.username }}",
            "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
            "github_run_id": "\${{ github.run_id }}",
            "github_run_url": "\${{ github.server_url }}/\${{ github.repository }}/actions/runs/\${{ github.run_id }}"
          }
          EOF
      - uses: actions/upload-artifact@v4
        with:
          name: github-proof
          path: proof/
          retention-days: 90
      - if: always()
        run: cd browser-container && docker compose down`
}

// Canonical workflows - used to verify "bring your own repo" proofs
const CANONICAL_WORKFLOWS = new Map()

// Load canonical workflows from .github/workflows on startup
function loadCanonicalWorkflows() {
  try {
    const workflowDir = '../../.github/workflows'
    const files = fs.readdirSync(workflowDir).filter(f => f.endsWith('.yml'))
    for (const file of files) {
      const content = fs.readFileSync(`${workflowDir}/${file}`, 'utf8')
      // Extract proof type from certificate.json "type" field in workflow
      const typeMatch = content.match(/"type":\s*"([^"]+)"/)
      if (typeMatch) CANONICAL_WORKFLOWS.set(typeMatch[1], content)
    }
    console.log(`Loaded ${CANONICAL_WORKFLOWS.size} canonical workflows`)
  } catch (e) {
    console.log('Could not load canonical workflows:', e.message)
  }
}
loadCanonicalWorkflows()

// Verify a GitHub Actions proof and create session
app.post('/api/verify', async (req, res) => {
  const { runUrl } = req.body
  const match = runUrl?.match(/github\.com\/([^/]+)\/([^/]+)\/actions\/runs\/(\d+)/)
  if (!match) return res.status(400).json({ error: 'Invalid run URL' })

  const [, owner, repo, runId] = match
  try {
    // Fetch run metadata including workflow path and commit SHA
    const runJson = execSync(`gh api /repos/${owner}/${repo}/actions/runs/${runId}`, { encoding: 'utf8' })
    const runData = JSON.parse(runJson)
    if (runData.conclusion !== 'success') return res.status(400).json({ error: `Run not successful: ${runData.conclusion}` })

    const { head_sha, path: workflowPath } = runData
    const run = { conclusion: runData.conclusion, name: runData.name, headSha: head_sha, createdAt: runData.created_at }

    // Fetch workflow content at exact commit SHA
    let workflowContent = null, workflowVerified = false, workflowMismatch = null
    try {
      const contentJson = execSync(`gh api /repos/${owner}/${repo}/contents/${workflowPath}?ref=${head_sha}`, { encoding: 'utf8' })
      const contentData = JSON.parse(contentJson)
      workflowContent = Buffer.from(contentData.content, 'base64').toString('utf8')
    } catch (e) {
      console.log('Could not fetch workflow content:', e.message)
    }

    // Download artifacts to temp dir
    const tmpDir = `/tmp/proof-${runId}`
    execSync(`rm -rf ${tmpDir} && mkdir -p ${tmpDir}`)
    execSync(`gh run download ${runId} --repo ${owner}/${repo} --dir ${tmpDir}`, { encoding: 'utf8' })

    // Find and parse certificate
    const certPath = execSync(`find ${tmpDir} -name "certificate.json" | head -1`, { encoding: 'utf8' }).trim()
    if (!certPath) return res.status(400).json({ error: 'No certificate found in artifacts' })
    const cert = JSON.parse(execSync(`cat "${certPath}"`, { encoding: 'utf8' }))

    // Find screenshot if available
    let screenshot = null
    try {
      const screenshotPath = execSync(`find ${tmpDir} -name "screenshot.png" | head -1`, { encoding: 'utf8' }).trim()
      if (screenshotPath) screenshot = fs.readFileSync(screenshotPath).toString('base64')
    } catch {}

    // Verify workflow against canonical if we have one
    const norm = normalizeCert(cert)
    if (workflowContent && CANONICAL_WORKFLOWS.has(norm.type)) {
      const canonical = CANONICAL_WORKFLOWS.get(norm.type)
      // Normalize whitespace for comparison
      const normalizeWs = s => s.replace(/\s+/g, ' ').trim()
      if (normalizeWs(workflowContent) === normalizeWs(canonical)) {
        workflowVerified = true
      } else {
        workflowMismatch = { expected: canonical.slice(0, 200), actual: workflowContent.slice(0, 200) }
      }
    }

    // Create session
    const session = {
      runId, runUrl, run, cert, screenshot, tmpDir,
      workflowContent, workflowVerified, workflowPath, headSha: head_sha,
      messages: [], createdAt: new Date()
    }
    sessions.set(runId, session)

    res.json({
      sessionId: runId,
      proof: { type: norm.type, claim: norm.claim, timestamp: cert.timestamp },
      run: { name: run.name, commit: run.headSha.slice(0, 7) },
      hasScreenshot: !!screenshot,
      workflow: {
        verified: workflowVerified,
        path: workflowPath,
        commitSha: head_sha,
        fromTrustedRepo: owner === 'amiller' && repo === 'github-zktls',
        mismatch: workflowMismatch ? 'Workflow differs from canonical' : null
      }
    })
  } catch (e) {
    res.status(500).json({ error: e.message })
  }
})

// Normalize cert fields (different workflows use different names)
function normalizeCert(cert) {
  return {
    type: cert.type || cert.proof_type,
    username: cert.profile || cert.username,
    followers: cert.followers,
    items: cert.items,
    claim: cert.claim || cert.profile || cert.items?.join(', ') || 'verified',
    ...cert
  }
}

// Generate bespoke content with Claude based on proof
app.post('/api/generate', async (req, res) => {
  if (!anthropic) return res.status(503).json({ error: 'ANTHROPIC_API_KEY not set' })
  const { sessionId, prompt } = req.body
  const session = sessions.get(sessionId)
  if (!session) return res.status(401).json({ error: 'Invalid session' })

  const cert = normalizeCert(session.cert)
  const isCart = cert.type?.includes('amazon') || cert.type?.includes('cart')

  // For cart proofs with screenshot, use vision to read items
  if (isCart && session.screenshot) {
    try {
      const msg = await anthropic.messages.create({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 1024,
        system: `You help people with verified shopping carts. This person has cryptographically proven their Amazon cart contents via GitHub Actions attestation. Look at their cart screenshot and generate creative content based on what you see.`,
        messages: [{
          role: 'user',
          content: [
            { type: 'image', source: { type: 'base64', media_type: 'image/png', data: session.screenshot } },
            { type: 'text', text: prompt || 'Look at my cart and create a fun recipe or meal plan using these ingredients!' }
          ]
        }]
      })
      return res.json({ content: msg.content[0].text, proofType: cert.type })
    } catch (e) {
      return res.status(500).json({ error: e.message })
    }
  }

  // Text-only generation for other proof types
  let systemPrompt = `You are helping someone who has proven something about themselves via a verifiable GitHub Actions attestation.`
  if (cert.type?.includes('twitter')) {
    systemPrompt += `\n\nThey have proven they are Twitter user @${cert.username}. Generate personalized content based on their verified identity.`
  } else {
    systemPrompt += `\n\nTheir verified claim: ${cert.claim}`
  }

  try {
    const msg = await anthropic.messages.create({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 1024,
      system: systemPrompt,
      messages: [{ role: 'user', content: prompt || 'Generate something for me!' }]
    })
    res.json({ content: msg.content[0].text, proofType: cert.type })
  } catch (e) {
    res.status(500).json({ error: e.message })
  }
})

// Post to public wall (requires valid session)
app.post('/api/wall', async (req, res) => {
  const { sessionId, message } = req.body
  const session = sessions.get(sessionId)
  if (!session) return res.status(401).json({ error: 'Invalid session' })

  const cert = normalizeCert(session.cert)
  const post = {
    id: Date.now(),
    message,
    proofType: cert.type,
    identity: cert.username || cert.claim,
    runUrl: session.runUrl,
    timestamp: new Date()
  }
  wall.push(post)
  res.json({ post })
})

// Get wall posts
app.get('/api/wall', (req, res) => {
  res.json({ posts: wall.slice(-50).reverse() })
})

// Get session info
app.get('/api/session/:id', (req, res) => {
  const session = sessions.get(req.params.id)
  if (!session) return res.status(404).json({ error: 'Session not found' })
  const cert = normalizeCert(session.cert)
  res.json({ proof: { type: cert.type, claim: cert.claim }, hasScreenshot: !!session.screenshot, createdAt: session.createdAt })
})

// Get session screenshot
app.get('/api/session/:id/screenshot', (req, res) => {
  const session = sessions.get(req.params.id)
  if (!session?.screenshot) return res.status(404).json({ error: 'No screenshot' })
  res.set('Content-Type', 'image/png')
  res.send(Buffer.from(session.screenshot, 'base64'))
})

// Get session workflow (for inspection/audit)
app.get('/api/session/:id/workflow', (req, res) => {
  const session = sessions.get(req.params.id)
  if (!session) return res.status(404).json({ error: 'Session not found' })
  res.json({
    path: session.workflowPath,
    commitSha: session.headSha,
    verified: session.workflowVerified,
    content: session.workflowContent,
    canonical: CANONICAL_WORKFLOWS.get(normalizeCert(session.cert).type) || null
  })
})

// Get random proof options
app.get('/api/proofs/random', (req, res) => {
  const n = parseInt(req.query.n) || 5
  res.json({ proofs: getRandomProofs(n), total: getTotalProofCount() })
})

// Get all proof options (grouped by site)
app.get('/api/proofs/all', (req, res) => {
  res.json({ catalog: PROOF_CATALOG, total: getTotalProofCount() })
})

// Get cached proof runs
app.get('/api/proofs/cache', (req, res) => {
  res.json({ cache: Object.fromEntries(proofCache) })
})

// Cache a proof run
app.post('/api/proofs/cache', (req, res) => {
  const { proofId, runUrl } = req.body
  if (!proofId || !runUrl) return res.status(400).json({ error: 'proofId and runUrl required' })
  proofCache.set(proofId, { runUrl, cachedAt: new Date() })
  res.json({ ok: true })
})

// Generate workflow for a proof type (on-demand, cached)
app.post('/api/workflow/generate', async (req, res) => {
  if (!anthropic) return res.status(503).json({ error: 'ANTHROPIC_API_KEY not set' })

  const { proofId } = req.body
  if (!proofId) return res.status(400).json({ error: 'proofId required' })

  // Check cache first
  if (workflowCache.has(proofId)) {
    return res.json({ workflow: workflowCache.get(proofId), cached: true })
  }

  // Find proof in catalog
  const allProofs = PROOF_CATALOG.flatMap(site =>
    site.proofs.map(p => ({ ...p, site: site.site, siteName: site.name }))
  )
  const proof = allProofs.find(p => p.id === proofId)
  if (!proof) return res.status(404).json({ error: 'Proof type not found' })

  const secretName = proof.site.replace(/\./g, '_').toUpperCase() + '_SESSION'

  try {
    const msg = await anthropic.messages.create({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 2048,
      system: `You generate GitHub Actions workflow YAML files for capturing authenticated browser proofs.

Follow this exact pattern - output ONLY the YAML, no explanation:

1. Name format: "{Site} {ProofType} Proof"
2. workflow_dispatch with appropriate inputs (username, etc.)
3. Steps: checkout, start browser container, inject session + navigate + screenshot, upload artifacts, cleanup
4. Secret name: ${secretName}
5. Certificate type: ${proofId}

Examples:
---
${EXAMPLE_WORKFLOWS['twitter-followers']}
---
${EXAMPLE_WORKFLOWS['github-contributions']}
---`,
      messages: [{
        role: 'user',
        content: `Generate a workflow for: ${proof.siteName} - ${proof.name}
Proof ID: ${proofId}
Description: ${proof.desc}
Target URL: ${proof.url}
Secret: ${secretName}

Output ONLY the YAML.`
      }]
    })

    const workflow = msg.content[0].text.trim()
    workflowCache.set(proofId, workflow)
    res.json({ workflow, cached: false })
  } catch (e) {
    res.status(500).json({ error: e.message })
  }
})

// Get cached workflow
app.get('/api/workflow/:proofId', (req, res) => {
  const workflow = workflowCache.get(req.params.proofId)
  if (!workflow) return res.status(404).json({ error: 'Workflow not generated yet' })
  res.json({ workflow })
})

const PORT = process.env.PORT || 3003
app.listen(PORT, () => console.log(`Relying party server: http://localhost:${PORT}`))
