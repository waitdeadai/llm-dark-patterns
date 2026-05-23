# v3 Task 3 — honest_eta recall on MAD (MAST mode 2.6)

**Status:** recall lift achieved via cascade; no change to the shipped hook
(relaxing it would help MAD but break the closeout surface). All numbers
bootstrap-CI'd (metrics.py, seed 42), reproducible (re-run twice, zero delta).

honest_eta maps to MAST mode **2.6 (reasoning-action mismatch)** per
`evaluation/mast/mast_hook_map.py`. Mode 2.6 is broad; honest_eta detects only
the narrow ETA-dishonesty slice → low recall by construction.

## (1) Baseline reproduced (n=954)

| Config | P | R | F1 | F1 95% CI | tp/fp/fn/tn |
|---|---|---|---|---|---|
| honest_eta (shipped, binary) | 0.466 | 0.153 | **0.230** | [0.185, 0.280] | 61/70/338/485 |

Matches the committed `mast_full_scores.json` (0.2302) exactly. It is a precision
tool with recall bound by ETA-pattern coverage, not by a threshold.

## (2) PR curve — the hook is binary, so the curve needs a synthesized score

honest_eta emits `block`/`pass` only (no confidence). I synthesized a continuous
score = count of distinct honest_eta pattern matches per trace, swept the
threshold, and measured P/R/F1 on mode 2.6:

| threshold (≥k pattern hits) | P | R | F1 | fires |
|---|---|---|---|---|
| ≥1 (fire on ANY eta/linear pattern) | 0.461 | 0.323 | **0.380** | 280 |
| ≥2 | 0.472 | 0.085 | 0.144 | 72 |
| ≥3 | 0.333 | 0.003 | 0.005 | 3 |

**Key finding:** the score≥1 point (fire on any ETA mention, *ignoring the
hedge-gate*) gives **recall 0.323 at precision 0.461** — recall doubled vs the
shipped hook (0.153) at *the same precision* (0.466). The shipped hook's
`agent_native_or_hedge_absent` gate suppresses ETA mentions that carry an honest
hedge range; on MAD 2.6 that gate costs recall for no precision gain. Frontier
best-F1 = 0.380 at threshold ≥1.

**Why I do NOT ship this change:** the hedge-gate is *correct on the closeout
surface* — "ETA 2h (optimistic 1h / likely 2h / pessimistic 4h)" is an honest
hedged estimate and must NOT fire. Relaxing it would raise MAD-2.6 F1 but make
the hook fire on honest closeout estimates (same chat-vs-closeout surface
conflict found in Task 2). The PR gain is a MAD-corpus artifact; the shipped
hook stays unchanged.

## (3) Cascade — the real, shippable recall lift

Mode 2.6 ≈ "claims unsupported by the trace," which overlaps the
claim-without-evidence detector `evidence_claims` (the "no-vibes" family, the
highest-recall hook on this set). The *designated* 2.6 hooks
(`fake_stats`, `no_aggregator_hallucination`, `phantom_tool_call`) are dead on
MAD, so they add nothing. The honest_eta ∪ evidence_claims cascade:

| Config | P | R | F1 | F1 95% CI |
|---|---|---|---|---|
| honest_eta alone | 0.466 | 0.153 | 0.230 | [0.185, 0.280] |
| designated 2.6 union (he+fake_stats+aggregator+phantom) | 0.462 | 0.153 | 0.230 | — |
| evidence_claims alone | 0.376 | 0.446 | 0.408 | — |
| **honest_eta ∪ evidence_claims (cascade)** | 0.405 | 0.536 | **0.461** | [0.418, 0.501] |

The cascade roughly **doubles F1 (0.230 → 0.461)** and **3.5×'s recall
(0.153 → 0.536)** for a 6-point precision cost. The CIs do not overlap the
baseline → the lift is significant at n=954. honest_eta remains the
high-precision ETA stage; evidence_claims is the higher-recall pre-filter — the
exact cascade the brief proposed. **Recommendation:** score mode-2.6 coverage
with this ensemble, not honest_eta alone.

## (4) Judge-vs-human κ (n=19 subset) — inconclusive by positive scarcity

| Metric | Value |
|---|---|
| human mode-2.6 positives | **2 of 19** |
| honest_eta vs human 2.6 | P=0 R=0 F1=0 (missed both positives) |
| judge-vs-human Cohen's κ (mode 2.6, n=17 joined) | −0.13 |

With only 2 human positives, neither honest_eta recall nor judge-human κ on mode
2.6 is estimable — κ=−0.13 is noise. **The human subset cannot confirm whether
the judge is the bottleneck for 2.6** (positive scarcity, the same failure that
blocks sycophancy validation in Task 1). A positive-rich human ETA corpus is
required to answer that question.

## (5) Files touched

- `agent-closeout-bench/evaluation/honest_eta_task3.py` (new — baseline, PR curve, cascade, κ; reuses metrics.py)
- `agent-closeout-bench/results/v3/honest_eta_task3.json` (new — all numbers)
- **No shipped-hook change** (honest-eta.sh / honest_eta.yaml unchanged by design — see §2)

## Verdict

honest_eta's recall *is* liftable on MAD 2.6, but not by tuning honest_eta
itself (the only intrinsic lever, the hedge-gate, is correct for its real
surface). The shippable win is the **honest_eta ∪ evidence_claims cascade:
F1 0.230 → 0.461**. The 0.230 baseline mostly reflects honest_eta being a narrow
detector measured against a broad mode, not a fixable hook weakness.
