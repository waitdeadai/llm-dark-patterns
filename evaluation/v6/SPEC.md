# SPEC — v6: `no-count-drift` Stop hook (count-vs-enumeration self-consistency gate)

Status: ACTIVE (pre-implementation). Author: waitdeadai. Date: 2026-05-25.
Origin: proposed by @beq00000 (Brendan Quinn) on `recognition-without-arrest-corpus#9` —
"a final-pass diff between every count-claim in prose and its enumeration or table
source," a verification gate that lives *outside* the writing agent's recall.

## 1. Problem Statement

LLM agents state a count in prose ("fourteen instances", "six instances", "5 of 7",
"2/35 = 5.7%") that contradicts the artifact's own enumeration or arithmetic — a
self-consistency (faithfulness) failure, not a missing-citation (factuality) failure.
No existing hook in the suite catches it: `no-fake-stats` checks citation presence and
deliberately ignores small integers.

## 2. Success Criteria (measurable)

- **SC1 (precision floor, hard gate):** On the v6 fixture set, the deterministic core
  produces **zero false positives on the negative set** (precision = 1.000). A blocking
  gate must not false-fire. The negative set MUST be **adversarial and authored
  independently of the detector patterns** (correct counts that resemble the positives;
  ambiguous/multi-enumeration scope; nested lists a naive counter would miscount; vague
  cardinality) — precision claimed only against that adversarial set, to avoid the
  co-evolved-corpus fake-precision trap. Verified by `tests/test-count-drift.sh` exiting 0.
- **SC2 (seeded true positives caught):** Each present as a fixture, each yields
  `decision=block`: (a) "fourteen" prose vs 15 enumerated bullets (R3); (b) "six
  instances" headline vs five enumerated (R3); (c) a genuinely wrong fraction-to-percent,
  e.g. "9/10 = 80%" (R1; 9/10 is 90%). NOTE: the #9 cross-section case ("2/35=5.7%" in §2
  vs "2/42=4.8%" in §3) is the same-quantity-different-denominator linking case and is
  explicitly OUT of scope (§3, advisory only); "2/35 = 5.7%" is itself arithmetically
  CORRECT (5.71% rounds to 5.7%) and MUST pass — it belongs in the adversarial negatives.
- **SC3 (abstention on ambiguity):** Inputs with 0 or ≥2 candidate enumerations in
  scope, vague cardinality ("a few"), or prose-only counts yield `decision=pass`
  (abstain). Verified by negative fixtures.
- **SC4 (fail-open):** Missing `jq` OR missing `python3` → hook exits 0 (never breaks a
  session). Verified by `tests/test-count-drift.sh` env-stubbed cases.
- **SC5 (determinism):** Identical input → identical verdict across two runs, zero delta.
  Verified by running the fixture scorer twice and diffing.
- **SC6 (no regression):** `bash scripts/*hook-smoke*` (or the repo's hook smoke) still
  passes with `no-count-drift` wired into `hooks/hooks.json`.
- **SC7 (reported, not gated):** F1 + bootstrap 95% CI on the full fixture set, reported
  in `evaluation/v6/RESULTS.md`. Recall is reported, NOT required high (bounded by
  structural extraction, per statcheck precedent ~61% recall at >96% specificity).

Non-criteria (explicitly): high recall is NOT a success criterion. LLM-judge accuracy is
out of scope for v1.

## 3. Scope

**In scope:**
- `hooks/no-count-drift.sh` — bash wrapper (reads `.last_assistant_message`, fail-open,
  calls the Python core, exit 2 on block) matching the suite's hook conventions.
- `lib/count_drift.py` — pure-stdlib Python core (no pip deps). Three TIER-1 deterministic
  detectors with strict abstention.
- `evaluation/v6/fixtures.jsonl` — hand-authored positives + negatives (incl. the SC2
  seeds and SC3 abstention cases).
- `evaluation/v6/score_count_drift.py` — scorer (precision/recall/F1 + bootstrap CI).
- `tests/test-count-drift.sh` — bash harness (assert pattern from `test-pack-loader.sh`).
- `hooks/hooks.json` — wire `no-count-drift.sh` into `Stop` and `SubagentStop`.
- `evaluation/v6/RESULTS.md` + this `SPEC.md`.

**Out of scope (this PR):**
- LLM-judge advisory tier (optional follow-up `no-count-drift-warn.sh`, env-gated, never
  exits 2 — mirrors existing `no-sycophancy-warn.sh`). Reason: keep v1 deterministic and
  high-precision; the literature ("Too Consistent to Detect", 2025-05) shows LLM judges
  miss self-consistent count errors.
- Cross-section semantic same-quantity linking (prose number vs a table cell for the
  "same" labeled metric) — the KPI-Check problem, ~73% F1; too fuzzy to block on.
- A Rust YAML rule pack in `agent-closeout-bench` — the engine is regex-match-only and
  cannot count items or recompute fractions, so the computation must live in Python. N/A.

## 4. Detector design (TIER-1 deterministic, abstain-on-ambiguity)

Input: the assistant message text. Output JSON: `{decision: block|pass, rule, evidence}`.

- **R1 — fraction/percentage arithmetic self-check (safest, ~100% precision, no linking):**
  Find `A/B = P%` / `A/B (P%)` patterns; recompute `A/B*100`; `block` if
  `|computed − P| > tol` (tol = max(0.5pp, one-ulp of stated precision)). No enumeration
  needed; pure arithmetic.
- **R2 — "N of M" bound check:** parse `N of M <noun>` (word or digit); `block` if `N > M`
  (impossible). If exactly one enumeration of the noun is in scope with a counted size,
  also check N against it; else just the N>M bound.
- **R3 — headline count vs single enumeration:** a count-claim (`<num> <noun>` as a
  heading/lead-in, **count ≥ 2**, colon **adjacent to the noun phrase** with no
  intervening punctuation/number) immediately followed, before the next heading, by
  **exactly one markdown LIST** whose **top-level** item count ≠ the claimed number.
  Tables are excluded (a 2×2 matrix has 4 cells but 2 rows — a poor count proxy). Number
  words require a leading word boundary (so "of-**ten**" / "writ-**ten**" do not parse as
  "ten"). **Abstain (pass)** on count < 2, 0 or ≥2 candidate lists, depth ambiguity,
  label/section indices, second-number lead-ins, or vague cardinality. (R3's loose
  lead-in and word-boundary gaps were caught by the independent MAD eval — §7 — not the
  hand-authored fixtures.)

Number parsing: built-in word→int lexicon (one..nineteen, tens, hundred, thousand,
ordinals, "a dozen"=12); no `text2num`/pip dep. Markdown counting: count top-level list
items (min-indent of the contiguous block) and table data rows (exclude header+separator)
via stdlib line scanning. Every detector **abstains** rather than guesses.

## 5. Agent-Native Estimate

- Estimate type: agent-native wall-clock.
- Execution topology: local (the precision-critical parser/abstention logic is one tightly
  coupled reasoning loop; do not split). Fixtures are a small optional sidecar.
- Capacity evidence: capacity is NOT the binding constraint — this is local single-loop
  implementation, not parallelizable dense work; `parallel-capacity.sh` not consulted
  because lanes don't reduce the critical path here.
- Effective lanes: 1 (optionally 2 if fixtures are delegated).
- Critical path: SPEC → /specqa → /introspect → `count_drift.py` core → fixtures →
  scorer/tests → /verify.
- Agent wall-clock: optimistic ~6 build/verify cycles, likely ~10, pessimistic ~16
  (pessimistic if hitting SC1 zero-false-positive needs a precision-tuning iteration on R3).
- Agent-hours: low (single-file core + fixtures + harness).
- Human touch time: design direction (given), review of the diff, merge/PR decision.
  No external credentials.
- Calendar blockers: none — isolated worktree, feature branch, no deploy. (Pushing the
  branch later needs the `workflow` scope only if hooks.json wiring counted as a workflow
  file — it is NOT under `.github/workflows`, so no scope blocker.)
- Confidence: medium — downgrade reason: R3 referent-linking abstention may need one
  tuning pass to guarantee zero false positives (SC1) without collapsing R3 recall to zero.
- Human-equivalent baseline (secondary only): ~half a day for a developer to write the
  parser, fixtures, and tests carefully.

## 6. Implementation Plan

### Task 1: Python core `lib/count_drift.py`
Definition of Done:
- [ ] Reads message text from stdin or `--text`/`--file`; emits decision JSON.
- [ ] R1 fraction/percentage recompute with tolerance.
- [ ] R2 "N of M" bound + optional in-scope list check.
- [ ] R3 headline-count vs single-enumeration with strict abstention.
- [ ] Word→int lexicon; top-level markdown list + table-row counting (stdlib only).
- [ ] Abstains (pass) on every ambiguous case enumerated in §4.

### Task 2: Bash hook `hooks/no-count-drift.sh`
Definition of Done:
- [ ] Reads stdin JSON, extracts `.last_assistant_message` via jq.
- [ ] Fail-open (exit 0) if jq or python3 absent, or input not JSON.
- [ ] Calls `lib/count_drift.py`; on `decision=block` exit 2 with
      `BLOCKED:` + `Matched rule:` + `Evidence:` + `Repair guidance:` (suite format).
- [ ] `stop_hook_active=true` → exit 0 (no re-entrancy), matching siblings.

### Task 3: Fixtures + scorer + tests
Definition of Done:
- [ ] `evaluation/v6/fixtures.jsonl` with the SC2 positives, SC3 abstentions, and a
      balanced negative set (correct counts that must pass).
- [ ] `evaluation/v6/score_count_drift.py` → precision/recall/F1 + bootstrap 95% CI (seed
      fixed, samples=1000) writing `evaluation/v6/RESULTS.md`.
- [ ] `tests/test-count-drift.sh` asserts SC1 (0 FP), SC2 (seeds blocked), SC3 (abstain),
      SC4 (fail-open via PATH stub), SC5 (determinism).

### Task 4: Wiring + docs
Definition of Done:
- [ ] `hooks/hooks.json` adds `no-count-drift.sh` to `Stop` and `SubagentStop`.
- [ ] `evaluation/v6/RESULTS.md` populated from a real scorer run.
- [ ] README hook table / METHODOLOGY updated to list the hook + its MAST FM-3.2 mapping.

## 7. Verification

- SC1/SC2/SC3/SC4/SC5 → `bash tests/test-count-drift.sh` exits 0 (each assertion).
- SC6 → repo hook-smoke passes with the new wiring.
- SC7 → `python3 evaluation/v6/score_count_drift.py` writes RESULTS.md with F1 + CI;
  run twice, diff = empty (also covers SC5).
- Hook-level smoke: pipe a positive `{"hook_event_name":"Stop","last_assistant_message":...}`
  → exit 2; negative → exit 0; `PATH` without jq → exit 0.
- **Independent (non-circular) precision** → `python3 evaluation/v6/independent_eval.py`
  runs the detector over corpora it was NOT authored against (real LLM responses in
  `evaluation/raw_results.jsonl` + the other hooks' stress fixtures) and must report
  **0 blocks** (zero false positives). Result: 0 / 988 texts. This is the precision
  evidence that the hand-authored F1 cannot give (co-evolved-corpus); it caught two real
  R3 false-positive classes that the fixtures missed.

## 8. Rollback Plan

1. The work is isolated on branch `feature/v6-count-drift` in a worktree; nothing is on
   `main` until an explicit merge.
2. To unwire without removing files: delete the `no-count-drift.sh` entries from
   `hooks/hooks.json` (each hook is independent by design).
3. Full revert: `git branch -D feature/v6-count-drift` (pre-merge) or `git revert <sha>`
   (post-merge); remove `hooks/no-count-drift.sh`, `lib/count_drift.py`, `evaluation/v6/`.
4. Verify rollback: repo hook-smoke passes and `grep -c no-count-drift hooks/hooks.json` = 0.

## Source ledger (deepresearch, accessed 2026-05-25)

- statcheck (CRAN; Nuijten validity study 2017): deterministic recompute-and-compare,
  specificity 96–100%, recall ~61% — high-precision/narrow-recall precedent.
- ContraDoc (NAACL 2024, arXiv:2311.09182): "Numeric" is a named and EASIEST
  intra-document self-contradiction type.
- "Sequential Enumeration in LLMs" (arXiv:2512.04727) + "Too Consistent to Detect"
  (arXiv:2505.17656): counting is a rule-based-symbolic strength; LLM/self-consistency
  judges miss self-consistent count errors → counting belongs in deterministic code.
- HalluLens (ACL 2025, arXiv:2504.17550): this is intrinsic/faithfulness hallucination,
  orthogonal to factuality.
- MAST (NeurIPS 2025 D&B, arXiv:2503.13657): maps to FM-3.2 "No or incomplete
  verification" (+ FM-2.6). DarkBench (ICLR 2025, arXiv:2503.10728) does not cover it.
- Landscape check: no existing hook in `llm-dark-patterns` / `agent-closeout-bench` /
  `cc-safe-setup` does in-message count-vs-enumeration — confirmed gap, not duplication.
