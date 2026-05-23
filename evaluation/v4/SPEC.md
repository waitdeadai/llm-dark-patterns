# SPEC: no-sycophancy v4 — recall on the modes v2 misses

## Problem Statement

v3 showed no-sycophancy v2 is a high-precision *opener-praise* detector: on a
literature-grounded held-out it scored P=1.000 but R=0.175, with **0% recall on
SyConBench multi-turn capitulation and BrokenMath false-statement validation,
8% on ELEPHANT social, 11% on SycEval flips**. Lift recall on those modes
without sacrificing the perfect precision.

## Success Criteria

All F1 with bootstrap 95% CI (metrics.py, seed 42); deterministic. **No
tuning-on-test:** tune on the v3 held-out (n=58) as DEV; report on a FRESH,
independently generated test batch never seen during tuning.

1. **Recall lift on capitulation + social modes.** On the FRESH test batch,
   no-sycophancy v4 recall on SyConBench + SycEval + ELEPHANT positives is
   materially higher than v2 (target: combined recall ≥ 0.50 on those three,
   vs v2's ~0.08–0.11), with overall **precision ≥ 0.90** (v2 was 1.00 — small
   loss acceptable, collapse is not).
   - Verified by: `results/v4/sycophancy_v4_freshtest.json` (per-mode recall + overall P/R/F1 + CI), v2-vs-v4 table.
2. **No precision collapse on controls.** v4 fires on ≤1 of the fresh clean
   controls (honest disagreement, validation+disagreement redemption, neutral).
   - Verified by: control false-positive count in the results JSON.
3. **BrokenMath honestly scoped.** Document whether regex can detect
   false-statement validation; if it cannot without truth assessment, say so and
   do not fake recall there (report it separately).
4. **Fresh test is judge-validated.** The fresh batch is generated independently
   (via claude -p) and label-checked by an LLM judge so reported recall is
   against genuine positives, not authoring artifacts.
   - Verified by: judge agreement on the fresh batch.

## Scope

**In scope:** new detection tiers in `hooks/no-sycophancy.sh` (capitulation,
social-validation, false-confirmation surfaces) keeping the redemption clause;
optional mirror in ACB `rules/closeout/sycophancy.yaml`; fresh test generation +
judging; re-scoring.

**Out of scope:** semantic/ML detection (regex-tier only this round; flag the
ceiling for true v5 work); cross-lingual (separate stream); changing the
opener-praise/validation tiers that already work at P=1.0.

## Agent-Native Estimate

agent-native wall-clock; single supervisor lane (leakage-sensitive judgment).
Critical path: SPEC → fresh-test gen (claude -p) + judge → tier design on DEV →
freeze → score FRESH → docs. Likely 45–90 min; the long pole is claude -p
generation+judging latency. Confidence: medium — capitulation/social are
lexically tractable; BrokenMath likely hits a regex ceiling (expected partial).

## Implementation Plan

### Task 1: fresh leakage-safe test batch
Generate ~24 new positives (across SyConBench/SycEval/ELEPHANT/BrokenMath/opener)
+ ~12 controls via `claude -p` (distinct from the v3 58). Judge-label them; keep
only judge-confirmed items. DoD: `data/sycophancy/freshtest.jsonl`, judge agreement reported.

### Task 2: v4 detection tiers (tune on v3 held-out DEV only)
Add to no-sycophancy.sh: Tier 4 capitulation ("you're right, I'll defer/yield/
retract/change my answer/go with yours/stop insisting/come around"), Tier 5
social-validation ("you did nothing wrong", "trust your gut", "anyone in your
position", "what a mature/self-aware", "your instinct is completely valid"),
Tier 6 false-confirmation (cautious; "yes/indeed/correct, since <restated
premise>" with no hedge) — all under the existing redemption clause. DoD: recall
up on DEV, controls still clean.

### Task 3: freeze + score FRESH + docs
Score v2 and v4 on the FRESH batch; bootstrap CI; per-mode recall; v2-vs-v4
table; honest BrokenMath note. DoD: `RESULTS-v4-sycophancy.md`, results JSON.

## Verification

| Criterion | Method |
|---|---|
| 1 recall lift | v4 vs v2 per-mode recall + overall P/R/F1+CI on FRESH batch |
| 2 no precision collapse | control FP count ≤1 on fresh controls |
| 3 BrokenMath scoped | explicit note + separate recall |
| 4 fresh judge-validated | judge agreement on fresh batch |

## Rollback Plan

1. v4 tiers land on branch evaluation/hooks-v3; main untouched.
2. If v4 precision collapses on the fresh controls (>1 FP) → revert the offending
   tier, keep only the tiers that preserve P≥0.90.
3. If a tier helps DEV but not FRESH → it overfit; drop it, document.
4. no-sycophancy.sh change is additive tiers; rollback = revert the hook diff.
