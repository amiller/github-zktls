# Oracle Variants: First vs Any Comment

## Two Versions Available

### 1. `check-forum.js` - First Comment Only (Original)
**Checks:** Only the first comment (post #2 in Discourse)
**Use case:** Race condition bets

```bash
node check-forum.js 27119 diamond
# ✅ FOUND: "diamond" appears in first comment!
```

**Prediction market examples:**
- "Will the first comment mention 'radicle'?"
- "Will Alice be the first to comment?"
- "Will someone disagree in the first response?"

**Why this is useful:**
- **Deterministic** - Result never changes once first comment posted
- **Race dynamics** - Creates urgency ("be first!")
- **Simple settlement** - No ambiguity
- **Your original challenge** - "first comment" condition

---

### 2. `check-forum-any.js` - Any Comment (Extended)
**Checks:** All comments up to max limit
**Use case:** General occurrence bets

```bash
node check-forum-any.js 27119 diamond 20
# ✅ FOUND in 17 comment(s)!
# First match: Comment #2 by vitali_grabovski
```

**Prediction market examples:**
- "Will anyone mention 'radicle' in this thread?"
- "Will 'scaling' be discussed within 50 comments?"
- "Will the author respond within 24 hours?"

**Returns:**
- Total matches
- First match details
- All matches (position, username, timestamp, excerpt)

**Why this is useful:**
- **Broader conditions** - Not just first comment
- **More markets** - "Will it ever be mentioned?"
- **Still deterministic** - Check up to N comments or deadline

---

## Design Trade-offs

| Aspect | First Comment | Any Comment |
|--------|--------------|-------------|
| **Finality** | Instant (once posted) | Requires deadline/limit |
| **Simplicity** | Very simple | Slightly complex |
| **Race dynamics** | Yes ("be first!") | No |
| **Gas cost** | Lower (simpler result) | Higher (more data) |
| **Market types** | Time-based races | General occurrence |

## Which Should You Use?

**Use `check-forum.js` (first comment) when:**
- You want a race condition
- Instant finality is important
- Betting closes when first comment appears
- Example: "Will first commenter agree or disagree?"

**Use `check-forum-any.js` (any comment) when:**
- You want "will it ever happen?" style bets
- Deadline-based settlement
- Need to track multiple occurrences
- Example: "Will 'scaling' be mentioned within 24 hours?"

## Combining Both

You can create markets with either oracle:

```solidity
// Market 1: First comment race
createMarket(
  "First comment mentions 'radicle'",
  "amiller/oracle",
  commitSHA,
  deadline,
  ORACLE_TYPE_FIRST  // Use check-forum.js
);

// Market 2: Any comment within timeframe
createMarket(
  "'radicle' mentioned within 24 hours",
  "amiller/oracle",
  commitSHA,
  deadline,
  ORACLE_TYPE_ANY  // Use check-forum-any.js
);
```

## Test Results

**Positive test (check-forum.js):**
```bash
$ node check-forum.js 27119 diamond
✅ FOUND: "diamond" appears in first comment!
Topic: ERC-8109: Diamonds, Simplified
First comment by: vitali_grabovski
```

**Negative test (check-forum.js):**
```bash
$ node check-forum.js 27680 radicle
❌ NOT FOUND: "radicle" does not appear in first comment
Topic: PQ on EVM: Stop Mixing Native, ZK and Protocol Enforcement
```

**Extended test (check-forum-any.js):**
```bash
$ node check-forum-any.js 27119 diamond 20
✅ FOUND in 17 comment(s)!
First match: Comment #2 by vitali_grabovski
Also found in 16 other comment(s)
```

**Extended negative (check-forum-any.js):**
```bash
$ node check-forum-any.js 27119 radicle 50
❌ NOT FOUND in any of the 72 comments
```

---

## Workflow Configuration

You can configure which oracle to use via repository variables:

```yaml
# .github/workflows/oracle-check.yml
- name: Run oracle check
  run: |
    if [ "${{ vars.ORACLE_TYPE }}" = "any" ]; then
      node check-forum-any.js "$TOPIC_ID" "$KEYWORD" "${{ vars.MAX_COMMENTS || 100 }}"
    else
      node check-forum.js "$TOPIC_ID" "$KEYWORD"
    fi
```

**Repository variables:**
- `ORACLE_TYPE` = "first" or "any"
- `MAX_COMMENTS` = Max comments to check (for "any" type)
- `DEFAULT_TOPIC_ID` = Topic to monitor
- `DEFAULT_KEYWORD` = Keyword to search

---

**Both oracles are production-ready and tested!** 🦞
