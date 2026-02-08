# Session Notes: Paper Refactoring - 2026-02-08

## Major Changes Made

### Structure Refactoring
1. **Deleted Section 3.3 "What GitHub Cannot Do"** - redundant given workarounds in Extensions
2. **Moved TEE Governance from Section 2.5 to Discussion (Section 7.2)** - opinion/analysis belongs in Discussion, not Background
3. **Restructured Section 6 Extensions:**
   - 6.1 Replicated Secrets Across Runners (the novel primitive - secrets migrate between runners with matching attestations)
   - 6.2 Coprocessor Networks (smart contract as registry + linearizer, TIME dimension, anti-rug)

### Conceptual Reframings
1. **Section 2.2 renamed "Attestation Primitives"** - focus on platform-controlled claims as the key primitive
   - Two verification approaches: direct crypto (Sigstore) vs committee-based (Opacity)
   - De-emphasized Rekor (we don't verify inclusion proofs)

2. **Section 2.4 renamed "Unexpected TEEs"** - broader question of what platforms can be repurposed

3. **Replaced SGX with TDX/SEV as primary examples** - SGX is deprecated
   - Updated bib entry and paper text for tee.fail (2025 DDR5 memory bus attacks on TDX/SEV/GPU)

4. **zkTLS section clarified** - self-service (own GitHub Secrets) vs delegated (encrypt to attested ephemeral key)

### Fluff Trimmed (~90 lines total)
- Trusted setup paragraph: ceremony dates → just cite Ignition
- "What can be verified without trust?" section → deleted
- Redundant "A taxonomy" → deleted (already in table)
- Listing 2 (Attestation struct) → deleted (same as Listing 1)
- "Separating Authorship" section: 3 fluffy paragraphs → 1 sentence
- TLSNotary history → deleted
- zkTLS delegated model: 2 paragraphs → 2 sentences
- Mid-execution attestation: simplified, removed sealed-bid example

### Garbage Claims Fixed
- Removed "stronger auditability than Intel's IAS" (2 places)
- Removed "strikingly similar to our model"
- Removed "arguably no stronger than trusting Intel"
- Removed "gap is narrower than it appears"
- Honest framing: hardware TEEs provide stronger isolation, GitHub provides simpler deployment

## References Directory Created
All 33 references now have local copies in `/home/amiller/projects/teleport/github-zktls/paper/references/`:
- 19 academic papers as PDF + TXT
- 14 website/doc references as MD
- Minor gaps: sealingpitfalls (Cloudflare blocked), trustlesstee (talk not public)

## Key Conceptual Points (from earlier session)

### P2P Coprocessor Networks are about TIME
- Operations > 6 hours
- Anti-rug redundancy (multiple runners, first-to-complete wins)
- Stable pubkey for receiving encrypted data over time
- "Anyone-can-serve" comes FREE from attestation mechanism

### The Rug Vector
- Operator can cancel job even with attested code
- Code integrity ≠ execution guarantee
- P2P fixes via redundancy

### Platform Guarantees "Against the User"
- OIDC claims are platform-controlled, user cannot forge
- This is what makes attestation work
- Even without Sigstore, committee could verify GitHub's API (Opacity model)

## Files Modified
- `/home/amiller/projects/teleport/github-zktls/paper/main.tex` - major refactoring
- `/home/amiller/projects/teleport/github-zktls/paper/refs.bib` - updated teefail entry

## Git Commits (pushed to both GitHub and Overleaf)
- Refactor: move governance to Discussion, reframe Extensions around TIME
- Restructure Extensions: replicated secrets + coprocessor networks
- Fix incorrect claims about Sigstore vs hardware attestation
- Fix overstated comparisons between GitHub and hardware TEEs
- Fix false equivalence in TEE background section
- Trim fluff from Section 3
- Trim more fluff throughout paper
- Reframe: attestation primitives and unexpected TEEs
- Replace SGX with TDX/SEV as primary TEE examples
- Fix tee.fail reference - covers TDX/SEV/GPU, not just SGX

## Pending Tasks
- Commit references directory to repo
- Fill in Introduction section (currently just outline comments)
- Fill in Limitations subsection in Discussion
- Fill in Conclusion section
- Review for any remaining fluff or garbage claims
