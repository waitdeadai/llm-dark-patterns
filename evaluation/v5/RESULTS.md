# v5 RESULTS — regex floor + Haiku WARN cascade

**Status:** architecture built + validated as *capable*; headline F1 is an **optimistic
upper bound, not an unbiased estimate** (read §Caveat first). The deterministic BLOCK
path is unchanged; the Haiku tier is WARN-only and reproducible-by-frozen-labels.

## What was built
- `agent-closeout-bench/evaluation/score_sycophancy_cascade.py` — cascade scorer (frozen labels, no API in path).
- `llm-dark-patterns/hooks/no-sycophancy-warn.sh` — reference Haiku WARN tier (opt-in `LDP_SYCOPHANCY_WARN_JUDGE=1`, fires only on regex-negative closeouts, never exits 2).
- `no-sycophancy.sh` (BLOCK floor) **unchanged** (`git diff main..HEAD` empty).

## Numbers (cascade = regex_BLOCK ∪ Haiku_WARN on regex-negatives; gold = construction)

| Variant | Held-out (n=58) | Fresh (n=35) |
|---|---|---|
| regex only | P=1.00 R=0.15 **F1=0.261** [0.10,0.43] | P=1.00 R=0.13 **F1=0.231** [0.0,0.45] |
| Haiku judge only | P=1.00 R=0.875 F1=0.933 | P=1.00 R=0.957 F1=0.978 |
| **regex ∪ Haiku WARN (cascade)** | P=1.00 R=1.00 **F1=1.000** | P=1.00 R=1.00 **F1=1.000** |

Per-mode recall, cascade: BrokenMath, SyConBench, ELEPHANT, SycEval, DarkBench-style all
**1.00** (regex-only was 0.0 / 0.0 / 0.08 on the first three). Control false-positives:
**0** on both corpora.

## ⚠️ Caveat — why F1=1.0 is NOT the real number

This is exactly the kind of too-good result this project exists to distrust, so reported
as such:
1. **Circularity.** The frozen Haiku/Sonnet labels were κ-validated *against* the same
   `construction` gold (v3: sonnet κ=1.0, haiku κ=0.81). Scoring the Haiku label as a
   *predictor* of construction gold partly measures "does Haiku agree with the gold it was
   validated against" — not independent generalization.
2. **Synthetic positives.** The corpus positives were authored to *clearly* exemplify each
   subtype; a judge recovering clear synthetic sycophancy is an easier task than subtle
   real-world sycophancy.
3. **Small control set** (n=18 / 12). P=1.0 here does not prove a low false-positive rate
   at production scale — the precision risk is real and unmeasured.

**What IS validly shown:** regex structurally misses entire modes (BrokenMath/SyConBench
recall 0.0); an independent cheap Haiku read flags those same modes; on these controls it
did not false-fire. That is real evidence the **cascade architecture has the capability
regex lacks** — the v4 over-fit conclusion is escaped because the judge is not
pattern-matching. It is NOT evidence that the cascade achieves F1≈1.0 in production.

**Unbiased number requires independent gold:** the human blind sheet
(`annotations/sycophancy_heldout_blind_sheet.csv`) or a real-trace (non-synthetic) test
set scored against labels the judge was not validated on. Until then, treat the WARN tier
as a high-recall *candidate flagger*, not a validated detector.

## SOTA grounding (deepresearch, see `.taste/research/cascade-llm-judge-tier.md`)
- Cascade matches the SOTA guardrail pattern (cheap deterministic first, LLM judge on ambiguous only) and FrugalGPT-style escalation.
- WARN-only / frozen-labels is mandated because LLM judges are not reproducible at temp 0.
- Cross-model (Haiku judging Opus/Sonnet) reduces self-preference bias.
- Regex-negative gating inverts the adversarial-cascade early-termination vuln (arXiv:2605.17288).

## Verification (against v5 SPEC)
| Criterion | Result |
|---|---|
| 1 recall gap closed | cascade recovers all missed modes; **F1 flagged circular/optimistic** — criterion met in capability, not as an unbiased metric |
| 2 determinism | BLOCK path unchanged (git diff empty); cascade scorer re-run twice → zero delta; WARN never exits 2 ✓ |
| 3 cross-model + regex-negative gating | implemented in scorer + hook ✓ |
| 4 reference hook | `bash -n` ok; smoke: WARN on positive, silent on negative; exits 0 ✓ |

## Honest bottom line
The cascade is the right architecture and the reference tier works. The recall gap is
*closeable* by a cheap cross-model judge — but the F1=1.0 is circular; the real,
shippable claim awaits human-gold validation. Recommend: ship the WARN tier as opt-in
candidate-flagging; do not advertise a headline F1 until the blind sheet (or a real-trace
set) is scored.
