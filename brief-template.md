# Opposing Counsel Brief — <artifact name>

Review `<path/to/artifact>` in the repository. This is a **read-only** security and correctness review. Do **not** edit files, run tests that write artifacts, launch network requests, or use credentials.

## Framing (adversarial)

You are on an adversarial panel. Your job is to **break** this, not to approve it: find the case where the control **lies**, can be **bypassed**, or **loosens** the property it is supposed to tighten. A reviewer that confirms is a failed reviewer. Where you can, **read the code closely enough to reproduce** a failure, not merely inspect it.

## Output — one finding per defect

For each finding, include:

- **Severity** (critical / high / medium / low)
- **Exact `file:line`**
- **Concrete trigger / reproduction** — inputs or state that make it fail
- **Impact** — what the failure lets an attacker or a wrong input do
- **Evidence** — the code path, quoted
- **Proposed fix**
- **Untested limitations** — what you could not verify

**Separate proven defects from hypotheses.** Rank most-severe first. If you find nothing in a lane, say so explicitly rather than padding.

## Review lanes (edit per artifact)

Cover each, and name which lane each finding belongs to:

- [ ] Authorization & scope — can authority leak, be reused, or be self-granted?
- [ ] External-tool / subprocess execution — argv injection, egress escape, unparsed output
- [ ] Request/transport enforcement — host-pinning, redirects, header allowlist, methods
- [ ] State / checkpoint / retry — replay, resume-after-seal, idempotency
- [ ] Concurrency & budgets — cross-branch leakage, shared-pool exhaustion, fan-out races
- [ ] Evidence & provenance — receipt binding, chain verify, attestation, "executed ⊆ recorded"
- [ ] Verifier / scoring / reporting — can a false claim be confirmed? can a metric be gamed?
- [ ] Test gaps — invariants asserted nowhere; negative controls missing

## Enforcement boundary

`<which paths are this package's responsibility>` vs. `<which are a shared / frozen dependency>`. Distinguish a defect in the artifact under review from a defect in that shared boundary — attribute each finding to the right side.

## Invariants that must hold (state them, so a violation is a finding)

- `<e.g. no finding is confirmed without a receipt citing its ground-truth canary>`
- `<e.g. an out-of-scope action is denied and sealed, never executed>`
- `<e.g. the frozen suite (N tests) stays green>`
