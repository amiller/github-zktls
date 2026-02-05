# Example Bounty Prompt

This is an example of a well-specified bounty prompt. Good prompts are:
- **Specific** — clear acceptance criteria
- **Verifiable** — Claude can check the diff
- **Scoped** — not too broad

---

## Example: Login Validation

```
Add input validation to the login form:

1. Email field:
   - Must be valid email format (contains @ and domain)
   - Show error "Please enter a valid email" below field

2. Password field:
   - Must be at least 8 characters
   - Show error "Password must be 8+ characters" below field

3. Submit button:
   - Disable while either field has errors
   - Only enable when both fields pass validation

4. Validation timing:
   - Validate on blur (when user leaves field)
   - Re-validate on each keystroke after first blur
```

---

## Example: Bug Fix

```
Fix the login bug where users can't log in with email addresses containing '+'.

The bug is in src/auth/validate.ts - the regex incorrectly treats '+' as invalid.

Acceptance criteria:
- test@example.com works (existing)
- test+tag@example.com works (currently broken)
- Add test case for '+' in email
```

---

## Example: Feature Addition

```
Add a "Remember me" checkbox to the login form:

1. Checkbox labeled "Remember me" below password field
2. If checked:
   - Store session for 30 days instead of default 24 hours
   - Pass `remember: true` to the login API
3. Checkbox unchecked by default
4. Persist checkbox state in localStorage
```

---

## Tips for Bounty Creators

1. **Be specific about files** — "Fix in src/auth/validate.ts" is better than "fix the auth"
2. **Include test criteria** — "Add test case for X" makes verification easier
3. **Define edge cases** — what should happen in unusual situations?
4. **Scope appropriately** — one focused task per bounty
