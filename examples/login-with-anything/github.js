import { Octokit } from '@octokit/rest'
import AdmZip from 'adm-zip'
import fs from 'fs'
import path from 'path'

const octokit = new Octokit({ auth: process.env.GITHUB_TOKEN })

export async function getWorkflowRun(owner, repo, runId) {
  const { data } = await octokit.actions.getWorkflowRun({ owner, repo, run_id: runId })
  return data
}

export async function getWorkflowContent(owner, repo, workflowPath, ref) {
  const { data } = await octokit.repos.getContent({ owner, repo, path: workflowPath, ref })
  return Buffer.from(data.content, 'base64').toString('utf8')
}

export async function downloadArtifacts(owner, repo, runId, destDir) {
  // List artifacts for this run
  const { data: { artifacts } } = await octokit.actions.listWorkflowRunArtifacts({ owner, repo, run_id: runId })
  if (!artifacts.length) throw new Error('No artifacts found')

  fs.mkdirSync(destDir, { recursive: true })

  for (const artifact of artifacts) {
    const { data } = await octokit.actions.downloadArtifact({
      owner, repo, artifact_id: artifact.id, archive_format: 'zip'
    })
    const zip = new AdmZip(Buffer.from(data))
    const artifactDir = path.join(destDir, artifact.name)
    fs.mkdirSync(artifactDir, { recursive: true })
    zip.extractAllTo(artifactDir, true)
  }
}

export async function verifyProofRun(runUrl) {
  const match = runUrl?.match(/github\.com\/([^/]+)\/([^/]+)\/actions\/runs\/(\d+)/)
  if (!match) throw new Error('Invalid run URL format')
  const [, owner, repo, runId] = match

  const runData = await getWorkflowRun(owner, repo, runId)
  if (runData.conclusion !== 'success') throw new Error(`Run not successful: ${runData.conclusion}`)

  return { owner, repo, runId, runData }
}
