# SPEC: no-sycophancy v5 — deterministic regex floor + Haiku WARN cascade

## Problem Statement

v4 proved lexical regex cannot close the sycophancy recall gap (held-out F1 0.298;
recall 0.0 BrokenMath/SyConBench, 0.08 ELEPHANT; v4 tiers overfit DEV 0.75→FRESH 0.30).
Deepresearch (`.taste/research/cascade-llm-judge-tier.md`) shows the SOTA fix is a
deterministic-floor + cheap-LLM-judge-ceiling cascade. Build and **measure** it.

## Success Criteria

All F1 with bootstrap 95% CI (metrics.py, seed 42). Cascade eval is deterministic
(judge labels frozen to disk — LLM judges are not reproducible at temp 0, so they must
not be in the reproducible path).

1. **Cascade closes the recall gap on the FRESH set** (the set v4 overfit on). The
   regex∪Haiku-WARN cascade reaches recall ≥ 0.70 on the fresh held-out positives
   (vs regex-only 0.13/0.17), with **precision ≥ 0.80** overall (controls FP-rate
   bounded). Reported on BOTH held-out (n=58) and fresh (n=35), per-mode recall.
   - Verified by: `results/v5/cascade_freshtest.json` + `cascade_heldout.json` (regex-only vs cascade, F1+CI, per-mode).
2. **Determinism preserved.** The regex `BLOCK` path is unchanged and reproducible; the
   Haiku tier is `WARN`-only (never escalates to BLOCK) and scored from frozen labels.
   Re-run twice → zero per-trace delta.
   - Verified by: re-run diff empty; `no-sycophancy.sh` unchanged (BLOCK path intact).
3. **Cross-model + regex-negative gating.** The WARN judge is Haiku (cross-tier vs
   Opus/Sonnet closeouts) and fires only on regex-NEGATIVE closeouts (targets misses +
   inverts the adversarial-cascade early-termination vuln, arXiv:2605.17288).
   - Verified by: scorer logic + reference WARN-tier hook.
4. **Reference implementation.** A reference `WARN`-tier hook that runs regex first and,
   on regex-negative closeouts, calls `claude -p --model haiku` with a frozen rubric,
   emitting WARN (exit 0 + stderr), opt-in via env, clearly marked non-deterministic.
   - Verified by: `bash -n` syntax + a smoke test on 1 positive / 1 negative.

## Scope

**In scope:** cascade eval scorer (frozen labels); per-mode recall + bootstrap CI on both
corpora; reference WARN-tier hook (`hooks/no-sycophancy-warn.sh` or lib); v5 RESULTS doc.

**Out of scope:** changing the deterministic `no-sycophancy.sh` BLOCK path; live-judge
production wiring beyond the reference smoke; cross-PROVIDER (non-Claude) judge (no key);
roleplay/honest_eta cascades (sycophancy first).

## Agent-Native Estimate

agent-native wall-clock; single Opus lane (eval is judgment-light but
correctness-critical). Critical path: SPEC → cascade scorer (frozen labels) → score both
corpora → reference WARN hook + smoke → v5 RESULTS → verify. Likely 30–60 min agent
wall-clock; no calendar blockers (frozen labels → no API in eval path). Confidence: high
— the recovery numbers (Haiku 0.88/0.96 positive recovery) are already measured; the open
risk is the control FP-rate, which the eval will surface.

## Implementation Plan

### Task 1: cascade eval scorer (frozen labels)
`evaluation/score_sycophancy_cascade.py`: for each trace, regex_fire = no-sycophancy.sh
exit 2; cascade_pred = regex_fire OR (NOT regex_fire AND judge_haiku==1). Score regex-only
vs cascade vs (sonnet variant) on held-out + fresh; bootstrap CI; per-source recall;
control FP count. DoD: results JSON for both corpora.

### Task 2: reference WARN-tier hook
`hooks/no-sycophancy-warn.sh`: sources/duplicates the regex check; on regex-negative,
`claude -p --model haiku` with a frozen rubric → WARN (exit 0 + stderr), opt-in
`LDP_SYCOPHANCY_WARN_JUDGE=1`. Never exit 2 (no BLOCK from the model). DoD: `bash -n` ok +
smoke on 1 pos / 1 neg.

### Task 3: v5 RESULTS + verify
`evaluation/v5/RESULTS.md`: regex-only vs cascade table (both corpora), per-mode recall,
control FP, determinism proof, honest precision-cost. /verify against criteria 1–4.

## Verification

| Criterion | Method |
|---|---|
| 1 recall gap closed | cascade vs regex F1+CI + per-mode recall on fresh & held-out |
| 2 determinism | re-run diff empty; no-sycophancy.sh BLOCK path unchanged |
| 3 gating/cross-model | scorer logic (regex-negative only; haiku judge) |
| 4 reference hook | `bash -n` + smoke pos/neg |

## Rollback Plan

1. All v5 work on branch `feature/v5-cascade-haiku-tier`; `no-sycophancy.sh` BLOCK path untouched.
2. If cascade precision collapses on controls (FP-rate high) → report the precision/recall
   tradeoff honestly, recommend WARN-only (not BLOCK) deployment, do not claim a clean win.
3. WARN-tier hook is additive + opt-in; rollback = delete the new file.
