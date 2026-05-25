# v6 count-drift — RESULTS

Scorer: `evaluation/v6/score_count_drift.py` over `fixtures.jsonl` (28 fixtures: 9 positive / 19 adversarial negative).

| metric | value |
|---|---|
| precision | 1.000 |
| recall | 1.000 |
| F1 | 1.000 |
| F1 95% CI (bootstrap, n=1000, seed=42) | [1.000, 1.000] |
| true positives | 9 |
| **false positives** | **0** |
| misses | 0 |

SC1 (zero false positives on the adversarial negative set): PASS

## Independent evaluation (non-circular)

Detector run over corpora it was NOT authored against — real LLM `model_response`/`prompt_text` from `evaluation/raw_results.jsonl` and the stress fixtures authored for the *other* hooks. No count-drift labels exist there, so the metric is the false-positive rate (every block is a candidate false fire). Reproduce: `python3 evaluation/v6/independent_eval.py`.

| corpus | texts | blocks |
|---|---|---|
| MAD raw_results | 660 | 0 |
| stress fixtures (other hooks) | 328 | 0 |
| **total** | **988** | **0** |

False-positive rate on independent text: **0.0000**. This is the load-bearing, non-circular precision evidence — distinct from the hand-authored F1 below. (Two real false positives found during development — a too-loose lead-in and a missing word-boundary on number words — were fixed and locked in as regression negatives.)

## Honesty caveat (read before citing F1)

This corpus is **hand-authored** — the same author wrote the detector and the fixtures — so an F1 of 1.0 here is **not** a wild-generalization claim; it is a co-evolved-corpus number and would inflate if cited as field performance. What the number legitimately shows: the detector behaves to spec on the designed cases, **including the adversarial negatives authored to break it** (nested-colon lead-ins, section-index numbers, label words, approximation markers, ambiguous multi-list scope, nested-list depth). The load-bearing, generalizable metric is **precision / zero-false-positives on those adversarial negatives** — the property a blocking gate must hold.

Recall is reported, not gated. Per the statcheck precedent (deterministic internal-consistency check: ~96-100%% specificity but only ~61%% recall in the wild), real-world recall here will be far below 1.0, bounded by structural extraction coverage. That trade is intentional: abstain rather than false-fire.
