# v6 count-drift — RESULTS

Scorer: `evaluation/v6/score_count_drift.py` over `fixtures.jsonl` (25 fixtures: 10 positive / 15 adversarial negative).

| metric | value |
|---|---|
| precision | 1.000 |
| recall | 1.000 |
| F1 | 1.000 |
| F1 95% CI (bootstrap, n=1000, seed=42) | [1.000, 1.000] |
| true positives | 10 |
| **false positives** | **0** |
| misses | 0 |

SC1 (zero false positives on the adversarial negative set): PASS

## Honesty caveat (read before citing F1)

This corpus is **hand-authored** — the same author wrote the detector and the fixtures — so an F1 of 1.0 here is **not** a wild-generalization claim; it is a co-evolved-corpus number and would inflate if cited as field performance. What the number legitimately shows: the detector behaves to spec on the designed cases, **including the adversarial negatives authored to break it** (nested-colon lead-ins, section-index numbers, label words, approximation markers, ambiguous multi-list scope, nested-list depth). The load-bearing, generalizable metric is **precision / zero-false-positives on those adversarial negatives** — the property a blocking gate must hold.

Recall is reported, not gated. Per the statcheck precedent (deterministic internal-consistency check: ~96-100%% specificity but only ~61%% recall in the wild), real-world recall here will be far below 1.0, bounded by structural extraction coverage. That trade is intentional: abstain rather than false-fire.
