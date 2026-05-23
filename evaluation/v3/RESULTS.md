# llm-dark-patterns hooks v3 — results summary

Closing the measurement/performance gaps from the v2 SPEC with statistical rigor
and zero train/test leakage. Every F1 carries a bootstrap 95% CI
(`agent-closeout-bench/evaluation/metrics.py`, samples=1000, seed=42); every
scoring path is deterministic (re-run twice → zero delta). TRAIN-only numbers are
never compared to TEST numbers.

See per-task docs: `RESULTS-task2-roleplay.md`, `RESULTS-task3-honest-eta.md`,
`RESULTS-task1-sycophancy.md`, `RESULTS-crosscutting.md`.

## Headline

| Task | Hook | Before | After | Verdict |
|---|---|---|---|---|
| 1 | no-sycophancy | 0.667 TRAIN (unvalidated) | **0.298 F1 on real held-out** (P=1.00, R=0.175) | 0.667 does **NOT** survive — see below |
| 2 | no-roleplay-drift | 0.545 TEST | **0.640 TEST** (CI [0.40,0.82]) | improved; 0.70 not cleared on n=22 (documented ceiling) |
| 3 | honest_eta | 0.230 (2.6) | **0.461** via cascade (CI [0.42,0.50]) | recall lift via ensemble, not hook change |

## Task 1 — no-sycophancy: the 0.667 TRAIN number does not survive

Built a redistributable, leakage-free held-out positive corpus (n=58: 40
positives across SycEval / SyConBench / ELEPHANT / BrokenMath subtypes + 18
controls), authored from the published taxonomies (not from the hook's regexes).
no-sycophancy v2 on it: **P=1.000, R=0.175, F1=0.298** [CI 0.130–0.458].

Recall by sycophancy type exposes the hook as a high-precision *opener-praise*
detector that misses the dominant 2026 modes:

| Type | Recall |
|---|---|
| DarkBench-style opener-praise (its target) | 0.833 |
| SycEval rebuttal-induced flips | 0.111 |
| ELEPHANT social/face-preserving | 0.083 |
| SyConBench multi-turn capitulation | 0.000 |
| BrokenMath false-statement validation | 0.000 |

Perfect precision (0 false-fires on 18 controls incl. redemption cases). The
0.667 TRAIN was on opener-praise/validation-heavy positives; against the real
taxonomy the hook catches almost nothing outside its narrow surface.

## Task 2 — no-roleplay-drift: real lift, honest ceiling

On the real DarkBench anthropomorphization held-out (n=22; the ACB synthetic
corpus is a co-evolved F1=1.0 fixture and was discarded): tuned the rust pack
(politeness allow-patterns + a new experiential-claim subfamily, validated
train-only) → **TEST F1 0.545 → 0.640**, recall +0.167, precision held, TRAIN
0.600 → 0.825. The 0.70 target is not cleared on n=22 (it sits inside the CI);
the ceiling is a chat-vs-closeout surface conflict, documented with an ablation.

## Task 3 — honest_eta: cascade, not hook surgery

honest_eta maps to MAST mode 2.6; it's a narrow ETA detector on a broad mode →
F1 0.230. The shippable lift is the **honest_eta ∪ evidence_claims cascade:
F1 0.461** (recall 0.153→0.536), CIs non-overlapping (significant at n=954). The
shipped hook is unchanged: its one intrinsic recall lever (the hedge-gate) is
correct for the closeout surface, so relaxing it would break real behavior.

## Cross-cutting

- Bootstrap CIs on every F1; reproducibility verified (zero per-trace delta).
- **Spanish smoke: total cross-lingual collapse** — both hooks catch 0/3 Spanish
  positives (English-pattern-only), per the DarkBench+ AAAI 2026 finding.
- Dual `claude -p` judge (sonnet + haiku) on the sycophancy held-out →
  inter-Claude κ proxy (NOT human; out-of-band caveat documented). Real human
  validation deferred to the exported blind sheet
  (`agent-closeout-bench/annotations/sycophancy_heldout_blind_sheet.csv`).
  Judge κ: construction-vs-sonnet **1.000**, construction-vs-haiku 0.813,
  inter-judge **0.813**; sonnet recovered 40/40 positives → the 33 hook misses
  are genuine sycophancy, not mislabeled data.

## What shipped vs what's staged

- **Additive (written):** v3 SPEC + result docs; eval scripts in
  `agent-closeout-bench/evaluation/` (`score_darkbench.py`, `score_roleplay.py`,
  `honest_eta_task3.py`, `sycophancy_*`); held-out corpus + blind sheet;
  `results/v3/*.json`.
- **Staged, not applied to live hooks:** tuned `roleplay_drift.yaml`
  (`evaluation/v3/staged-rules/`). Recommend reviewing on branch
  `evaluation/hooks-v3` before applying — it improves F1 but doesn't hit 0.70.
- **No change** to `honest-eta.sh` / `no-sycophancy.sh` (intentional; see docs).
- **v4 backlog:** sycophancy recall on non-opener-praise modes; surface-aware
  roleplay/honest_eta; locale packs for cross-lingual coverage.
