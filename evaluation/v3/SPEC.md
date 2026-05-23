# SPEC: llm-dark-patterns hooks v3 — close measurement & performance gaps with statistical rigor

## Problem Statement

Three in-scope hooks have unvalidated or weak held-out F1: `no-sycophancy` (0.667 TRAIN-only — DarkBench held-out has **zero** sycophancy positives, so the number is unvalidated), `no-roleplay-drift` (0.545 TEST, weakest validated hook), and `honest_eta` (0.230, recall-bound precision tool). Close these gaps without any train/test leakage and without reporting TRAIN-only numbers as if comparable to TEST.

## Success Criteria

All F1 numbers reported with bootstrap 95% CI via `agent-closeout-bench/evaluation/metrics.py::bootstrap_f1_interval` (samples=1000, seed=42) — the no-vibes standard. All scoring deterministic and reproducible (re-run twice → zero per-trace delta).

1. **Task 1 — no-sycophancy held-out positives.** A redistributable (MIT/Apache-source + synthesized-from-taxonomy) held-out positive corpus of **n ≥ 40** sycophancy positives with documented per-trace provenance, labeled by `claude -p` primary judge + an independent second-judge pass, with LLM-LLM Cohen's κ reported (explicitly labeled a proxy, **not** human agreement) and a blind validation sheet exported for operator human-validation. `no-sycophancy` v2 re-run on this TEST set with bootstrap F1 + 95% CI, plus an explicit verdict on whether the 0.667 TRAIN number survives contact with real test positives.
   - Verified by: `data/sycophancy/heldout_positives.jsonl` (one trace+label+source+judge/human flags per line, n≥40), `results/sycophancy_heldout_v2.json` (F1+CI), κ report, blind sheet file.
2. **Task 2 — no-roleplay-drift TEST F1 > 0.70.** Tuned `roleplay_drift.yaml` (and/or `no-roleplay-drift.sh`) scored on a frozen held-out (ACB `locked_test`, n=40: 20 pos / 20 neg) reaches F1 > 0.70 with bootstrap 95% CI reported. Tuning done on `dev` only; if any threshold is tuned against `locked_test`, a fresh held-out slice is carved and used for the headline number.
   - Verified by: `results/roleplay_v3.json` (before/after F1+CI on the frozen split), error-cluster doc, no-test-leak statement.
3. **Task 3 — honest_eta recall up, precision held.** A PR curve on the MAD set (n=954) with an operating point chosen on the PR frontier, and a cascade (high-precision honest_eta + higher-recall pre-filter) with combined F1 reported. Judge-vs-human κ recomputed on the MAD human-labelled subset (n=19). Before/after F1 with CI, precision not materially below the original honest_eta precision.
   - Verified by: `results/honest_eta_pr.json`, PR-curve artifact, cascade F1+CI, κ report.
4. **No leakage / no TRAIN-as-TEST.** No held-out trace is inspected during tuning. No TRAIN-only F1 is presented as comparable to a TEST F1. Each new rule/threshold cites the FN/FP evidence or literature taxonomy that motivated it.
   - Verified by: per-task iteration notes; grep that headline tables label split (TRAIN/TEST/CI) explicitly.
5. **Reproducibility.** Every scoring path re-runs to identical numbers (fixed seed; LLM-judge labels frozen to disk, never re-judged in the scoring path).
   - Verified by: re-run twice, diff = empty.

## Scope

**In scope:** `no-sycophancy.sh`, `no-roleplay-drift.sh` + `agent-closeout-bench/rules/closeout/roleplay_drift.yaml`, `honest-eta.sh`; new eval scripts under `agent-closeout-bench/evaluation/`; the held-out sycophancy corpus + intake; Spanish smoke (stretch).

**Out of scope:** other 25+ hooks; re-generating existing corpora; ELEPHANT/ClawsBench *redistribution* (taxonomy-only per ACB intake registry); true human validation (operator-run from the exported blind sheet — this SPEC delivers everything up to that handoff); MiniMax/cross-provider judge (no key in session — `claude -p` only, out-of-band caveat documented).

## Agent-Native Estimate

- **Estimate type:** agent-native wall-clock
- **Topology:** local supervisor + bounded subagent packets for T3/T1 after T2 proves the pipeline (disjoint files; metrics.py shared read-only)
- **Critical path:** rust build → T2 (baseline → error cluster → rule tune → re-measure) → [T3 ∥ T1] → cross-cutting (CI/reproducibility/Spanish) → verify
- **Agent wall-clock:** optimistic 2.5h / likely 4h / pessimistic 7h (T1 corpus + dual-judge is the long pole; bounded by `claude -p` latency per trace)
- **Human touch time:** operator human-validates ≥50 traces from blind sheet (T1, post-handoff); ~10 min review per task
- **Calendar blockers:** none hard; `claude -p` throughput is the rate limit for T1 judging
- **Confidence:** medium. Risks: roleplay FN tail may be semantic (regex ceiling < 0.70 → escalate to feature rule); honest_eta PR curve needs a synthesized feature-score since the hook is binary; T1 license restriction shrinks the redistributable positive pool.

## Implementation Plan

### Task 2 — no-roleplay-drift (proves the pipeline)
DoD: build engine; baseline bash+rust on dev/validation/locked_test w/ CI; dump every FN/FP on dev; cluster by failure mode; targeted YAML pattern/allow edits each tied to an FN/FP; re-measure on frozen locked_test (carve fresh slice if locked_test was touched); F1>0.70 w/ CI or documented regex ceiling + escalation.

### Task 3 — honest_eta
DoD: confirm MAD gold-label mapping for ETA-honesty; add feature-score to enable PR sweep; PR curve + frontier operating point; cascade pre-filter; combined F1+CI; κ on n=19 subset; precision not materially below baseline.

### Task 1 — no-sycophancy held-out positives
DoD: intake MIT/Apache positives + synthesize-from-taxonomy (SycEval rebuttal taxonomy incl. progressive/regressive; SyConBench multi-turn late-capitulation; ELEPHANT social/face-preserving; BrokenMath well-posed-false); n≥40; dual `claude -p` judge → κ proxy; blind sheet; re-run no-sycophancy v2 → TEST F1+CI; verdict on 0.667 survival.

### Cross-cutting
DoD: bootstrap CI on every F1; re-run-twice zero-delta proof; Spanish smoke per tuned hook (flag any F1 collapse).

## Verification

| Criterion | Method |
|---|---|
| 1 sycophancy held-out | `results/sycophancy_heldout_v2.json` F1+CI; corpus n≥40 w/ provenance; κ + blind sheet present |
| 2 roleplay > 0.70 | `results/roleplay_v3.json` before/after F1+CI on frozen locked_test |
| 3 honest_eta | PR curve + operating point + cascade F1+CI + κ(n=19) |
| 4 no leakage | iteration notes; split labels on every table |
| 5 reproducibility | re-run twice, diff empty |

## Rollback Plan

1. All hook edits land on branch `evaluation/hooks-v3` in each repo; `main` untouched until verified.
2. If a tuned hook regresses on its frozen held-out vs baseline → revert that hook's diff, keep the negative result documented.
3. If roleplay can't clear 0.70 within the regex family → document the ceiling, do not merge a misleading number, propose feature/ML escalation for v4.
4. T1 corpus is additive (new files); rollback = delete the new JSONL + results, no existing data touched.
