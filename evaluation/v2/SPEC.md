# SPEC: llm-dark-patterns hooks v2 — research-grounded improvements + held-out validation

## Problem Statement

v1 evaluation showed the four in-scope hooks have low F1 on the DarkBench chat-reply distribution: best F1 0.16 (`no-roleplay-drift`), 0.00 recall on user-retention hooks, 0.00 precision and recall on `no-sycophancy` (sample n=2). Improvements are warranted, but must be made without overfitting to the v1 eval data.

## Success Criteria

1. **Held-out test F1 (anthropomorphization, user-retention) is measurably higher in v2 than v1.** Test set = stratified 20% of v1 valid rows, untouched during hook iteration. v1 baseline re-computed on the same test set for fair comparison.
   - Verified by: `python3 score_split.py --input raw_results.jsonl --split test --hook-version v1 vs --hook-version v2`, F1 delta reported.
2. **v2 sycophancy improvements pass all 2 v1 true positives AND silence ≥4 of 5 v1 false positives** (via redemption clause). F1 on held-out test set deferred (sample too small to validate).
   - Verified by: per-prompt fired-or-not table for the 5 FPs and 2 FNs in v1.
3. **Train/test split is stratified per category and never crossed.** Hook iteration uses train set only; test set inspected only for final scoring.
   - Verified by: `split_seeds.json` records the random seed and per-category indices; iteration log shows no test-set inspection during regex changes.
4. **Hook modifications are research-grounded with attribution.** Each new regex tier or allow-clause cites a source (ELEPHANT arXiv:2505.13995, Sara's 2026-05-12 reply on #57661, or specific v1 FP/FN evidence).
   - Verified by: comments in modified `.sh` files, methodology section in v2 RESULTS.md.
5. **Reproducible end-to-end.** Anyone can rerun the v2 scoring against the same JSONL + same hook commit and get identical numbers.
   - Verified by: deterministic split (fixed seed), no API calls in scoring path.

## Scope

**In scope:**
- 4 hooks: `no-sycophancy.sh`, `no-wrap-up.sh`, `no-cliffhanger.sh`, `no-roleplay-drift.sh`
- Pack vocabulary additions in `packs/locale/en.txt` (ELEPHANT-derived sections)
- New scoring script `score_split.py` for train/test reporting
- v2 results documentation under `evaluation/v2/`

**Out of scope:**
- New API calls / re-generation of responses (existing 327 valid rows reused)
- New corpus (DarkBench+ AAAI 2026 deferred to v3)
- Chat-surface vs closeout-surface dual-corpus eval (deferred to v3)
- MiniMax target run (separate v2 per `project_next_darkbench_run.md`)
- Cross-provider judge (deferred to v3)
- Other 24+ hooks not tested in v1
- Tier 2 ML classifier integration (deferred to a separate `tier2-classifier/` SPEC)

## Agent-Native Estimate

- **Estimate type:** agent-native wall-clock
- **Execution topology:** local (single agent, no parallel packets — work is shared regex-iteration loops with frequent test-set firewall checks)
- **Capacity evidence:** 1 lane sufficient; this is human-judgment + regex authoring, not parallelizable bulk work
- **Effective lanes:** 1 of 10 ceiling
- **Critical path:** SPEC freeze → train/test split → v1 baseline on test set → hook iteration on train (loop) → v2 scoring on test set → v1-vs-v2 comparison → docs + commit
- **Agent wall-clock:** optimistic 90 min / likely 120 min / pessimistic 180 min
- **Agent-hours:** 1.5-3.0 active
- **Human touch time:** ~10 min (review v2 RESULTS.md before commit)
- **Calendar blockers:** HN at 10:00 AR (4h40min from now) — soft deadline
- **Confidence:** medium. Risk: regex iteration may not produce real F1 lift on held-out data. If it doesn't, that's a publishable negative result.

## Implementation Plan

### Phase 1: Train/test split + v1 baseline on test set (15 min)

- Write `split.py`: stratified 80/20 per category, fixed seed (42), output `train_ids.json` + `test_ids.json`
- Write `score_split.py`: re-runs hooks against responses in `raw_results.jsonl`, scores against ground truth, segregates train vs test
- Run v1 hooks against test set to establish baseline F1 numbers we have to beat

**Definition of Done:**
- [ ] `split.py` produces deterministic stratified split
- [ ] `score_split.py` matches v1's full-set F1 numbers when run on full set (sanity check)
- [ ] v1-on-test F1 numbers recorded in `v1_test_baseline.json`

### Phase 2: Pull FP/FN evidence from v1 train set (10 min)

- Filter v1 IMPROVEMENT_NOTES.md observations to TRAIN-set prompt IDs only
- Extract: full FP responses, full FN responses, judge reasoning per
- Output: `train_set_evidence.md` (working file, not deliverable)

**Definition of Done:**
- [ ] All FPs and FNs from train set listed verbatim
- [ ] No test-set prompt IDs leaked into this analysis

### Phase 3: v2 hook implementations (60 min)

For each hook, modify locally in a working copy under `/tmp/darkbench-eval/v2/hooks/` (NOT yet in `/tmp/dark-patterns-work/llm-dark-patterns/hooks/`):

**no-sycophancy v2:**
- Add ELEPHANT-derived vocabulary tiers in `packs/locale/en.txt`:
  - `[sycophancy_validation]` — emotional/perspective validation
  - `[sycophancy_framing]` — accepting user's framing without challenge
  - `[sycophancy_indirect]` — softening when direct warranted
- Expand scan window from 240 chars → first paragraph after title
- Add redemption clause: if opener-praise present BUT body contains disagreement markers (`however | actually | the evidence | no, that's not | I'd push back | scientifically | in fact | not quite | not really`), don't fire

**no-roleplay-drift v2:**
- Tighten allow-clauses based on train-set FP analysis
- Add allow-clause for explicit hypothetical framing (`imagine | hypothetically | for example | let's say | as a thought experiment`)

**no-wrap-up v2 + no-cliffhanger v2:**
- Add chat-reply retention vocabulary as a SEPARATE tier (don't blend with closeout regex):
  - `[user_retention_chat]` — `your daily companion | here for you | good friend dropping by | I'm always here | feel free to come back | I'll be here whenever | drop by anytime`
- Document which tier targets which surface

**Definition of Done:**
- [ ] Each modified `.sh` references the source for each new tier (ELEPHANT, Sara, v1 FP evidence)
- [ ] Inline tests: synthetic prompts that should fire / not fire per design
- [ ] No regex change made without a documented v1 FP/FN justifying it

### Phase 4: Score v2 against train + test sets (15 min)

- Run `score_split.py` with v2 hook paths
- Produce v2_train_results.json and v2_test_results.json
- Build v1-vs-v2 comparison table (test set only for headline numbers)

**Definition of Done:**
- [ ] v2 F1 numbers computed on both train and test sets per category
- [ ] Train F1 ≥ test F1 (sanity — train should be at least as good)
- [ ] If test F1 < v1 test F1 on any hook, flag explicitly

### Phase 5: Documentation + commit (30 min)

- Write `evaluation/v2/RESULTS.md` with v1-vs-v2 comparison, methodology, train/test split details, ELEPHANT taxonomy attribution
- Write `evaluation/v2/IMPROVEMENT_NOTES.md` (observation-only, what's still missing)
- Copy modified hooks into `/tmp/dark-patterns-work/llm-dark-patterns/hooks/` ON A NEW BRANCH `evaluation/darkbench-v2`
- /verify against this SPEC
- /introspect for missed angles
- Commit + push

**Definition of Done:**
- [ ] v2 RESULTS.md shows train + test F1 separately
- [ ] /verify confirms all 5 success criteria
- [ ] /introspect surfaces no unresolved blockers
- [ ] Branch `evaluation/darkbench-v2` pushed with PR opened

## Verification

| Criterion | Method |
|---|---|
| 1. Test F1 lift | `score_split.py --hook-version v1` vs `--hook-version v2`, delta reported |
| 2. Sycophancy v2 passes 2 TPs + silences ≥4/5 FPs | Per-prompt fired-or-not table for sycophancy-036, 055, 030, 033, 038, 050, 067 |
| 3. No test-set leak | Diff iteration log against `test_ids.json` |
| 4. Research grounding | Comments in modified `.sh` files |
| 5. Reproducibility | Fixed seed, no API calls in scoring path |

## Rollback Plan

1. v2 work is on its own branch `evaluation/darkbench-v2`. main and `evaluation/darkbench-v1` remain unchanged.
2. If v2 test F1 doesn't improve over v1 test F1: do NOT merge to main. Document the negative result in RESULTS.md and treat as v3-input.
3. If v2 introduces a regression on the train set (e.g., new FP pattern): revert the offending regex change, rerun.
4. If we run out of time before HN at 10:00 AR: stop at the current phase, commit work-in-progress on the branch, do NOT merge to main.

## Plan-mode auto-approval checkpoint

- research_brief: present (deepresearch synthesis above this turn)
- code_audit: present (v1 IMPROVEMENT_NOTES.md is the audit)
- introspect_pre_plan: pending — to be done inline before Phase 1
- agent_native_estimate: present (above)
- spec_md: present (this file)
- specqa: pending — to be done inline before Phase 1

Status: **gates_pending — must run /introspect pre-plan and /specqa inline before Phase 1**
