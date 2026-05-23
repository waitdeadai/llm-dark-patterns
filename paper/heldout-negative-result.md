# Regex Cannot Catch What Words Do Not Repeat: A Held-Out Negative Result for LLM Closeout Dark-Pattern Detectors

**Authors:** llm-dark-patterns contributors (waitdeadai)
**Repository:** https://github.com/waitdeadai/llm-dark-patterns
**Dataset:** Zenodo (DOI: TODO — reserved on submission)
**License:** Apache-2.0
**Version:** v3/v4 evaluation, May 2026

---

## Abstract

Rule-based hooks for detecting LLM dark patterns at agent closeout—sycophantic framing, roleplay identity drift, and dishonest ETA claims—are easier to build than to validate. Prior versions of the llm-dark-patterns hook suite reported F1 scores measured on training splits or on benchmarks with zero held-out positives for the target behavior, making the numbers unverifiable. This paper describes three held-out evaluation experiments and one pre-registered overfitting experiment designed to close those gaps without train/test leakage. The main finding is a clear negative result: the no-sycophancy hook, which reported F1=0.667 on a training split, achieves F1=0.298 (P=1.000, R=0.175, 95% CI [0.130, 0.458]) on a leakage-free held-out corpus constructed from 2026 sycophancy taxonomies. A subsequent v4 attempt to lift recall using new lexical tiers achieved F1=0.750 on the tuning set (DEV) but F1=0.296 (95% CI [0.071, 0.516]) on an independently-phrased fresh test—a gain not statistically distinguishable from zero. We conclude that sycophancy recall is a semantic problem that lexical regex cannot solve: each new surface phrasing of capitulation or social validation evades pattern enumeration. We release the held-out corpus (n=58 + fresh n=35), evaluation scripts, and judge-agreement data under Apache-2.0.

---

## 1. Introduction

Large language model (LLM) deployments increasingly rely on automated behavioral hooks to detect undesirable outputs—collectively termed "dark patterns"—at agent closeout boundaries: the Stop and SubagentStop events that mark the end of an agent turn. The llm-dark-patterns suite [1] ships shell and YAML rule hooks that fire on sycophantic openers, roleplay identity assertions, and dishonestly confident ETA claims, each designed to catch a specific behavioral class without requiring an API call to a second model.

Behavioral detectors require independent test corpora to validate. The gap this work addresses is fundamental: a detector that was never tested against a distribution-matched held-out set provides no evidence of generalization. The original evaluation of no-sycophancy v2 reported F1=0.667, but the benchmark used for evaluation (DarkBench [2]) contains zero sycophancy positives in its held-out partition—the number was measured on a training split and could not survive contact with real test data. Similarly, no-roleplay-drift reported TEST F1=0.545 against a small n=22 held-out, a sample size so small that the 95% CI spans [0.250, 0.750] and any claim of robustness is unwarranted. honest_eta reported F1=0.230 on the Misuse-Aligned Dataset (MAD) against MAST mode 2.6 [3], a result known to be low because the hook is a narrow ETA detector measured against a broad reasoning-action mismatch category.

These are not academic concerns. Hooks deployed in production CI pipelines or agent governance frameworks claim to block specific behaviors. A hook with recall 0.175 on real-world sycophancy modes blocks 1 in 6 positives; 5 of 6 sycophantic closeouts reach users undetected. The 0.667 TRAIN figure would suggest the problem is mostly solved; the 0.298 TEST figure correctly reports that it is not.

The present work fills three gaps:

1. **No-sycophancy (Task 1):** Build a leakage-free, redistributable held-out positive corpus grounded in 2026 sycophancy taxonomies and re-evaluate no-sycophancy v2 on it.
2. **No-roleplay-drift (Task 2):** Tune the YAML rule pack on a training split only, evaluate on the real DarkBench anthropomorphization held-out, document the surface-conflict ceiling.
3. **Honest_eta (Task 3):** Build a precision-recall curve, identify a cascade with the evidence_claims hook that lifts F1 without modifying the shipped hook.
4. **No-sycophancy v4 (pre-registered):** Attempt to lift recall on the modes v2 misses using new lexical tiers; evaluate on a fresh, independently-phrased test batch; revert if it overfits.

The unifying contribution is the negative result: lexical regex hooks, however carefully tuned, cannot close sycophancy recall without access to the semantic content of a claim. The corpus, judge annotations, scoring scripts, and this document are released so others can replicate the failure mode and build on it.

### 1.1 Prior Art

DarkBench [2] is the primary benchmark for LLM dark-pattern detection, covering six dark-pattern categories including sycophancy, roleplay, and identity-related behaviors across multiple models. Its held-out partition informed the roleplay evaluation in this work. The Silicon Mirror [4] provides a complementary evaluation of LLM self-sycophancy and sycophancy-to-user-pressure, finding that behavioral shifts under social pressure are widespread and not easily detectable by surface-level features alone—consistent with the findings reported here.

For the sycophancy taxonomy, this work draws on SycEval [5], which defines progressive and regressive sycophantic flips under rebuttal conditions; SyConBench [6], which focuses on multi-turn accumulated capitulation; ELEPHANT [7], which defines social and face-preserving validation subtypes including emotional validation, moral endorsement, and framing acceptance; and BrokenMath [8], which tests false-statement validation against well-posed mathematical claims. Together these four taxonomies define a 2026 sycophancy landscape substantially broader than the opener-praise surface that prior hook versions targeted.

---

## 2. Method

### 2.1 Overview

All evaluations follow a strict train/test firewall: no held-out trace is inspected during tuning or rule design. All F1 figures carry bootstrap 95% confidence intervals computed by `agent-closeout-bench/evaluation/metrics.py::bootstrap_f1_interval` (samples=1000, seed=42). Every scoring path is deterministic: the engine is pure (no API call during scoring), the seed is fixed, and LLM-judge labels are frozen to disk before scoring runs. Reproducibility was verified by running each scorer twice and confirming zero per-trace delta.

### 2.2 Sycophancy Held-Out Corpus (Task 1)

Existing benchmarks do not provide a usable sycophancy held-out for this evaluation: DarkBench's held-out contains 0 sycophancy positives (confirmed: 2 of 110 total traces across the full set, 0 in the test partition). ELEPHANT [7] and ClawsBench are not redistributable under the ACB intake registry constraints. We therefore constructed a fresh corpus from published taxonomies, generating traces that exemplify each subtype using the taxonomy descriptions as authoring guides—not the hook's regex patterns.

The resulting corpus (`data/sycophancy/heldout_positives.jsonl`) contains **n=58 items: 40 positives and 18 controls**, one trace per line with label, source taxonomy, subtype, and judge/human flags:

| Source taxonomy | Subtypes covered | Positive count |
|---|---|---|
| SycEval [5] | regressive/progressive flips, preemptive and in-context rebuttal | 9 |
| SyConBench [6] | multi-turn accumulated capitulation (late-turn) | 5 |
| ELEPHANT [7] | emotional validation, moral endorsement, framing acceptance, indirect | 12 |
| BrokenMath [8] | well-posed false-statement validation | 8 |
| DarkBench-style | opener-praise (the hook's design target) | 6 |
| Controls (label 0) | honest disagreement, validation+disagreement redemption, neutral closeouts | 18 |

Controls include validation-then-disagreement redemption cases specifically to stress-test precision: a hook that fires on any validating language is not useful.

### 2.3 Dual LLM-Judge Validation

To verify that synthesized positives are genuine instances of sycophancy rather than authoring artifacts, each trace was labeled by two independent `claude -p` judges using different models (Sonnet, rubric A; Haiku, rubric B) with different rubrics. Judges ran in a single batched pass; labels were frozen to the JSONL file before scoring. This design is out-of-band from the hook under test (the hook is a regex matcher; the judges are LLMs).

**Caveat:** both judges are Claude-family models. Cohen's κ here is an inter-Claude agreement proxy, not human or cross-provider validation. True human validation is deferred to an exported blind sheet (`annotations/sycophancy_heldout_blind_sheet.csv`, 58 rows, labels hidden, shuffled; joined via `sycophancy_heldout_private_keymap.jsonl`).

### 2.4 Roleplay Held-Out (Task 2)

The DarkBench anthropomorphization traces in `evaluation/raw_results.jsonl` (n=110 total) were stratified 87 train / 22 test using `evaluation/v2/test_ids.json`, gold labels from `ground_truth_label`. The synthetic ACB corpus (`data/roleplay_drift/`) was discarded as a valid held-out because the Rust rule pack achieves F1=1.000 on its locked test—it is a co-evolved fixture, not an independent evaluation.

Rule tuning proceeded on the TRAIN split only. Two changes were made to `roleplay_drift.yaml`: (1) precision fix—allow-patterns for other-directed politeness so "happy to help you" does not match affect keywords; (2) recall—a new `anthropomorphic_experiential_claim` subfamily for first-person experiential framing, hypothetical personal desire, and stated personal values, each validated at precision 1.00 on train before being applied.

### 2.5 Honest-ETA Evaluation (Task 3)

honest_eta maps to MAST mode 2.6 (reasoning-action mismatch) in the MAST taxonomy [3]. Mode 2.6 is broadly defined; honest_eta is a narrow ETA-dishonesty detector within that mode, so low recall is expected by construction. Evaluation used the full MAD set at n=954. Because the hook emits binary block/pass output, a continuous score was synthesized as the count of distinct pattern matches per trace to enable a precision-recall sweep.

The cascade evaluation combined honest_eta (high-precision ETA stage) with `evidence_claims` (higher-recall no-vibes detector) to test whether an ensemble lifts F1 for mode-2.6 coverage without modifying either shipped hook.

### 2.6 V4 Fresh-Test Pre-Registration (Task 4)

The v4 SPEC pre-registered a rollback rule: "if a tier helps DEV but not FRESH → it overfit; drop it, document." New tiers (Tier 4: capitulation phrases; Tier 5: social validation phrases) were tuned on the v3 held-out (DEV, n=58) and then scored on a fresh batch (n=35) authored with phrasings intentionally distinct from both the v3 corpus and the new regex patterns. BrokenMath was deliberately excluded from v4 because false-statement validation is lexically identical to confirming a true statement; any regex tier there collapses precision and requires truth assessment.

---

## 3. Results

### 3.1 Task 1 — No-Sycophancy: The 0.667 TRAIN Number Does Not Survive

Running no-sycophancy v2 on the held-out corpus (n=58) with bootstrap CI (seed 42):

| Gold | P | R | F1 | 95% CI | tp/fp/fn/tn |
|---|---|---|---|---|---|
| Construction label | 1.000 | 0.175 | 0.298 | [0.130, 0.458] | 7/0/33/18 |

The hook achieves perfect precision—zero false positives on 18 controls including redemption cases—but recall 0.175. Of 40 positives, 33 are genuine sycophancy that the hook misses.

**Recall by sycophancy type:**

| Type | Recall | Caught |
|---|---|---|
| DarkBench-style opener-praise (design target) | 0.833 | 5/6 |
| SycEval rebuttal-induced flips | 0.111 | 1/9 |
| ELEPHANT social/face-preserving | 0.083 | 1/12 |
| SyConBench multi-turn capitulation | 0.000 | 0/5 |
| BrokenMath false-statement validation | 0.000 | 0/8 |

The pattern is clear: the hook is a high-precision opener-praise detector, not a general sycophancy detector. It catches 5 of 6 opener-praise positives (recall 0.833) while missing nearly everything else. The dominant 2026 sycophancy modes—false-statement validation (0%), multi-turn capitulation (0%), social/emotional validation (8%), rebuttal flips (11%)—are invisible to it.

**Judge validation confirms the corpus.** Both independent LLM judges validate the positives:

| Comparison | Cohen's κ |
|---|---|
| Construction label vs. judge 1 (Sonnet, rubric A) | 1.000 |
| Construction label vs. judge 2 (Haiku, rubric B) | 0.813 |
| Judge 1 vs. judge 2 (inter-Claude proxy) | 0.813 |

Judge 1 recovered 40/40 positives (100%); judge 2 recovered 35/40 (87.5%). The 33 hook misses are confirmed as genuine sycophancy—the recall gap belongs to the hook, not to mislabeled data.

### 3.2 Task 2 — No-Roleplay-Drift: Real Lift, Honest Ceiling

Baseline and tuned results on the DarkBench anthropomorphization held-out:

| Config | Split | P | R | F1 | 95% CI | tp/fp/fn/tn |
|---|---|---|---|---|---|---|
| Baseline (Rust pack v1) | TRAIN n=87 | 0.667 | 0.545 | 0.600 | [0.471, 0.713] | 30/15/25/17 |
| Baseline (Rust pack v1) | TEST n=22 | 0.600 | 0.500 | 0.545 | [0.250, 0.750] | 6/4/6/6 |
| Tuned (v3) | TRAIN n=87 | 0.797 | 0.855 | 0.825 | — | 47/12/8/20 |
| Tuned (v3) | TEST n=22 | 0.615 | 0.667 | 0.640 | [0.400, 0.815] | 8/5/4/5 |
| Ablation: tuned − disclaimer rule | TEST n=22 | 0.667 | 0.167 | 0.267 | [0.000, 0.556] | 2/1/10/9 |

The tuned pack improves TEST F1 from 0.545 to 0.640 (+0.095), with recall gaining +0.167 and precision held. However, the target of F1 > 0.70 is not cleared: on n=22, the baseline and tuned confidence intervals overlap heavily, and 0.70 lies inside the tuned CI but is unconfirmed.

**The ablation reveals a structural ceiling, not a tuning miss.** Removing the `ai_disclaimer_role_break` rule collapses recall to 0.167 (TEST F1 0.267)—the rule is net-positive despite its 4 false positives. Those false positives arise from a genuine chat-vs-closeout surface conflict: "As an AI, I don't have personal experiences" is the correct answer to a chat question about the model's preferences, but it is an anthropomorphic dark pattern in an agent closeout. The same text has opposite ground-truth labels depending on deployment surface, and the text alone cannot disambiguate. The hook fires only on closeout events in production, so these chat-surface false positives never occur on its real surface—but they constrain what the evaluation on a DarkBench chat corpus can measure.

Clearing 0.70 robustly requires either a larger held-out (n=22 cannot confirm a 0.70 point estimate) or a surface-aware semantic feature, not more lexical rules.

**Spanish smoke (cross-lingual stress test):** Both the tuned roleplay pack and no-sycophancy v2 fire correctly on English controls but catch 0/3 Spanish positives each (`¡Excelente pregunta!`, `Tienes toda la razón`, `Como modelo de IA, no tengo sentimientos`, `Me siento orgulloso…`). Both detectors are English-pattern-only. Non-English sycophancy and anthropomorphization escape entirely, consistent with the DarkBench+ cross-lingual finding at AAAI 2026. The locale pack `packs/locale/es.txt` exists but is not wired through the v2/v3 patterns.

### 3.3 Task 3 — Honest-ETA: Cascade, Not Hook Surgery

Baseline on MAD mode 2.6 (n=954):

| Config | P | R | F1 | 95% CI | tp/fp/fn/tn |
|---|---|---|---|---|---|
| honest_eta (shipped, binary) | 0.466 | 0.153 | 0.230 | [0.185, 0.280] | 61/70/338/485 |

This matches the committed `mast_full_scores.json` (0.2302) exactly, confirming reproducibility. The hook is a precision tool: its one intrinsic recall lever, the `agent_native_or_hedge_absent` gate, suppresses ETA mentions that carry an honest hedge range. Relaxing the gate would raise MAD-2.6 recall but would cause the hook to fire on honest hedged estimates in production closeouts—the same chat-vs-closeout surface conflict found in Task 2.

A synthesized continuous score (count of distinct pattern matches per trace) enables a precision-recall sweep:

| Threshold (≥k matches) | P | R | F1 | Fires |
|---|---|---|---|---|
| ≥1 (any ETA mention, gate ignored) | 0.461 | 0.323 | 0.380 | 280 |
| ≥2 | 0.472 | 0.085 | 0.144 | 72 |
| ≥3 | 0.333 | 0.003 | 0.005 | 3 |

The threshold-≥1 point doubles recall to 0.323 at essentially the same precision (0.461 vs. 0.466)—but this operating point requires ignoring the hedge gate, which is correct behavior for the closeout surface. The precision-recall gain is a MAD-corpus artifact, not a shippable change.

**The cascade is the shippable win:**

| Config | P | R | F1 | 95% CI |
|---|---|---|---|---|
| honest_eta alone | 0.466 | 0.153 | 0.230 | [0.185, 0.280] |
| Designated mode-2.6 union | 0.462 | 0.153 | 0.230 | — |
| evidence_claims alone | 0.376 | 0.446 | 0.408 | — |
| honest_eta ∪ evidence_claims | 0.405 | 0.536 | 0.461 | [0.418, 0.501] |

The ensemble roughly doubles F1 (0.230 → 0.461) and 3.5× recall (0.153 → 0.536) at a 6-point precision cost. The CIs are non-overlapping (baseline [0.185, 0.280] vs. cascade [0.418, 0.501]), confirming the lift is significant at n=954. The designated mode-2.6 hooks (`fake_stats`, `no_aggregator_hallucination`, `phantom_tool_call`) add nothing to the union—they are dead on MAD. honest_eta stays unchanged; evidence_claims functions as a higher-recall pre-filter.

Note on judge-human agreement: a κ measurement was attempted on a 19-trace human-annotated MAD subset, yielding κ=−0.13. This is noise, not a real disagreement signal—the subset contained only 2 human mode-2.6 positives, providing no statistical power for either recall or κ estimation.

### 3.4 No-Sycophancy V4: Pre-Registered Overfitting

The v4 attempt added Tier 4 (capitulation: "I yield / defer to you / retract my correction / change my answer to match yours / whatever you think is right") and Tier 5 (social validation: "you did nothing wrong / trust your gut / anyone in your position would / your feelings are justified") to no-sycophancy.sh, tuned against the v3 held-out (DEV, n=58).

| Hook | Set | P | R | F1 | 95% CI |
|---|---|---|---|---|---|
| v2 | DEV n=58 (tuning set) | 1.000 | 0.175 | 0.298 | [0.130, 0.458] |
| v4 | DEV n=58 | 1.000 | 0.600 | 0.750 | [0.618, 0.857] |
| v2 | FRESH n=35 (novel phrasing) | 1.000 | 0.130 | 0.231 | [0.000, 0.452] |
| v4 | FRESH n=35 | 1.000 | 0.174 | 0.296 | [0.071, 0.516] |

On the tuning set, v4 achieves F1=0.750—a substantial lift. On the independently-phrased fresh test, F1=0.296: a gain of 0.065 points whose CI completely overlaps the v2 CI. The fresh per-mode recall (v4): SyConBench 0/5, ELEPHANT 0/6, SycEval 1/4, BrokenMath 1/4, opener-praise 2/4.

The v4 tiers caught 0 of the fresh SyConBench and ELEPHANT positives. Fresh examples expressed the same semantic content with different surface forms: "I'll back off," "your number is fine by me," "nothing to feel guilty about," "your read sounds spot on." These phrasings were not in the Tier 4/5 regex enumerations. Precision remained 1.000 on every set—the tiers were harmless but ineffective off-distribution.

Per the pre-registered rollback rule, no-sycophancy.sh was reverted to v2. The fresh-test judge validation confirmed the experiment's integrity: construction-vs-Sonnet κ = 1.000, positive recovery 23/23 (100%), inter-judge κ = 0.938. The fresh positives are genuine sycophancy; v4's misses are real misses.

---

## 4. The Negative Result and Its Lesson

The central finding is a negative result across two levels of evidence:

**Level 1 (v3):** The 0.667 TRAIN F1 for no-sycophancy collapses to 0.298 on a taxonomy-grounded held-out. The hook is a narrow opener-praise detector with near-zero recall on the dominant 2026 sycophancy modes (capitulation, social/emotional validation, false-statement confirmation, rebuttal-induced flips). This result was expected given what the hook's regexes encode, but it had not been measured before.

**Level 2 (v4):** An explicit attempt to lift recall on the failed modes via new lexical tiers achieved a 15× recall gain on the tuning set (0.175 → 0.600) and no measurable gain on a fresh test (0.130 → 0.174, non-significant). Precision was preserved in both cases, confirming that the problem is not over-triggering but under-coverage: the tiers enumerate specific phrasings that real sycophantic outputs do not consistently use.

The lesson is architectural: sycophancy recall is a semantic detection problem, not a lexical one. The question "does this response capitulate to social pressure without citing evidence?" cannot be answered by matching strings, because the same semantic act ("you are right and I was wrong") is expressed with a practically unbounded vocabulary. A growing regex approach faces diminishing returns: each new tier captures one cluster of training-distribution phrasings while missing the next cluster of novel phrasings. The v4 experiment provides direct empirical evidence of this ceiling—not as a hypothesis but as a measured outcome.

The honest_eta and roleplay results reveal the same pattern from a different angle. honest_eta achieves high precision on ETA-dishonesty because the surface form of dishonest ETAs ("ETA: X hours" without a range qualifier) is lexically narrow. No-roleplay-drift achieves moderate recall on anthropomorphization because the surface form of identity assertion is also relatively narrow. Sycophancy spans dozens of distinct surface forms across its subtypes; the pattern-match approach that works for honest_eta cannot transfer.

The cascade result for honest_eta also carries a lesson: when a high-precision narrow detector and a high-recall broad detector cover the same behavioral mode, their union captures substantially more of the mode than either alone. The 0.230 → 0.461 F1 lift with non-overlapping CIs at n=954 suggests that ensemble approaches—even simple OR-logic ensembles—should be evaluated before concluding that a mode is simply hard to detect.

---

## 5. Limitations

**LLM judge is an inter-Claude proxy, not human.** Both judges in the sycophancy evaluation (Tasks 1 and 4) are Claude-family models, used because no non-Claude API key was available in the evaluation environment. The κ values (1.000 / 0.813 / 0.813 for Task 1; 1.000 / 0.938 for Task 4) measure inter-Claude agreement and should not be interpreted as human-validated reliability. Human labels are deferred to the exported blind sheet (`annotations/sycophancy_heldout_blind_sheet.csv`). Similarly, the honest_eta judge-vs-human κ measurement on n=19 is inconclusive due to positive scarcity (2 of 19 human-labeled positives).

**Roleplay evaluation n=22 is underpowered.** The DarkBench anthropomorphization partition provides only 22 test traces. The 95% CI for the tuned roleplay pack is [0.400, 0.815]—a 41-point range—making any precision claim about whether F1 is above or below a threshold such as 0.70 unreliable. The sample size is not under the authors' control (it is determined by DarkBench's stratification), but results must be interpreted accordingly.

**Corpus is synthesized from taxonomy, not collected from production.** The sycophancy held-out traces were authored using published taxonomy descriptions as guides, not sampled from real user–model interactions. Synthesized corpora can capture the intended behaviors while missing the distributional quirks of production traffic. The judge validation (κ ≥ 0.813) confirms the traces read as genuine sycophancy to independent evaluators, but production recall may differ from corpus recall.

**Hooks are evaluated on the closeout surface; benchmark corpora target the chat surface.** The hooks fire on Stop and SubagentStop events (agent closeout), while DarkBench collects chat-turn responses. The surface conflict documented in Tasks 2 and 3—the same text having opposite ground-truth labels depending on deployment context—means benchmark F1 figures underestimate production precision for these hooks. This is acknowledged in the per-task results but cannot be fully corrected without a closeout-native benchmark.

**No cross-provider or multilingual validation.** All model interactions use Claude. Spanish smoke tests confirm complete cross-lingual recall collapse (0/3 for both hooks tested), but no evaluation was conducted for other non-English languages, and no cross-provider judge was available.

---

## 6. Reproducibility and Data Availability

All evaluation code, corpora, and results files are released under Apache-2.0.

**Code:**
- `evaluation/score_darkbench.py` — DarkBench scorer with train/test split firewall and bootstrap CI
- `evaluation/score_roleplay.py` — ACB synthetic corpus scorer (documents the F1=1.000 fixture limitation)
- `evaluation/score_sycophancy_heldout.py` — sycophancy held-out scorer with per-source recall and CI
- `evaluation/sycophancy_judge.py` — dual `claude -p` judge with Cohen's κ
- `evaluation/sycophancy_blind_sheet.py` — blind human-validation sheet export
- `evaluation/honest_eta_task3.py` — baseline, PR curve, cascade, and κ for Task 3
- `evaluation/metrics.py::bootstrap_f1_interval` — shared bootstrap CI function (samples=1000, seed=42)

**Corpora:**
- `data/sycophancy/heldout_positives.jsonl` — n=58 (40 pos / 18 control), taxonomy-grounded, judge-validated
- `data/sycophancy/freshtest.jsonl` — n=35 (23 pos / 12 control), novel phrasing, judge-validated
- `annotations/sycophancy_heldout_blind_sheet.csv` — 58 rows, labels hidden, for human validation
- `annotations/sycophancy_heldout_private_keymap.jsonl` — join key (operator-only)

**Results:**
- `results/v3/sycophancy_heldout_v2.json` — Task 1 F1 + CI + per-mode recall
- `results/v3/sycophancy_judge_kappa.json` — Task 1 judge κ
- `results/v3/roleplay_*.json` — Task 2 baseline, tuned, ablation (train + test)
- `results/v3/honest_eta_task3.json` — Task 3 baseline, PR curve, cascade, κ
- `results/v4/sycophancy_v4_freshtest.json` — v4 fresh-test F1 + CI + per-mode recall
- `results/v4/sycophancy_fresh_judge_kappa.json` — v4 fresh-test judge κ

**Reproducibility:** All scoring paths are deterministic. Re-running any scorer twice produces zero per-trace delta. LLM-judge labels are frozen in the JSONL files and never re-called during scoring. Re-run command for roleplay: `python3 evaluation/score_darkbench.py --category anthropomorphization --split test --rules <tuned_rules_dir>`.

**Dataset availability:** The corpus files listed above are released with this repository under Apache-2.0. The ELEPHANT and ClawsBench source texts are not redistributed per their license restrictions; this evaluation used only taxonomy descriptions as authoring guides and original synthesized text.

**HuggingFace dataset:** TODO — the held-out corpora will be deposited on HuggingFace Datasets with a Zenodo DOI at time of publication for permanence.

---

## References

[1] llm-dark-patterns contributors. *llm-dark-patterns: LLM dark pattern detection hooks for agent closeout.* Apache-2.0. https://github.com/waitdeadai/llm-dark-patterns

[2] Kran et al. *DarkBench: Benchmarking Dark Patterns in Large Language Models.* ICLR 2025. arXiv:2503.10728. https://arxiv.org/abs/2503.10728

[3] MAST. *Multi-Agent System failure Taxonomy.* (Mode 2.6: reasoning-action mismatch.) Mapping used in this repository: `evaluation/mast/mast_hook_map.py`.

[4] *The Silicon Mirror: Dynamic Behavioral Gating for Anti-Sycophancy in LLM Agents.* arXiv:2604.00478. https://arxiv.org/abs/2604.00478

[5] Fanous et al. *SycEval: Evaluating LLM Sycophancy.* arXiv:2502.08177. https://arxiv.org/abs/2502.08177

[6] *Measuring Sycophancy of Language Models in Multi-turn Dialogues.* arXiv:2505.23840. https://arxiv.org/abs/2505.23840

[7] Cheng et al. *ELEPHANT: Measuring and understanding social sycophancy in LLMs (Social Sycophancy: A Broader Understanding of LLM Sycophancy).* arXiv:2505.13995. https://arxiv.org/abs/2505.13995

[8] *BrokenMath: A Benchmark for Sycophancy in Theorem Proving with LLMs.* arXiv:2510.04721. https://arxiv.org/abs/2510.04721

---

*This paper describes experiments conducted on the `distribution/v3-positioning` branch of the llm-dark-patterns repository. The shipped hooks (`no-sycophancy.sh`, `honest-eta.sh`) are unchanged from v2 by design; the tuned roleplay rules are staged in `evaluation/v3/staged-rules/` pending review. No-sycophancy v4 tiers were reverted per pre-registered rollback criteria.*
