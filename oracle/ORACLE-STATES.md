# Oracle States: Three-Valued Logic

## Critical Design: Settleable vs Not Settleable

The oracle returns **three distinct states**, not just true/false:

### 1. ✅ FOUND (settleable: true, found: true)
**Meaning:** First comment exists AND contains the keyword

**Example:**
```json
{
  "result": "FOUND",
  "found": true,
  "settleable": true,
  "first_comment": {
    "id": 65572,
    "username": "vitali_grabovski",
    "created_at": "2025-12-12T14:26:22.217Z"
  }
}
```

**Action:** Can settle market → YES wins

---

### 2. ❌ NOT_FOUND (settleable: true, found: false)
**Meaning:** First comment exists BUT does NOT contain the keyword

**Example:**
```json
{
  "result": "NOT_FOUND",
  "found": false,
  "settleable": true,
  "first_comment": {
    "id": 67036,
    "username": "rdubois-crypto",
    "created_at": "2026-02-08T09:18:15.268Z"
  }
}
```

**Action:** Can settle market → NO wins

---

### 3. ⏳ NO_COMMENTS (settleable: false, found: null)
**Meaning:** First comment DOES NOT EXIST YET

**Example:**
```json
{
  "result": "NO_COMMENTS",
  "found": null,
  "settleable": false,
  "topic_id": "27685",
  "message": "First comment has not been posted yet. Cannot settle market."
}
```

**Action:** CANNOT settle market yet → Wait for first comment

---

## Why This Matters

**Without three states, you could prematurely settle:**

❌ **Bad (two states):**
```
State 1: FOUND (true)
State 2: NOT_FOUND (false) ← Ambiguous! Is comment missing or keyword missing?
```

If you settle with "NOT_FOUND" when no comment exists yet:
- Market settles as NO wins
- Then first comment appears with keyword → too late!
- Wrong outcome, bettors lose money incorrectly

✅ **Good (three states):**
```
State 1: FOUND (true, settleable)
State 2: NOT_FOUND (false, settleable)
State 3: NO_COMMENTS (null, NOT settleable) ← Clear: cannot settle yet!
```

**Smart contract must check `settleable == true` before accepting settlement.**

---

## Testing All Three States

```bash
# State 1: FOUND
node check-forum.js 27119 diamond
# ✅ FOUND: "diamond" appears in first comment!
# settleable: true, found: true

# State 2: NOT_FOUND
node check-forum.js 27119 radicle
# ❌ NOT FOUND: "radicle" does not appear in first comment
# settleable: true, found: false

# State 3: NO_COMMENTS
node check-forum.js 27685 anything
# ⏳ NO COMMENTS YET (cannot settle)
# settleable: false, found: null
```

---

## Workflow Integration

The GitHub workflow should:

```yaml
- name: Check if settleable
  run: |
    SETTLEABLE=$(jq -r '.settleable' oracle-result.json)
    if [ "$SETTLEABLE" != "true" ]; then
      echo "❌ Cannot settle: first comment does not exist yet"
      echo "Wait for first comment before settling market"
      exit 1
    fi
    
    echo "✅ Settleable! First comment exists."
```

---

## Contract Integration

Smart contract should verify settleable:

```solidity
function settle(uint256 marketId, bytes memory attestation) external {
    // Parse attestation
    OracleResult memory result = parseAttestation(attestation);
    
    // MUST check settleable
    require(result.settleable == true, "Cannot settle: first comment missing");
    
    // Now safe to use result.found
    market.result = result.found;
    market.settled = true;
}
```

---

## Edge Cases

**What if someone posts a comment, then deletes it?**
- Oracle sees "no comments" again
- Cannot settle until a (permanent) first comment exists
- This is fine - the condition is "first comment" (must exist)

**What if first comment is edited to add/remove keyword?**
- Oracle uses the comment as it exists at check time
- Discourse doesn't let you edit other people's comments
- First commenter could edit, but that's part of the game
- Could add "created_at" check to detect edits

**What if there's a race condition (comment posted during oracle run)?**
- Oracle returns current state at time of check
- Attestation timestamp proves when check occurred
- If comment appears after, need to trigger oracle again

---

## Summary

| State | settleable | found | Meaning | Settlement |
|-------|-----------|-------|---------|------------|
| FOUND | true | true | Comment exists with keyword | YES wins |
| NOT_FOUND | true | false | Comment exists without keyword | NO wins |
| NO_COMMENTS | false | null | Comment doesn't exist yet | Cannot settle |

**Always check `settleable` before settling a market!** ⚠️

---

**Oracle version:** 1.1.0 (added `settleable` field)
