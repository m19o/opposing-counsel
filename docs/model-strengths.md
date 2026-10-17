# Model strengths: a challenged list

Which model gets which lane, and how much that assignment is worth. This list started as field notes from one build session (2026-10-02). On 2026-10-15 it was challenged two ways: against the rest of the work records it came from (replicated across sessions, several test-gated) and against public benchmarks (versions and dates pinned below). One row failed outright and is corrected here; two more needed their mechanism corrected. Treat every row as having a shelf life of about one release cycle: models move, re-derive with your own board.

Two honesty notes before the table. The original list was self-assessed by the model it ranked highest, which is exactly the failure this repo exists to catch; the verdicts below only count where a different model or a test gate confirmed them. And internal verdicts are model+harness properties: every "honest" or "reliable" row below was measured inside receipt-gated workflows where a bad claim gets demoted. Public unharnessed numbers measure the same models with no gate, and they disagree sometimes. Both are true in their context.

Since 2026-10-17 this list is also checked against a seeded-bug fixture benchmark: six re-introduced bugs from the maze's hardening history, seats scored on recall against an answer key. The measured matrix and its integrity notes are in the README's benchmark section.

## The lanes (as of 2026-10-15; Fable 5.1, Opus 5.5, Sonnet 5.5, Haiku 5.5, Kimi K3 / K2.8 era)

| Seat | Lane | Confidence |
|---|---|---|
| Opus | Chair: orchestration, cross-file synthesis, final judgment | Confirmed internally and publicly |
| Sonnet | Workhorse: careful implementation, best cost-capability point | Confirmed, with one correction |
| Fable | Taste, docs, honest synthesis inside the gates | Confirmed in-harness; contradicted publicly outside them |
| Haiku | Cheap mechanical enumeration, always with a verification pass, never solo judgment | Confirmed in direction; mechanism corrected |
| Kimi K2.8 | Autonomous execution | Strongest internal evidence in the set; public evidence is vendor-only |
| Kimi K3 | Orchestration, consulting/architecture review | Confirmed internally; weak publicly, supervised use only |

**Opus chairs.** Internal: nearly every slice it synthesized passed the frozen invariant suite, and its review passes found real HIGHs. Public: #1 on Artificial Analysis Index (58), Arena Text (1509), independent Terminal-Bench 4.0 (65.15%), SWE-bench Pro (89.9%), GDPval-AA (1846), and the best knowledge-reliability index of the family (46.4). Anthropic reserves "sustained judgment" language for it over Sonnet. Weak leg in the original list: in these workflows the recorded orchestrators were actually K3 and the main session, so "orchestration" is a shared lane, not Opus's alone.

**Sonnet builds.** Internal: a 25-commit headless build cycle, all suites green; deep audits with reproduced findings; no record of shipping bad code. Public: #1 on Artificial Analysis's own Terminal-Bench run (63.6%) at half Opus's price. Correction to the original list: "deep audit depth" belongs to Opus, not Sonnet. Opus leads SWE-bench Pro by 8.6 points (89.9 vs 81.3), and Anthropic assigns complex open-ended work to Opus. Sonnet is the high-throughput careful implementer, not the deepest reviewer.

**Fable judges taste and writes the honest doc, inside the gates.** Internal: the UX-honesty and design judging lanes, and the competitive-position doc that states losses plainly. The original list's "slightly less code depth than Sonnet" is contradicted internally: on two test-gated boards Fable found the deepest defect first (a funnel blocker, a forgery hole), and it ran a 15/15 adversarial-bypass denial pass. Public: contradicted outside the gates. AA-Omniscience gives Fable 5.1 the family's worst calibration (72.6% fabrication when it does not know), and Anthropic positions it as the hardest-reasoning tier, not the taste tier, flagging its prose as denser than its predecessor. Read together: keep Fable on judgment/docs lanes inside receipt-gated workflows where claims must cite evidence; do not trust it ungrounded.

**Haiku sweeps, never judges.** Internal: documented failure is misses and miscounts: two boards where it shipped "no findings" by inspection while other seats found real defects, plus false-alarm sweeps (wrong-venv "failures", miscounts). The original list's "over-reported false positives twice" is half the story; the mechanism is an accuracy gap, not a specific FP rate. Public: the gap is enormous (Terminal-Bench 39.2 vs Sonnet's 70.6; Omniscience accuracy 14.4% vs Opus's 66.2%) and its low hallucination rate comes from declining, not from being right. Rule stands: cheap enumeration with an independent verification pass, never a verdict of its own. Note Anthropic claims Haiku 5.5 had the lowest FP rate in one triage eval, one vendor eval, unverified here.

**Kimi K2.8 executes.** Internal, the strongest evidence in this set: measured bake-off runs at 5/6 proven with zero confabulated findings (n=5, mean 5.0/6, confab 0/24), re-derived twice from raw receipts by different models, never recurred across 51 confirmed findings. Its recorded failures are craft gaps, not honesty gaps. The zero-confab property is model+harness though: the receipt gate demotes bad claims, so credit the pair, not the model alone. Public: the K2 line independently led open-weight agentic coding (Terminal-Bench 2.1: 67%); K2.8-specific numbers are Moonshot changelog only.

**Kimi K3 orchestrates and reviews architecture.** Internal: orchestrated a 5-hour, 25-commit, all-green build cycle; its reconcile critique caught real design flaws another model missed; "strongest model id" in the harness's own docs. Public: weak. Hallucination ~51-53% (up from K2.6's 39%), novel-reasoning gap (ARC-AGI-2 60.4 vs Opus 5.5's 93.3), independent verdict "supervised, verifiable-output workloads only." That is precisely how the board uses it: every claim it makes gets verified by a different model or a gate.

## The rules that survived the challenge

1. A claim is never verified by its author. This list was self-assessed by Opus; the one row that failed under challenge is the one that flattered the original ranking.
2. At least one cross-vendor seat. Correlated blind spots are the failure mode the panel exists to break.
3. Cheap tiers never judge alone. They sweep; something else verifies.
4. "Reliable" is a model+harness property. Public unharnessed benchmarks and internal gated experience disagree most on the models with the strongest gates around them (Fable, K3). When they disagree, trust the measurement that matches your usage.
5. Pin model IDs and dates. This list is pinned to 2026-10-15 versions; a new release invalidates it.
6. What no public benchmark measures (judge false-positive rates by tier, taste, orchestration quality), the board itself is the instrument. Run it, record what each seat is actually good at, update this file.

## Sources

Internal: build-cycle reports, board syntheses, and bake-off measurements in the author's private kit (2026-08-27 through 2026-10-08, test-gated where noted). Public: Artificial Analysis Intelligence Index v4.3.2 (Sep 2026), vals.ai Terminal-Bench 4.0 (2026-10-13), SWE-bench Pro (2026-10-14), LMArena Text/WebDev (Oct 2026), AA-Omniscience hallucination tracker (2026-10-08), Anthropic model announcements (Sep-Oct 2026), Moonshot Kimi K3 tech report and Kimi Code changelog (Jul-Sep 2026), WithO2 Kimi K3 review (2026). Benchmark formulas changed twice in September 2026; vendor-vs-independent gaps run 6-7 points; treat every number as one-release-cycle fresh.
