# Settlement Design: Manual Trigger vs Automatic

## Design Choice: Manual Trigger Only

**The workflow does NOT run automatically.** Settlers must manually trigger it.

### Why Manual > Automatic

#### ❌ **Automatic polling (every 15 min) is wasteful:**
- Burns GitHub Actions minutes
- Checks even when nobody's betting yet
- Creates unnecessary attestations
- Costs the repo owner money (if over free tier)

#### ✅ **Manual trigger (on-demand) is better:**
- Only runs when someone needs to settle
- No wasted compute
- Settler pays the "cost" (their time to click button)
- More flexible (can trigger immediately or wait)

### How Settlement Works

```
1. Market created, people bet
2. Event happens (first comment posted)
3. Settler notices and wants to claim/settle
4. Settler triggers workflow manually:
   - Go to GitHub Actions tab
   - Click "Run workflow"
   - Enter topic_id and keyword
   - Click "Run workflow"
5. Workflow produces attested result
6. Settler uses attestation to settle contract
7. Winners claim their payouts
```

### Who Can Trigger?

**Anyone!** The workflow is public.

- Bettors can trigger to settle
- Third parties can trigger (maybe for a fee)
- Automated bots can trigger via GitHub API

### Incentives

**Who triggers settlement?**

1. **Winners** - Want to claim their payout
2. **Arbitrageurs** - Trigger + settle for small fee
3. **Bots** - Automated settlement services

**Example:**
```
Alice bet YES, Bob bet NO
First comment appears with keyword
Alice (winner) checks forum → sees keyword
Alice triggers workflow → gets attestation
Alice settles contract → claims payout
Bob accepts loss
```

### Manual Trigger via GitHub UI

1. Go to your fork: `github.com/username/prediction-market-oracle`
2. Click "Actions" tab
3. Click "Prediction Market Oracle" workflow
4. Click "Run workflow" dropdown
5. Enter:
   - `topic_id`: 27680
   - `keyword`: radicle
   - `oracle_type`: first (or any)
   - `max_comments`: 100
6. Click "Run workflow" button
7. Wait ~30 seconds
8. Download attestation from artifacts

### Automated Trigger via GitHub API

You can also trigger programmatically:

```bash
# Using GitHub CLI
gh workflow run oracle-check.yml \
  --repo username/prediction-market-oracle \
  --ref main \
  -f topic_id=27680 \
  -f keyword=radicle \
  -f oracle_type=first

# Get the run ID
RUN_ID=$(gh run list --workflow=oracle-check.yml --json databaseId --jq '.[0].databaseId')

# Wait for completion
gh run watch $RUN_ID

# Download attestation
gh run download $RUN_ID
```

### Settlement Bot Example

A simple bot that auto-settles:

```javascript
// settlement-bot.js
const { Octokit } = require("@octokit/rest");

async function settlePredictionMarket(topicId, keyword) {
  const octokit = new Octokit({ auth: process.env.GITHUB_TOKEN });
  
  // 1. Trigger workflow
  const workflow = await octokit.actions.createWorkflowDispatch({
    owner: "username",
    repo: "prediction-market-oracle",
    workflow_id: "oracle-check.yml",
    ref: "main",
    inputs: {
      topic_id: topicId,
      keyword: keyword,
      oracle_type: "first"
    }
  });
  
  // 2. Wait for completion
  await sleep(60000); // 1 min
  
  // 3. Get result
  const runs = await octokit.actions.listWorkflowRuns({
    owner: "username",
    repo: "prediction-market-oracle",
    workflow_id: "oracle-check.yml",
    per_page: 1
  });
  
  const runId = runs.data.workflow_runs[0].id;
  
  // 4. Download attestation
  const artifacts = await octokit.actions.listWorkflowRunArtifacts({
    owner: "username",
    repo: "prediction-market-oracle",
    run_id: runId
  });
  
  // 5. Settle contract with attestation
  // ... contract.settle(marketId, result, attestation)
}
```

### Gas Costs

**Manual trigger = gas efficient:**
- Only one attestation per market (when settled)
- No wasted attestations from polling
- Settler decides when to pay gas

**Automatic polling = gas wasteful:**
- Attestation every 15 min = 96 per day
- Most are useless (event hasn't happened yet)
- Free tier: 2000 min/month = ~20 days before paying

### Multi-Market Support

With manual trigger, one oracle repo can serve many markets:

```
Market 1: "radicle" in topic 27680
Market 2: "diamond" in topic 27119
Market 3: "scaling" in topic 30000

All use same oracle repo, triggered on-demand when needed
No automatic polling, no wasted resources
```

### Emergency: What if Oracle Goes Down?

**Fallback options:**

1. **Run oracle locally:**
   ```bash
   git clone https://github.com/username/prediction-market-oracle
   node check-forum.js 27680 radicle
   # You get the same result (code is deterministic)
   ```

2. **Fork and trigger:**
   - Fork the repo
   - Trigger workflow on your fork
   - Same commit SHA = same trust

3. **Contract timeout:**
   - Market has deadline
   - If oracle never settles, refund bets after timeout

### Comparison

| Aspect | Automatic (cron) | Manual (on-demand) |
|--------|-----------------|-------------------|
| **Efficiency** | ❌ Wasteful | ✅ Optimal |
| **Cost** | ❌ High (96 runs/day) | ✅ Low (1 run/market) |
| **Control** | ❌ Fixed schedule | ✅ Settler decides |
| **Latency** | ✅ Up to 15 min | ⚠️ Depends on settler |
| **Incentives** | ❌ Free rider problem | ✅ Clear (winner settles) |

### Recommendation

✅ **Use manual trigger (current design)**

Only use automatic polling if:
- You're running a settlement bot service
- You charge a fee for auto-settlement
- The market has a very tight deadline (minutes)

For most prediction markets, **manual trigger is better.**

---

**Current workflow:** Manual trigger only (no cron schedule)
