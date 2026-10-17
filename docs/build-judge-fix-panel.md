# Build → Judge → Fix with Adversarial Model Panels

*A method, not a mechanism. Build one slice; hand it to a panel of different models told to break it; fix every confirmed finding; re-run the invariant tests; move on.*

## Context

You are building controls whose entire value is that they hold under adversarial pressure: authorization gates, honesty checks, scope boundaries. A control that only "looks right" to its author is worthless; the author shares the blind spot that lets the bug through.

## Problem

Single-model review (including self-review) inherits one model's taste and one model's blind spots. A reviewer asked "is this good?" tends to confirm; a reviewer that can upgrade or approve becomes a soft authority. And "the tests pass" proves only that the cases you thought of pass.

## Forces

- Reviewers must be motivated to find problems, not to approve.
- Taste and blind spots are model-specific, so diversity catches more.
- The build must not regress its invariants while you iterate.

## Solution

1. **Build one slice** at a time (one gate, one metric), small enough to reason about.
2. **Judge with a panel of *different* models** (e.g. opus + sonnet + fable + haiku), each told explicitly to **break it**: "find the case where this control lies / can be bypassed / loosens the thing it should tighten," with file:line and a failing case. Adversarial framing, not "review this."
3. **Synthesize**: a finding two models raise is almost certainly real; a lone claim gets verified against the code before you act.
4. **Fix every confirmed finding**, then **re-run the invariant tests** (the frozen suite that must never go red) before the next slice.
5. Keep the honest caveats the panel surfaces and ship them with the artifact.

This is how the platform was built, and it paid off concretely: a cross-family panel caught a real anonymization leak a single model missed, and a *different* model reading the code caught a silently-regressed confirm gate. "Don't grade your own homework" is the whole point.

## Consequences

- **+** Catches bypasses and regressions a single reviewer (human or model) misses.
- **+** Produces the adversarial test cases that turn "FP = 0" into *"FP = 0, red-teamed"*: the difference between un-gamed-yet and ungameable.
- **−** Costs several model runs per slice; reserve the full panel for the controls that matter, use a lighter touch for low-stakes code.
- **−** Panels disagree; you still have to synthesize and verify, not just tally votes.
- **−** A safety classifier may false-positive on legitimate defensive work; route around it (write to a file, frame defensively) rather than abandoning the review.

## Instantiation

Used throughout a private autonomous-security platform: the authorization gates, the resource-scope embedded-authority fix, the budget/posture/verifier slices, and the eval/guardrail/benchmark layer were each built then challenged by a multi-model panel with confirmed findings folded back, the frozen invariant suite re-run green after every edit. Pairs with independent verification: audit with a broader pattern set than the scrubber's own.
