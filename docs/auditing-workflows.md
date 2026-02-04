# Auditing Workflows

When a prover submits a ZK proof, you receive:
- `artifactHash` - SHA-256 of the artifact the workflow produced
- `repoHash` - SHA-256 of `"owner/repo"` (the prover can optionally disclose the repo)
- `commitSha` - Git commit that triggered the workflow

This guide helps you evaluate whether to trust the proof.

## Do You Need to Audit?

Not always. Consider your trust model:

| Scenario | Need to Audit? |
|----------|----------------|
| You trust the prover personally | No |
| Prover uses a well-known template | Maybe - verify it matches |
| Prover claims custom workflow | Yes |
| High-value transaction | Yes |

## How to Audit

### 1. Get the Repo Name

The prover must disclose their repo name. Verify it:

```bash
# Compute hash of claimed repo
echo -n "owner/repo" | sha256sum
# Compare to repoHash from proof
```

### 2. View the Workflow at the Proven Commit

```
https://github.com/{owner}/{repo}/blob/{commitSha}/.github/workflows/
```

**Important:** Always use the `commitSha` from the proof. Don't look at `main` or any other branch—the code might have changed.

### 3. What to Check in the Workflow

#### Artifact Source
Where does the `artifact` that gets hashed come from?

```yaml
# GOOD: Artifact is deterministic output of the workflow
- run: echo "$TWEET_CONTENT" > artifact.txt
- uses: actions/attest-build-provenance@v2
  with:
    subject-path: artifact.txt

# BAD: Artifact comes from external source that prover controls
- run: curl ${{ secrets.MY_SERVER }}/artifact > artifact.txt
```

#### Secret Usage
What secrets could influence the output?

```yaml
# ACCEPTABLE: Secrets used for authentication only
env:
  TWITTER_TOKEN: ${{ secrets.TWITTER_TOKEN }}

# SUSPICIOUS: Secrets that could change workflow behavior
run: |
  if [ "${{ secrets.MAGIC_FLAG }}" == "true" ]; then
    echo "fake data" > artifact.txt
  fi
```

#### External Dependencies
What could change between runs?

```yaml
# RISKY: Unpinned actions
- uses: actions/checkout@main  # Could change!

# BETTER: Pinned to commit
- uses: actions/checkout@8ade135  # Immutable
```

## Red Flags

🚩 **Artifact from secrets** - The artifact content depends on a secret value

🚩 **External data fetched at runtime** - Curl/wget to prover-controlled servers

🚩 **Unpinned dependencies** - Actions without version pins

🚩 **Complex logic** - Hard-to-follow bash scripts

🚩 **Recent repo creation** - Repo created right before the proof

## Green Flags

✅ **Simple, readable workflow** - Easy to understand what it does

✅ **Artifact is workflow output** - Not fetched from elsewhere

✅ **Pinned dependencies** - All actions use commit hashes

✅ **Established repo** - Has history, not created for this proof

## Template Verification

If the prover claims to use a standard template:

1. Diff their workflow against the template
2. Check for additions/modifications
3. Verify any changes are benign

```bash
# Example: compare to tweet-capture template
diff prover-workflow.yml templates/tweet-capture.yml
```

## When in Doubt

Ask the prover to explain:
- What does the workflow do?
- What's in the artifact?
- Why any custom modifications?

If you can't verify the workflow satisfies your requirements, don't accept the proof.
