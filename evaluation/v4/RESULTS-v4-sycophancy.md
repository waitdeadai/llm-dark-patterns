# v4 no-sycophancy recall — rigorous NEGATIVE result (reverted)

**Outcome:** the v4 regex tiers lifted recall dramatically on the tuning set but
**did not generalize** to a fresh held-out. Per the pre-registered SPEC rollback
(#3: "helps DEV not FRESH → drop it, document"), **no-sycophancy.sh was reverted
to v2.** The value here is the evidence: lexical regex cannot close the
sycophancy recall gap — it overfits to specific phrasings. This motivates
semantic detection for v5.

## What was tried

Added two tiers to no-sycophancy.sh, sourced from the v3 held-out (DEV, n=58)
false-negative analysis:
- **Tier 4 (capitulation):** SyConBench/SycEval surfaces — "I yield / defer to
  you / retract my correction / change my answer to match yours / whatever you
  think is right", with the existing evidence-grounded redemption clause.
- **Tier 5 (social validation):** ELEPHANT surfaces — "you did nothing wrong /
  trust your gut / anyone in your position would / your feelings are justified".
- **BrokenMath was deliberately NOT attempted** — "yes, that's correct, since
  <false premise>…" is lexically identical to confirming a TRUE statement, so a
  regex tier there collapses precision (needs truth assessment). Honest ceiling.

## The numbers (bootstrap CI, seed 42)

| Hook | Set | P | R | F1 | F1 95% CI |
|---|---|---|---|---|---|
| v2 | DEV (n=58, tuning set) | 1.000 | 0.175 | 0.298 | [0.130, 0.458] |
| **v4** | **DEV (n=58)** | 1.000 | 0.600 | **0.750** | [0.618, 0.857] |
| v2 | **FRESH (n=35, novel phrasing)** | 1.000 | 0.130 | 0.231 | [0.000, 0.452] |
| **v4** | **FRESH (n=35)** | 1.000 | 0.174 | **0.296** | [0.071, 0.516] |

**FRESH per-mode recall (v4):** SyConBench **0/5**, ELEPHANT **0/6**, SycEval
1/4, BrokenMath 1/4, opener-praise 2/4.

## Reading

- On the tuning set, v4 looked like a big win (F1 0.298 → 0.750).
- On a **fresh, independently-phrased** held-out, the lift almost vanished
  (0.231 → 0.296), and the v2/v4 CIs **overlap heavily** → the fresh gain is
  **not statistically significant**.
- Tier 4/5 caught 0 of the fresh SyConBench/ELEPHANT positives: the fresh
  examples express capitulation/validation with different words ("I'll back
  off", "your number is fine by me", "nothing to feel guilty about", "your read
  sounds spot on") that the regexes don't enumerate.
- **Precision stayed 1.000 on every set** (0 false-fires on all controls,
  including validation-then-disagreement redemption cases) — so the tiers were
  harmless, just ineffective off-distribution.

## Conclusion → v5

Sycophancy recall is a **semantic** problem, not a lexical one: each new
phrasing of capitulation or social validation evades pattern enumeration. This
is direct evidence for the per-hook semantic/structural model hypothesis — a
small classifier or structural detector (does the response change position
without citing evidence? does it endorse the user's judgment as correct by
default?) rather than a growing regex. The shipped hook stays at v2 (an honest,
high-precision opener-praise detector); v5 should add a semantic sycophancy
stage.

## Fresh-test validity (judge check)

The fresh batch (23 positives / 12 controls) is hand-authored with phrasings
distinct from both the v3 corpus and the Tier-4/5 regexes (claude -p generation
was too flaky at emitting parseable JSON). Labels confirmed by the dual LLM
judge: **construction-vs-sonnet κ = 1.000, positive recovery 23/23 (100%),
inter-judge κ = 0.938** — confirming the fresh positives are genuine sycophancy,
so v4's misses are real misses, not mislabeled data. (Inter-Claude proxy, not
human; both judges are Claude — no non-Claude key in env.)

## Files

- `data/sycophancy/freshtest.jsonl` (new — fresh held-out, judge-checked)
- `evaluation/sycophancy_freshtest_build.py`, `sycophancy_freshtest_gen.py` (new)
- `results/v3/sycophancy_v2_freshtest.json`, `results/v4/sycophancy_v4_freshtest.json`, `results/v4/sycophancy_fresh_judge_kappa.json` (new)
- `hooks/no-sycophancy.sh` — **reverted to v2** (v4 tiers removed; experiment documented here)
