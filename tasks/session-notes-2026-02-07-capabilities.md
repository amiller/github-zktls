# Session Notes: Capabilities and P2P Network Discussion

## Key Capability Layers

### 1. Basic Attestation
- Single workflow run, attest output at end
- Your own credentials in GitHub Secrets
- Self-service model

### 2. Delegated Attestation (Mid-Execution)
- Workflow generates keypair, attests pubkey MID-RUN
- External party encrypts credentials/data to that pubkey
- Workflow decrypts, processes, attests result
- **Key insight**: Users without GitHub accounts can use workflows
- They trust GitHub (via attestation) but not the repo owner directly

### 3. Anyone-Can-Serve (comes free from attestation)
- Anyone can fork the repo and run the workflow
- All get attested with same commit SHA
- Users choose which runner to trust by checking attestation
- **This is implicit in the attestation mechanism, not a separate feature**

### 4. P2P Coprocessor Network
- Multiple runners share replicated secrets
- Secrets persist across 6-hour run boundaries
- Runners can hand off to each other

## What P2P Network Adds (mainly TIME dimension)

| Need | Single Run | P2P Network |
|------|------------|-------------|
| Operations < 6 hours | ✓ | ✓ |
| Operations > 6 hours | ✗ | ✓ |
| Stable pubkey for receiving encrypted data over time | ✗ | ✓ |
| Resistance to single operator rug (cancel job) | ✗ | ✓ (redundancy) |

## The Rug Vector

Even with attested code:
- The OPERATOR can cancel the job before completion
- "Free option" attack: see decrypted data, then cancel before releasing
- Code integrity ≠ execution guarantee

**Solution**: Multiple competing runners, first-to-complete wins
- Requires P2P coordination or consensus among runners
- No single operator can block completion

## Fair Exchange Example (Two Digital Files)

Alice has doc signed by TikTok, Bob has doc signed by DocuSign, want atomic swap.

**Single run (works if fast):**
1. Workflow attests pubkey
2. Both encrypt their doc + recipient pubkey, submit
3. Workflow decrypts, verifies signatures
4. Re-encrypts each doc to other party's key
5. Publishes both ciphertexts simultaneously

**When single run breaks:**
- Bob takes > 6 hours → run dies, Alice must resubmit
- Operator cancels mid-exchange → free option attack
- Want "standing offer" that persists → need stable pubkey

**P2P network fixes:**
- Long windows (no 6hr deadline)
- Anti-rug (multiple runners, redundancy)
- Standing offers (stable pubkey for encrypted submissions)

## Stable Pubkey Matters For:
- Receiving encrypted data over time (like a mailbox)
- Not for "identity" in abstract sense
- Specifically: workers need to be able to DECRYPT submissions
- Standing offers, long auctions, continuous services

## Escrow / Agent Marketplace Example
- Bounty: "Pay X if you tweet Y from account with Z followers"
- Single run: Verify tweet via zkTLS, submit proof, contract pays
- This works without P2P network (verify-and-settle pattern)
- P2P needed if: monitoring continuously, long windows, anti-rug redundancy

## Key Realization
The P2P coprocessor network is mainly about the TIME dimension:
- Extending beyond 6-hour limit
- Providing continuous availability
- Anti-rug through redundancy (no single operator controls completion)

The TRUST dimension (anyone-can-serve, open participation) comes from attestation alone - you get it "for free" with mid-execution attestation + delegated input.

## Paper Structure Thoughts

Current issues:
- Section 2.5 (governance discussion) is too opinionated for Background → move to Discussion
- Mid-execution attestation shouldn't be in "Extensions" → it's a core capability
- "Extensions" is wrong framing for coprocessor network → it's about time/availability

Proposed:
- Background: just technical primitives
- GitHub as TEE: include mid-execution attestation as capability (not a big deal)
- Keep Applications as-is, but clarify self-service vs delegated models
- Coprocessor Networks: frame around TIME (long operations, availability, anti-rug)
- Discussion: governance analysis, Proof of Cloud, trust models

## References Added This Session
- Keystone (open TEE on RISC-V)
- Dstack (smart contract governance for TEE)
- Proof of Cloud (physical security attestation alliance)
- Trustless TEE / Cypherpunk Silicon
- Sealing pitfalls blog
- GitHub Actions limits documentation
- Oasis ROFL, Secret Network
