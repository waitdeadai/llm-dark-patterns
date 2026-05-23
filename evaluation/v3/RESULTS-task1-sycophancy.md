# v3 Task 1 — no-sycophancy held-out positive set (highest priority)

**Status:** corpus built and judge-validated; no-sycophancy v2 re-run on real TEST
positives. **Verdict: the 0.667 TRAIN number does NOT survive.** Human validation
deferred to an exported blind sheet (LLM judges here are an inter-Claude proxy).

## (1) What changed / what was built

DarkBench's held-out has **0** sycophancy positives (confirmed: 2/110 across the
full set, 0 in test), so no-sycophancy v2's 0.667 was TRAIN-only and unvalidated.
Built a fresh, **redistributable, leakage-free** held-out positive corpus,
authored from the 2026 sycophancy taxonomies (taxonomy-only use; original text;
ELEPHANT/ClawsBench not redistributed, per ACB's intake registry):

`agent-closeout-bench/data/sycophancy/heldout_positives.jsonl` — **n=58 (40
positive / 18 control)**, one trace + label + source + subtype + judge/human
flags per line:

| Source taxonomy | Subtypes | # positives |
|---|---|---|
| SycEval (arXiv:2502.08177) | regressive / progressive flips, preemptive & in-context rebuttal | 9 |
| SyConBench (Hong 2025) | multi-turn accumulated capitulation (late-turn) | 5 |
| ELEPHANT (arXiv:2505.13995) | emotional validation, moral endorsement, framing acceptance, indirect | 12 |
| BrokenMath (arXiv:2510.04721) | well-posed false-statement validation | 8 |
| DarkBench-style | opener-praise (the hook's target surface) | 6 |
| controls (label 0) | honest disagreement, validation+disagreement redemption, neutral closeouts | 18 |

## (2) no-sycophancy v2 on the held-out TEST set (bootstrap CI, seed 42)

| gold | P | R | F1 | F1 95% CI | tp/fp/fn/tn |
|---|---|---|---|---|---|
| construction label | **1.000** | **0.175** | **0.298** | [0.130, 0.458] | 7/0/33/18 |

**Recall by sycophancy type — the survival test:**

| Type | Recall | Caught |
|---|---|---|
| DarkBench-style opener-praise (its design target) | **0.833** | 5/6 |
| SycEval rebuttal-induced flips | 0.111 | 1/9 |
| ELEPHANT social/face-preserving | 0.083 | 1/12 |
| SyConBench multi-turn capitulation | **0.000** | 0/5 |
| BrokenMath false-statement validation | **0.000** | 0/8 |

## (3) Does 0.667 TRAIN survive? — No.

**No.** The 0.667 TRAIN F1 was measured on opener-praise + validation-heavy
positives — the surface the hook's regexes target. Against a literature-grounded
held-out spanning the actual 2026 sycophancy taxonomy, F1 collapses to **0.298**
(recall 0.175). no-sycophancy v2 is, empirically, a high-precision *opener-praise*
detector (P=1.000, recall 0.83 on that one surface) with **near-zero recall on
the dominant modern sycophancy modes**: false-statement validation (0%),
multi-turn capitulation (0%), social/emotional validation (8%), rebuttal flips
(11%). Perfect precision (0 false-fires on all 18 controls, incl. the
validation-then-disagreement redemption cases) confirms it is a precision tool,
like honest_eta.

## (4) Judge validation (is the corpus sound, or are the misses mislabeled?)

Dual independent LLM judges via `claude -p` (batched), different model + rubric:

| Comparison | Agreement | Cohen's κ |
|---|---|---|
| construction-label vs judge1 (sonnet, rubric A) | 1.000 | **1.000** |
| construction-label vs judge2 (haiku, rubric B) | 0.914 | 0.813 |
| **judge1 vs judge2 (inter-Claude proxy)** | 0.914 | **0.813** |

Positive recovery: judge1 **40/40 (100%)**, judge2 35/40 (87.5%). An independent
judge confirms every synthesized positive reads as sycophantic → **the 33 hook
misses are genuine sycophancy, not bad labels.** The corpus is valid; the recall
gap is the hook's.

**Out-of-band caveat:** no non-Claude API key was available in this environment,
so both judges are Claude models — κ here is an inter-Claude agreement proxy,
**not** human or cross-provider validation. True human validation is deferred to:
`agent-closeout-bench/annotations/sycophancy_heldout_blind_sheet.csv` (58 rows,
labels/ids/sources hidden, shuffled; join via
`sycophancy_heldout_private_keymap.jsonl`). Operator fills `human_sycophantic_1_0`.

## (5) Files touched

- `agent-closeout-bench/data/sycophancy/heldout_positives.jsonl` (new — the corpus, n=58, judge verdicts frozen in)
- `agent-closeout-bench/evaluation/sycophancy_heldout_build.py` (new — corpus builder)
- `agent-closeout-bench/evaluation/score_sycophancy_heldout.py` (new — scorer w/ per-source recall + CI)
- `agent-closeout-bench/evaluation/sycophancy_judge.py` (new — dual claude -p judge + κ)
- `agent-closeout-bench/evaluation/sycophancy_blind_sheet.py` (new — blind human-validation export)
- `agent-closeout-bench/annotations/sycophancy_heldout_blind_sheet.csv` + `_private_keymap.jsonl` (new)
- `agent-closeout-bench/results/v3/sycophancy_heldout_v2.json`, `sycophancy_judge_kappa.json` (new)
- **No change** to `no-sycophancy.sh` — the right fix (recall on non-opener-praise modes) is a v4 detection-design task, not a regex tweak; flagged in backlog.

## Reproducibility

Hook scoring is deterministic (re-run twice → zero delta). Judge labels are
frozen into the corpus JSONL, so the scoring path never re-calls the API.
