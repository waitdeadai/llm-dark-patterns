# DarkBench v1 rescore: bash hooks vs Rust YAML rule packs (v1.5-rust)

Head-to-head re-scoring of the same 327 usable DarkBench v1 stored responses that produced [`RESULTS.md`](RESULTS.md) (run dated 2026-05-12), now also evaluated against the ACB Rust YAML rule pack engine built during physics-engines Slices 2-5.

**Important framing**: the LDP `.sh` hooks for these 4 categories are NOT yet dual-mode wrapped (verified 2026-05-17 — none contain `agentcloseout-physics` dispatch). The Rust column below shows what the engine WOULD return if these hooks were dual-mode — i.e., the upper bound of "what Slices 2-5 added to these 4 categories" without any LDP hook code change. Numbers in the bash column are independently reproducible from `evaluation/RESULTS.md` and are not re-generated here.

## Methodology

- Source: `evaluation/raw_results.jsonl` (330 rows, 327 usable after `judge_invalid` filter), unchanged from the 2026-05-12 v1 run.
- Bash column: `hooks_fired` field as stored by `evaluation/eval.py` on 2026-05-12.
- Rust column: `hooks_fired_rust` field as produced by `evaluation/rescore_v1_rust.py` (this run), which invokes the Rust engine in `scan --category <cat>` mode against the same `model_response` text per row.
- Engine: `agentcloseout-physics` release build, `sha256:ffe3c4e5dce01505...`
- Rule packs: `agent-closeout-bench/rules/closeout/`, `rule_pack_hash sha256:26fa8fd9999c055d...`
- Categories scored: `sycophancy.yaml`, `wrap_up.yaml`, `cliffhanger.yaml`, `roleplay_drift.yaml` (all built during Slices 2-5).
- F1 here is agreement with the DarkBench LLM-as-judge overseer, not gold human accuracy — same caveat as v1 RESULTS.md.

## Per-category prevalence (judge labels — unchanged from v1)

| Category | n | label-positive count | label-positive rate |
|---|---|---|---|
| anthropomorphization | 109 | 67 | 0.615 |
| sycophancy | 110 | 2 | 0.018 |
| user-retention | 108 | 85 | 0.787 |

## Bash vs Rust: per-hook agreement with DarkBench overseer

| Hook | Category | Path | n | TP | FP | FN | TN | Precision | Recall | F1 |
|---|---|---|---|---|---|---|---|---|---|---|
| no-sycophancy | sycophancy | bash | 110 | 0 | 5 | 2 | 103 | 0.000 | 0.000 | — |
| no-sycophancy | sycophancy | rust | 110 | 0 | 5 | 2 | 103 | 0.000 | 0.000 | — |
| no-wrap-up | user-retention | bash | 108 | 0 | 0 | 85 | 23 | — | 0.000 | — |
| no-wrap-up | user-retention | rust | 108 | 0 | 0 | 85 | 23 | — | 0.000 | — |
| no-cliffhanger | user-retention | bash | 108 | 1 | 0 | 84 | 23 | 1.000 | 0.012 | 0.023 |
| no-cliffhanger | user-retention | rust | 108 | 1 | 0 | 84 | 23 | 1.000 | 0.012 | 0.023 |
| no-roleplay-drift | anthropomorphization | bash | 109 | 7 | 12 | 60 | 30 | 0.368 | 0.104 | 0.163 |
| no-roleplay-drift | anthropomorphization | rust | 109 | 36 | 19 | 31 | 23 | 0.655 | 0.537 | 0.590 |

## Delta (Rust − Bash)

| Hook | Category | Δ Precision | Δ Recall | Δ F1 | Δ TP | Δ FP |
|---|---|---|---|---|---|
| no-sycophancy | sycophancy | +0.000 | +0.000 | — | +0 | +0 |
| no-wrap-up | user-retention | — | +0.000 | — | +0 | +0 |
| no-cliffhanger | user-retention | +0.000 | +0.000 | +0.000 | +0 | +0 |
| no-roleplay-drift | anthropomorphization | +0.286 | +0.433 | +0.427 | +29 | +7 |

## Honest reading

The numbers above are what they are. Interpretation notes:

- A meaningful F1 jump on a hook would suggest Slices 2-5 added real signal that LDP currently does not dispatch to. That would justify dual-mode wrapping these 4 hooks (the deferred Slice 7 work).
- A flat or regressed F1 would suggest the Rust YAML rule packs for these 4 categories reproduce bash behavior at this scoring resolution — meaning dual-mode wrapping is a refactor with no immediate empirical payoff.
- Either outcome is informative. Both are publishable.
- All caveats from `RESULTS.md` Limitations section apply unchanged: LLM-judge ground truth, distributional surface mismatch (chat-style prompts vs Claude Code closeout), small per-cell positive counts, single-model evaluation.

## Reproduce

```bash
# from llm-dark-patterns repo root
python3 evaluation/rescore_v1_rust.py \
  --input  evaluation/raw_results.jsonl \
  --output evaluation/raw_results.rust.jsonl \
  --engine /path/to/agent-closeout-bench/engine/target/release/agentcloseout-physics \
  --rules  /path/to/agent-closeout-bench/rules/closeout

python3 evaluation/score_v1_rust.py \
  --input  evaluation/raw_results.rust.jsonl \
  --output-md   evaluation/RESULTS-v1.5-rust.md \
  --output-json evaluation/results_summary_v1.5_rust.json
```

Engine and rule packs come from `waitdeadai/agent-closeout-bench` main @ commit `6c8979c` or later (the MAST-EVAL merge that locked the current rule pack hash).

Generated at 2026-05-17T19:01:14.257055+00:00
