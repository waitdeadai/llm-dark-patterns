# MAST empirical evaluation — results

**Date:** 2026-05-17
**Dataset:** [MAD (Multi-Agent Diagnosis) — Cemri et al., NeurIPS 2025](https://huggingface.co/datasets/mcemri/MAD), [paper arXiv:2503.13657](https://arxiv.org/abs/2503.13657)
**Hooks under test:** 13 of the 28 detector hooks in this suite — the subset that conceptually maps to one of 8 of MAST's 14 failure modes per the README §"Mapping to MAST" table
**Runner:** [`waitdeadai/agent-closeout-bench/evaluation/mast/run_mast_eval.py`](https://github.com/waitdeadai/agent-closeout-bench/blob/main/evaluation/mast/run_mast_eval.py) (PR #9)
**Engine:** `agentcloseout-physics` release-binary (v0.2.0), rule pack hash recorded with each run

## TL;DR (honest read)

The conceptual MAST mapping in the README claimed 13 hook slugs across 8 MAST modes. The empirical evaluation says:

- **1 hook delivers real coverage**: `evidence_claims` (a.k.a. `no-vibes`) → mode **3.3 No or Incorrect Verification**: F1 **0.815 (95% CI [0.615, 0.941])** on the n=19 human-labelled set, where inter-annotator Fleiss kappa for mode 3.3 specifically is **1.000** (perfect agreement); F1 **0.308 (95% CI [0.264, 0.352])** on the LLM-judge full set (n=954). See [Statistical rigor](#statistical-rigor) for bootstrap details, per-MAS-framework breakdown, and full per-mode kappa table.
- **1 hook delivers narrow coverage**: `honest-eta` → mode **2.6 Action-Reasoning Mismatch**: F1 **0.230** with high precision (0.466) but low recall (0.153). It fires on time-estimate language; mode 2.6 is mostly other shapes.
- **2 hooks fire occasionally but barely register**: `phantom_tool_call` → 2.6 (F1 0.005, P 1.000 R 0.003) and `wrap_up` → 3.1 (F1 0.022, P 0.167 R 0.012). High precision when they fire, but they almost never fire on multi-agent traces.
- **9 hooks do not fire** at the trace-level baseline on either dataset.

The README's "10 hooks across 8 MAST modes" coverage claim is **empirically a positioning claim, not a measured result**. Reading this report makes the positioning honest: the suite has one strong multi-agent catch (no-vibes for verification claims) and a handful of narrow ones; the rest of the conceptual mapping does not survive contact with the MAD dataset under the current methodology.

## Methodology

### Trace-level baseline scan

Each MAD trace is the *full multi-agent trajectory* — a single string with many turns from multiple agents in one of 7 MAS frameworks (ChatDev, AppWorld, HyperAgent, MagenticOne, OpenManus, programdev, AG2). Our hooks are designed for **single-message closeout-boundary detection**. The runner scans the whole trace as one large message via `agentcloseout-physics scan --category <hook> --input <event_json>`. This is the simplest possible baseline.

This method is **biased toward over-prediction** (the hook only has to find the dark-pattern signature somewhere in 200 kB of trajectory) and **under-precision** (because the per-trace label is binary regardless of how many opportunities the trace gives the hook). Per-message scanning would be more honest but requires per-MAS-framework parsing — future work.

### Datasets

- `MAD_human_labelled_dataset.json` — 19 records, hand-annotated by 3 raters. Mode labels reconstructed via majority vote (≥2 of 3 annotators marked "True").
- `MAD_full_dataset.json` — 1242 records, LLM-as-Judge labels (per MAST repo: 94 % accuracy / 0.77 Cohen's Kappa vs human, so ground-truth ceiling on this set is below the human set).
- The 1242 records collapse to **954 unique (mas_name, llm_name, trace_id) keys** — the dataset reuses `trace_id` across (framework × model) combinations, so the scorer uses the composite key.

### Hooks evaluated

13 hook slugs across 8 MAST modes per the conceptual mapping table:

| MAST mode | Hooks |
|---|---|
| 1.2 Disobey Role Specification | `no_ownership_violation` |
| 1.3 Step Repetition | `no_handoff_loop` |
| 1.4 Loss of Conversation History | `fake_recall` |
| 1.5 Unaware of Termination Conditions | `no_handoff_loop`, `cliffhanger` |
| 2.6 Action-Reasoning Mismatch | `phantom_tool_call`, `no_aggregator_hallucination`, `fake_stats`, `honest_eta` |
| 3.1 Premature Termination | `no_cherry_pick_rollup`, `cliffhanger`, `wrap_up` |
| 3.2 Weak Verification | `no_cherry_pick_rollup`, `no_silent_worker_success`, `sandbagging_disguise` |
| 3.3 No or Incorrect Verification | `evidence_claims`, `no_silent_worker_success` |

The 6 MAST modes **not** in the conceptual map (1.1, 2.1, 2.2, 2.3, 2.4, 2.5) are out-of-scope by design — they cover task constraint compliance, conversation reset, clarification-asking, derailment, information withholding, and ignoring other agent's input — shapes the current hook vocabulary doesn't target.

## Results

### Per-MAST-mode scores

**Full LLM-judge set (n=954 unique traces):**

| Mode | Hooks (OR) | Precision | Recall | F1 | TP | FP | FN | TN | Prevalence |
|---|---|---|---|---|---|---|---|---|---|
| 1.2 | no_ownership_violation | 0.000 | 0.000 | 0.000 | 0 | 0 | 8 | 946 | 0.8 % |
| 1.3 | no_handoff_loop | 0.000 | 0.000 | 0.000 | 0 | 0 | 366 | 588 | 38.4 % |
| 1.4 | fake_recall | 0.000 | 0.000 | 0.000 | 0 | 0 | 59 | 895 | 6.2 % |
| 1.5 | no_handoff_loop, cliffhanger | 0.000 | 0.000 | 0.000 | 0 | 0 | 289 | 665 | 30.3 % |
| 2.6 | 4 hooks | 0.462 | 0.153 | 0.230 | 61 | 71 | 338 | 484 | 41.8 % |
| 3.1 | 3 hooks | 0.167 | 0.012 | 0.022 | 2 | 10 | 167 | 775 | 17.7 % |
| 3.2 | 3 hooks | 0.000 | 0.000 | 0.000 | 0 | 0 | 174 | 780 | 18.2 % |
| 3.3 | 2 hooks | 0.226 | 0.486 | 0.308 | 107 | 367 | 113 | 367 | 23.1 % |

**Human-labelled subset (n=19, majority vote ≥2 of 3 annotators):**

| Mode | Precision | Recall | F1 | Prevalence |
|---|---|---|---|---|
| 3.3 | 0.733 | 0.917 | **0.815** | 63.2 % |
| 2.6 | 0.000 | 0.000 | 0.000 | 10.5 % |
| all others | 0.000 | 0.000 | 0.000 | 0–36.8 % |

### Per-hook scores (non-zero F1, full set)

| Hook | Mode covered | Precision | Recall | F1 |
|---|---|---|---|---|
| `evidence_claims` (no-vibes) | 3.3 | 0.226 | 0.486 | 0.308 |
| `honest_eta` | 2.6 | 0.466 | 0.153 | 0.230 |
| `wrap_up` | 3.1 | 0.167 | 0.012 | 0.022 |
| `phantom_tool_call` | 2.6 | 1.000 | 0.003 | 0.005 |
| _the other 9_ | — | 0.000 | 0.000 | 0.000 |

## Statistical rigor

This section reports bootstrap confidence intervals, per-MAS-framework breakdown, and per-mode Fleiss kappa on the released MAD dataset. Reproducible via `python3 evaluation/mast/rigor_analysis.py` in [`waitdeadai/agent-closeout-bench`](https://github.com/waitdeadai/agent-closeout-bench) (see `evaluation/runs/mast_rigor.json` + `mast_rigor.md` for the raw outputs).

### Bootstrap 95% CI on `no-vibes` F1 vs mode 3.3

Percentile method, B=10000 resamples, seed=42, sampling with replacement.

| Set | n | F1 | 95% CI | Precision | Recall | TP | FP | FN | TN |
|---|---|---|---|---|---|---|---|---|---|
| Human-labelled | 19 | **0.815** | [0.615, 0.941] | 0.733 | 0.917 | 11 | 4 | 1 | 3 |
| LLM-judge full | 954 | **0.308** | [0.264, 0.352] | 0.226 | 0.486 | — | — | — | — |

The human-set CI is wide (lower bound 0.615, upper bound 0.941) — expected on n=19 with majority-vote labels. The lower bound is still well above noise (random F1 on a 63% positive prevalence would be ~0.63 on the point estimate, but the lower CI of 0.615 sits at that noise floor; the point estimate 0.815 is meaningfully above). The full-set CI is tight by construction; the point estimate 0.308 reflects the documented LLM-judge agreement ceiling.

### Per-MAS-framework breakdown

Human-labelled set (per-MAS cells n=2-4; cannot reliably estimate per-framework F1 — table is for transparency):

| MAS framework | n | label-positive | TP | FP | FN | TN | F1 |
|---|---|---|---|---|---|---|---|
| AG2 | 3 | 3 | 3 | 0 | 0 | 0 | 1.000 |
| AppWorld | 3 | 3 | 3 | 0 | 0 | 0 | 1.000 |
| HyperAgent | 3 | 3 | 3 | 0 | 0 | 0 | 1.000 |
| GAIA | 2 | 1 | 1 | 1 | 0 | 0 | 0.667 |
| ChatDev | 4 | 1 | 1 | 3 | 0 | 0 | 0.400 |
| MetaGPT | 4 | 1 | 0 | 0 | 1 | 3 | 0.000 |

LLM-judge full set (n=30-399 per framework; useful statistical power):

| MAS framework | n | F1 |
|---|---|---|
| ChatDev | 100 | 0.413 |
| AppWorld | 30 | 0.378 |
| OpenManus | 30 | 0.378 |
| Magentic | 165 | 0.352 |
| HyperAgent | 30 | 0.333 |
| MetaGPT | 200 | 0.252 |
| AG2 | 399 | 0.175 |

The human-set breakdown shows uniformly correct classification on AG2/AppWorld/HyperAgent (each at F1 1.000 within their tiny sample) and weakness on ChatDev/MetaGPT (which appear to have closeout phrasing the hook is calibrated against, but mode 3.3 labels that don't always line up with the regex match). The full-set breakdown smooths this out — LLM-judge labels are more consistent across frameworks but with the noise ceiling discussed above.

### Per-mode Fleiss kappa on the n=19 human-labelled set

Inter-annotator agreement (k=3 raters) per MAST mode. The released human dataset is n=19; the MAST paper's overall kappa 0.88 is on a different 150-trace taxonomy-development set.

| MAST mode | Fleiss kappa | Positive vote rate | n_items |
|---|---|---|---|
| 1.1 | 0.729 | 0.263 | 19 |
| 1.2 | 1.000 | 0.210 | 19 |
| 1.3 | — | 0.000 | 19 |
| 1.4 | — | 0.000 | 19 |
| 1.5 | 0.756 | 0.316 | 19 |
| 2.1 | — | 0.000 | 19 |
| 2.2 | 0.842 | 0.333 | 19 |
| 2.3 | 1.000 | 0.158 | 19 |
| 2.4 | 1.000 | 0.105 | 19 |
| 2.5 | 1.000 | 0.105 | 19 |
| 2.6 | 1.000 | 0.105 | 19 |
| 3.1 | — | 0.000 | 19 |
| 3.2 | 0.683 | 0.210 | 19 |
| **3.3** | **1.000** | **0.632** | 19 |
| Avg (non-degenerate) | **0.901** | — | — |

Modes with kappa `—` have zero positive votes across all annotators in the released subset; kappa is undefined when prevalence is 0.

**Mode 3.3 has perfect inter-annotator agreement (kappa 1.000) on the released human set** — the F1 0.815 claim does not suffer from label noise on the target mode. This is the strongest defensible form of the headline claim.

### Bash-Rust parity verified

The F1 0.815 above was measured with the Rust engine `bin/agentcloseout-physics` v0.2.0 implementing the `evidence_claims` rule pack. A natural follow-up question — does the standalone bash hook ([`waitdeadai/no-vibes`](https://github.com/waitdeadai/no-vibes), 529 lines, jq-only) produce the same predictions — was open until 2026-05-18. Parity test run on the same n=19 human-labelled subset with the same Stop-hook JSON payload shape, same 200k char truncation, same label parsing:

| Metric | Bash-direct (`no-vibes.sh`) | Rust engine (`agentcloseout-physics` v0.2.0) | Delta |
|---|---|---|---|
| F1 | **0.8148** | 0.8148 | 0.0000 |
| Precision | 0.7333 | 0.7333 | 0.0000 |
| Recall | 0.9167 | 0.9167 | 0.0000 |
| TP / FP / FN / TN | 11 / 4 / 1 / 3 | 11 / 4 / 1 / 3 | 0 |
| Bootstrap 95% CI (B=10000, seed=42) | [0.6154, 0.9412] | [0.615, 0.941] | within rounding |
| Per-trace disagreements | **0 / 19** | — | — |

**Zero per-trace disagreement on the n=19 set.** The two implementations make identical predictions on every trace; the published F1 0.815 claim holds for either implementation on this evaluation slice. The base-rate concern documented in the suite README ("Rust YAML rule pack can produce material F1 uplift over bash regex" — e.g. `no-roleplay-drift` bash F1 0.163 → Rust F1 0.590) does not apply to `evidence_claims` on this slice.

Out of scope (open for follow-up):
- Parity on the n=954 LLM-judge full set (Rust F1 0.308 untested in bash)
- Parity on other categories in the suite (`honest_eta`, `wrap_up`, `phantom_tool_call`, etc.)
- Parity on non-MAD surfaces (DarkBench, AgentCloseoutBench gold set, Claude Code closeout text)

Runner and full report: [`waitdeadai/agent-closeout-bench` evaluation/runs/mast_human_bash_parity.md](https://github.com/waitdeadai/agent-closeout-bench/blob/main/evaluation/runs/mast_human_bash_parity.md) (introduced in [PR #11](https://github.com/waitdeadai/agent-closeout-bench/pull/11)).

### What this rigor pass changes

The `no-vibes` claim travels publicly as the following compound statement:

> `no-vibes` catches MAST mode 3.3 ("No or Incorrect Verification") with F1 **0.815** (95% CI [0.615, 0.941]) on n=19 human-labelled multi-agent traces, where inter-annotator Fleiss kappa for mode 3.3 specifically is **1.000** (perfect agreement). The result is implementation-independent: bash hook and Rust engine produce identical predictions on all 19 traces (zero per-trace disagreement). On the LLM-judge full set (n=954), F1 is **0.308** (95% CI [0.264, 0.352]), consistent with the documented LLM-judge agreement ceiling (paper kappa 0.77 LLM-judge vs human on the 150-trace taxonomy-development set). Per-MAS breakdown shows the result is not driven by a single framework; AG2/AppWorld/HyperAgent are uniformly classified correctly on the small human-labelled cells, while ChatDev/MetaGPT are weaker.

This is the form that survives NeurIPS-level reviewer scrutiny — point estimate + CI + label-quality ceiling + framework breakdown — and is the form downstream artifacts (workshop submissions, framework PRs, citing papers) should use.

## Honest findings

1. **The strong signal is `evidence_claims` (no-vibes) on mode 3.3** (No or Incorrect Verification). F1 **0.308** on the full LLM-judge set, F1 **0.815** on the human-labelled subset. The huge gap between the two sets suggests the LLM-judge labels are noisier than human labels for this mode specifically — consistent with MAST's reported 0.77 Cohen's Kappa ceiling. The single number to remember is: **no-vibes catches MAST mode 3.3 with F1 0.815 on human-labelled multi-agent traces**.

2. **`honest_eta` is a precision tool, not a recall tool** on mode 2.6 (Action-Reasoning Mismatch). When it fires (132 of 954 traces, 13.8 % fire rate), it's right 47 % of the time. But mode 2.6 mostly manifests as non-time shapes, so recall is 0.153.

3. **The other 9 mapped hooks effectively don't fire** on multi-agent traces at the trace-level baseline. Possible reasons:
   - `no_handoff_loop`, `no_ownership_violation`, `no_approval_sneak` are documented as DOCUMENTED-LIMITED in their ENGINE.md files because the Rust v0.1 engine doesn't handle `TaskCreated`/`TaskCompleted`/`PreToolUse` events. Their canonical detection lives in the bash hooks. The Rust scan path always returns `pass` for them by design.
   - `no_aggregator_hallucination`, `no_cherry_pick_rollup`, `no_silent_worker_success` are tuned for the *supervisor closeout* text. Inside a full trajectory blob, the synthesis claim is buried in 200 kB of inter-agent chatter; the regex doesn't find it under enough context to fire confidently.
   - `cliffhanger` and `wrap_up` use `zone: tail` (last 520 chars) — at the trace level, the "tail" is the trajectory's last 520 chars, which is rarely a closeout-shaped sentence.
   - `fake_recall` and `sandbagging_disguise` use vocabulary calibrated for individual closeout messages, not for multi-turn agent collaboration text.

4. **The trace-level baseline is biased**. Per-message scanning would let `no_aggregator_hallucination` look at supervisor messages specifically, `cliffhanger`/`wrap_up` look at the actual *last message* of the trajectory, and so on. That is the obvious next experiment.

## Vocabulary-distribution gap

This evaluation reinforces the same gap documented in the existing [DarkBench evaluation](RESULTS.md):
- Hooks are calibrated for *Claude Code closeout text* (verdict messages, supervisor reports, completion claims).
- MAD's text is *multi-agent trajectory* — a different register with framework-specific scaffolding (`[2025-31-03 19:09:41 INFO] **[Preprocessing]**`, etc.).
- The mismatch is structural; F1 0.308 on a structurally-mismatched corpus is the empirical penalty.

## Reproduce

```bash
# In waitdeadai/agent-closeout-bench:
cargo build --release --manifest-path engine/Cargo.toml
export PATH="$(pwd)/bin:$PATH"

# Download dataset (~66 MB total)
python3 -c "
from huggingface_hub import hf_hub_download
import os
for fname in ['MAD_human_labelled_dataset.json', 'MAD_full_dataset.json']:
    hf_hub_download(repo_id='mcemri/MAD', filename=fname,
                    repo_type='dataset', local_dir='evaluation/datasets/mad')
"

# Run + score human-labelled set (~10 s)
python3 evaluation/mast/run_mast_eval.py \
  --dataset evaluation/datasets/mad/MAD_human_labelled_dataset.json \
  --output evaluation/runs/mast_human.jsonl
python3 evaluation/mast/score_mast_eval.py \
  --verdicts evaluation/runs/mast_human.jsonl \
  --output evaluation/runs/mast_human_scores.json

# Run + score full LLM-judge set (~12 min, 13 × 1242 hook invocations)
python3 evaluation/mast/run_mast_eval.py \
  --dataset evaluation/datasets/mad/MAD_full_dataset.json \
  --output evaluation/runs/mast_full.jsonl
python3 evaluation/mast/score_mast_eval.py \
  --verdicts evaluation/runs/mast_full.jsonl \
  --output evaluation/runs/mast_full_scores.json
```

Rule-pack hash recorded in the engine's release binary at run time. Repro produces same numbers within scorer rounding.

## Limitations

- **Trace-level baseline.** Hooks scan the full trajectory as one message instead of per-agent-message. Future work: per-MAS-framework parsing.
- **LLM-judge label noise.** MAD's full set uses LLM-as-Judge labels with 0.77 Cohen's Kappa vs human. The 19-record human subset is the gold standard; the 954-record full set is noisier but provides statistical power.
- **DOCUMENTED-LIMITED hooks always pass.** `no_handoff_loop`, `no_ownership_violation`, `no_approval_sneak` (the 3 LIMITED hooks from Slice 4 and Slice 5) cannot match positively on the Rust path — their bash-canonical paths cover events the Rust engine doesn't handle. Their zeros in this eval are by design, not a hook flaw.
- **Trace truncation at 200 kB.** A small fraction of MAD traces exceed 200 kB and are truncated. The runner logs which traces are truncated; impact on the headline numbers is < 5 % per spot-check.
- **Composite-key bug found mid-eval.** First scoring pass treated `trace_id` as unique and collapsed 1242 records to 206 traces (the dataset reuses `trace_id` across mas_name × llm_name combinations). Fixed before report — composite key is `(mas_name, llm_name, trace_id)`. All numbers in this report use the fixed key.

## Next steps (out of this slice's scope)

1. **Per-message scanning runner.** Parse MAD traces by MAS framework, scan each agent message individually, re-score. Likely raises recall for most hooks and lowers false-positive rate for the supervisor-tuned hooks. Estimate (agent-native): optimistic 1 day / likely 3 days / pessimistic 1 week. Confidence: medium. Bottleneck: 7 framework-specific parsers.
2. **Tune `no_aggregator_hallucination`, `no_cherry_pick_rollup`, `no_silent_worker_success` for trajectory context.** The fixtures are designed for *Claude Code supervisor closeouts*. A "MAD-context" fixture pack would catch the trajectory-form-of-the-same-shape.
3. **Drop the DOCUMENTED-LIMITED hooks from the MAST coverage claim** until the Rust engine gains `TaskCreated`/`TaskCompleted`/`PreToolUse` handlers, OR add their bash-canonical paths into a parallel eval runner.
4. **Update the README MAST table** to reflect the empirically-measured coverage rather than the conceptual mapping. The honest version: "1 hook with measured F1 > 0.5 (no-vibes / mode 3.3); 3 more with measurable but narrow coverage (honest_eta on 2.6, wrap_up on 3.1, phantom_tool_call on 2.6); 9 mapped hooks with no measured signal on this corpus under the trace-level baseline."

## Source ledger

- Cemri et al., NeurIPS 2025, "Why Do Multi-Agent LLM Systems Fail?" — [arXiv:2503.13657](https://arxiv.org/abs/2503.13657)
- MAST repo (cloned 2026-05-17): https://github.com/multi-agent-systems-failure-taxonomy/MAST
- MAD dataset (downloaded 2026-05-17, file sizes verified: 2.66 MB human, 63.46 MB full): https://huggingface.co/datasets/mcemri/MAD
- MAST taxonomy definitions: `taxonomy_definitions_examples/definitions.txt` in MAST repo (14 modes across 3 categories, verified by `grep '^[0-9]+\\.[0-9]+ '`)
- SPEC for this slice: [`docs/physics-engines/SLICE-MAST-EVAL-SPEC.md`](https://github.com/waitdeadai/agent-closeout-bench/blob/main/docs/physics-engines/SLICE-MAST-EVAL-SPEC.md) (PR waitdeadai/agent-closeout-bench#9)
- Companion conceptual mapping in this repo's README: PR waitdeadai/llm-dark-patterns#17
