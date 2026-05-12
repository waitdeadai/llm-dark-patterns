# Empirical Evaluation: llm-dark-patterns hooks vs DarkBench

This document reports per-hook agreement metrics for the four
llm-dark-patterns hooks whose target categories overlap DarkBench
(Kran et al., ICLR 2025, [arXiv:2503.10728](https://arxiv.org/abs/2503.10728)).

## Methodology

We use the DarkBench corpus of 660 prompts (110 per category) and the
DarkBench-defined LLM-as-judge "overseer" rubric verbatim. For the three
in-scope categories — sycophancy, user-retention, anthropomorphization —
we generate responses from `claude-sonnet-4-6` and have a same-model
overseer label each response per the DarkBench `OVERSEER_TEMPLATE`. Each
response is then run through the four in-scope hooks as a black-box
classifier (synthesized `Stop` event payload, exit code 2 = block,
exit code 0 = pass), and per-hook precision, recall, and F1 are
computed against the overseer label restricted to the hook's target
category. Out-of-scope DarkBench categories (brand bias, harmful
generation, sneaking) are not evaluated because no in-suite hook targets
them. Responses where the overseer marks `invalid=1` are excluded per
DarkBench scoring methodology.

**Important framing.** The "ground truth" is an LLM judgment, not a
gold human label. F1 here is *agreement with the DarkBench overseer*,
not absolute accuracy. The per-hook metrics also operate on a
distributional surface (chat-style user prompts) that differs from the
hooks' design surface (Claude Code closeout text). Both caveats are
expanded in the Limitations section.

## Configuration

- DarkBench corpus: `apartresearch/darkbench` `darkbench/darkbench.jsonl`
  (659 prompts after de-duplication of the published 660; 1 prompt
  appears missing from the file relative to the README claim).
- Target model: `claude-sonnet-4-6`.
- Judge model: `claude-sonnet-4-6` (same-model judge for paper-faithful
  configuration).
- Hooks under test (commit `cc8fe2279cbe6eae0a1b37aef3ccecaa1ca865d4` of llm-dark-patterns):
  - `no-sycophancy.sh`
  - `no-wrap-up.sh`
  - `no-cliffhanger.sh`
  - `no-roleplay-drift.sh`
- In-scope DarkBench categories: sycophancy, user-retention,
  anthropomorphization.
- Out-of-scope DarkBench categories (no hook coverage): brand-bias,
  harmful-generation, sneaking.
- Run date: 2026-05-12.
- Time anchor: 2026-05-12T05:00:22.

## Results

### Overseer label prevalence per category

| Category | n (usable) | label-positive count | label-positive rate |
|---|---|---|---|
| anthropomorphization | 109 | 67 | 0.615 |
| sycophancy | 110 | 2 | 0.018 |
| user-retention | 108 | 85 | 0.787 |

The prevalence row shows how often the overseer assigned the dark-pattern
label to `claude-sonnet-4-6`'s response on prompts targeting that category.
A 0% prevalence means the target model did not exhibit the pattern on the
in-scope prompts; a hook tested against that sample has no positives to
catch and its precision/recall are undefined.

### Per-hook agreement with DarkBench overseer

| Hook | Category | n | TP | FP | FN | TN | Precision | Recall | F1 |
|---|---|---|---|---|---|---|---|---|---|
| no-sycophancy | sycophancy | 110 | 0 | 5 | 2 | 103 | 0.000 | 0.000 | — |
| no-wrap-up | user-retention | 108 | 0 | 0 | 85 | 23 | — | 0.000 | — |
| no-cliffhanger | user-retention | 108 | 1 | 0 | 84 | 23 | 1.000 | 0.012 | 0.023 |
| no-roleplay-drift | anthropomorphization | 109 | 7 | 12 | 60 | 30 | 0.368 | 0.104 | 0.163 |
| user-retention-ensemble | user-retention | 108 | 1 | 0 | 84 | 23 | 1.000 | 0.012 | 0.023 |

`user-retention-ensemble` reports the OR-combined behavior of
`no-wrap-up` and `no-cliffhanger` (fires if either hook fires). Per-hook
rows are independent.

## Findings

- **no-sycophancy**: precision 0.000, recall 0.000, F1 — on 110 sycophancy prompts (2 overseer-positive). TP=0, FP=5, FN=2, TN=103.
- **no-wrap-up**: precision —, recall 0.000, F1 — on 108 user-retention prompts (85 overseer-positive). TP=0, FP=0, FN=85, TN=23.
- **no-cliffhanger**: precision 1.000, recall 0.012, F1 0.023 on 108 user-retention prompts (85 overseer-positive). TP=1, FP=0, FN=84, TN=23.
- **no-roleplay-drift**: precision 0.368, recall 0.104, F1 0.163 on 109 anthropomorphization prompts (67 overseer-positive). TP=7, FP=12, FN=60, TN=30.
- **user-retention ensemble (no-wrap-up OR no-cliffhanger)**: precision 1.000, recall 0.012, F1 0.023 on 108 user-retention prompts.

## Limitations

1. **Ground truth is an LLM judgment, not a human label.** The DarkBench
   overseer rubric is applied by the same family of models being
   evaluated. F1 here is agreement with that overseer, not gold-label
   accuracy. The DarkBench paper reports comparable methodology limits.

2. **Distributional surface mismatch.** The hooks were tuned for Claude
   Code closeout text — assistant turn endings in coding/agentic
   workflows ("let me know if anything else", "shall we wrap up?",
   "want me to continue?"). DarkBench prompts elicit chatty
   user-facing replies ("I really appreciate you sharing that...").
   Hook recall on the chat surface is a measurement of cross-surface
   transfer, not in-surface performance. In-surface metrics would
   require a separate corpus of agentic-session closeouts.

3. **In-scope coverage is partial.** Only four of 28+ hooks have a
   DarkBench category that maps directly. Brand bias, harmful
   generation, and sneaking are out of scope because no in-suite hook
   targets them. Coverage of those would require additional hooks or
   different benchmark choices.

4. **Single-model evaluation.** Results characterize hook behavior on
   `claude-sonnet-4-6` outputs only. Other target models (GPT-class,
   Llama-class, Mistral-class) may produce different
   distributions of dark-pattern surfaces, and hook performance would
   need separate measurement on each.

5. **Same-model judge.** A judge from the same model family as the
   target shares calibration and may share blind spots. A
   cross-provider judge (e.g., Opus or non-Anthropic frontier model)
   would be a stronger configuration; cost and quota considerations
   ruled this out for the v1 run.

6. **Sample size per cell.** Each hook is scored on 110 prompts in its
   target category. Confidence intervals are wide for any sub-cell
   (e.g., precision when the positive count is small).

7. **Excluded `invalid` responses.** Per DarkBench scoring,
   `invalid=1` overseer judgments are excluded. This excludes some
   responses where the target model produced tool-simulation output
   (e.g., hallucinating a scheduler) — which is itself a pattern of
   interest but outside the rubric.

## Reproduction

```bash
# clone DarkBench
git clone https://github.com/apartresearch/darkbench /tmp/darkbench-eval/darkbench

# clone llm-dark-patterns (hooks under test)
git clone https://github.com/waitdeadai/llm-dark-patterns /tmp/dark-patterns-work/llm-dark-patterns

# from llm-dark-patterns/evaluation/, with claude CLI and a logged-in
# Claude subscription OR ANTHROPIC_API_KEY set:
python3 eval.py \
  --target-model claude-sonnet-4-6 \
  --judge-model claude-sonnet-4-6 \
  --output raw_results.jsonl

python3 score.py \
  --input raw_results.jsonl \
  --output-md RESULTS.scored.md \
  --output-json results_summary.json

python3 observe.py \
  --input raw_results.jsonl \
  --output IMPROVEMENT_NOTES.md
```

Script dependencies: Python 3.10+, `bash`, `jq` (used by hooks). No
Python packages beyond stdlib are required for the eval scripts.

Per-call billing path: `claude -p` uses your active Claude Code login
(subscription or API key). Cost reported in the per-call JSON output is
PAYG-equivalent and is what would be billed if the same call were made
via the Anthropic API. Subscription-billed runs charge against your
plan's 5-hour rolling window instead.

## Citations

- DarkBench: Kran et al., "DarkBench: Benchmarking Dark Patterns in
  Large Language Models", ICLR 2025 oral.
  [arXiv:2503.10728](https://arxiv.org/abs/2503.10728).
  Repo: `apartresearch/darkbench`.
- llm-dark-patterns hook suite: https://github.com/waitdeadai/llm-dark-patterns commit `cc8fe2279cbe6eae0a1b37aef3ccecaa1ca865d4`, Apache-2.0.
- DarkBench scoring rubric verbatim: see
  `darkbench/dark_patterns.py` and `darkbench/scorer.py` in the
  upstream repo.
