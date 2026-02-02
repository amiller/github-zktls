# Proof Workflow Guidelines

Generate GitHub Actions workflows that capture authenticated screenshots as proofs.

## Structure

Every proof workflow follows this pattern:

```yaml
name: {Site} {ProofType} Proof

on:
  workflow_dispatch:
    inputs:
      # Site-specific inputs (username, etc.)

jobs:
  prove:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Start browser container
      - name: Inject session and capture proof
      - name: Upload proof artifacts
      - name: Cleanup
```

## Key Components

### 1. Workflow Inputs
Define inputs the user needs to provide (usernames, profile IDs, etc.):
```yaml
inputs:
  username:
    description: 'Twitter username (without @)'
    required: true
```

### 2. Session Secret
Each site needs a secret named `{SITE}_SESSION` containing cookies JSON:
- `TWITTER_COM_SESSION` for twitter.com
- `GITHUB_COM_SESSION` for github.com
- `UBER_COM_SESSION` for uber.com

### 3. Browser Container
Start the Neko-based browser container:
```yaml
- name: Start browser container
  run: |
    cd browser-container
    docker compose up -d --build
    sleep 10
    curl -f http://localhost:3002/health
```

### 4. Capture Proof
Inject cookies, navigate, screenshot:
```yaml
- name: Inject session and capture proof
  env:
    SESSION_JSON: ${{ secrets.SITE_SESSION }}
  run: |
    mkdir -p proof

    # Inject session
    echo "$SESSION_JSON" | curl -X POST http://localhost:3002/session \
      -H "Content-Type: application/json" -d @-

    # Navigate to proof URL
    curl -X POST http://localhost:3002/navigate \
      -H "Content-Type: application/json" \
      -d '{"url":"https://site.com/path"}'

    sleep 5  # Wait for page load

    # Capture screenshot
    curl http://localhost:3002/screenshot -o proof/screenshot.png

    # Create certificate
    cat > proof/certificate.json << EOF
    {
      "type": "proof-type-id",
      "claim": "what this proves",
      "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
      "github_run_id": "${{ github.run_id }}",
      "github_run_url": "${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"
    }
    EOF
```

### 5. Upload Artifacts
```yaml
- name: Upload proof artifacts
  uses: actions/upload-artifact@v4
  with:
    name: {site}-proof
    path: proof/
    retention-days: 90
```

### 6. Cleanup
```yaml
- name: Cleanup
  if: always()
  run: cd browser-container && docker compose down
```

## Certificate Fields

Required fields in `certificate.json`:
- `type`: Proof type ID (e.g., "twitter-followers", "uber-rating")
- `timestamp`: ISO 8601 timestamp
- `github_run_id`: For verification
- `github_run_url`: Link to the run

Optional fields based on proof type:
- `username`, `profile`: For identity proofs
- `claim`: Human-readable description of what's proven

## Examples

See these workflows as reference:
- `twitter-proof.yml` - Twitter follower count
- `github-contributions.yml` - GitHub contribution graph

## URL Patterns by Site

| Site | Proof | URL Pattern |
|------|-------|-------------|
| twitter.com | followers | `https://x.com/{username}` |
| github.com | contributions | `https://github.com/{username}` |
| uber.com | rating | `https://riders.uber.com/profile` |
| amazon.com | cart | `https://www.amazon.com/gp/cart/view.html` |
| spotify.com | playlists | `https://open.spotify.com/collection/playlists` |
| linkedin.com | profile | `https://www.linkedin.com/in/{username}` |
