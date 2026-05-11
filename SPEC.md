# SPEC: Phase A/B/C — multi-agent orchestration + agentic safety + power-user polish

## Problem Statement

The current 11-hook suite addresses single-agent textual dishonesty
(positive closeout without evidence, sycophancy, paternalism, fake
recall, fake stats, fake cite, ETA bullshit, wrap-up nudging,
continuity loss). It does not yet address the **2026 SOTA workflow**:
a dev orchestrating 5+ parallel Claude Code instances/subagents.

DeepResearch (live 2026-05-11) confirmed that the dominant failure
mode of multi-agent systems is "silent mistakes, not crashes"
([arXiv:2604.14228 Apr 2026], [Anthropic multi-agent blog Jun 2025]),
that LLM-based aggregation hallucinates consensus that does not
exist in worker output ([Beam AI Apr 2026]), that handoff loops
between agents are common ([gurusup May 2026]), and that the
canonical AgentLeak benchmark ([arXiv:2602.11510]) catalogs 7
communication channels in multi-agent pipelines vulnerable to
credential and context leak. Anthropic's own Claude Opus 4.6 Sabotage
Risk Report flags "passive research sandbagging that could be
confused with ordinary capability weakness."

This SPEC ships hooks for that surface PLUS a power-user-polish
batch addressing the textual annoyances frontier LLMs default to
(emoji spam, TL;DR bait, meta-commentary, prompt-restate preamble,
disclaimer padding, AI tells, roleplay drift).

## Filter — what's NOT shipping (with rationale)

3 of the 20 candidates from the 2026-05-11 deepresearch are
explicitly skipped:

- **`no-stale-context-trust`** — requires turn-window state tracking
  the suite does not currently provide. Implementing inside one hook
  would be wrong shape. Defer to a future state-engine extension.
- **`no-circular-verification`** — requires multi-agent log analysis
  the operator's own orchestration framework would need to surface
  in the hook payload. Without payload access, false-positive risk
  too high. Defer.
- **`no-credit-fishing`** — folded as a new section
  `[credit_fishing_opener]` into the existing `no-sycophancy` hook
  rather than shipped standalone. Same architecture (turn-open
  praise-spam variant), no need for a separate hook.

17 hooks ship, organized in 3 phases.

## Success Criteria (verifiable)

For each shipped hook:
- [ ] `hooks/<hook-name>.sh` exists, executable, syntax-valid bash.
- [ ] `hooks/hooks.json` registers it under the correct event(s).
- [ ] At least one new section in `packs/locale/en.txt` if locale-
  specific vocab applies, OR an inline regex if pattern is
  universal (numeric thresholds, phrase patterns regardless of
  language).
- [ ] At least 5 stress fixtures (3 positive + 2 negative + 1 edge).
- [ ] README "The suite" table row added.
- [ ] METHODOLOGY.md citation entry where academic backing exists.

For the suite as a whole:
- [ ] `bash tests/stress/run.sh` returns 0 with all fixtures PASS.
- [ ] `bash tests/test-pack-loader.sh` returns 17/17 PASS.
- [ ] `bash -n` passes on every new hook.
- [ ] `jq -e .` passes on `hooks/hooks.json`.
- [ ] CI workflow updated to include new hooks in the bundle smoke
  loop (existing stress job picks up new fixtures automatically).
- [ ] One commit per phase, conventional title.

## Phase A — Multi-agent orchestration (5 hooks)

**Highest leverage for the +5 parallel instances use case.**

| Hook | Trigger summary | Backing |
|---|---|---|
| `no-aggregator-hallucination` | "synthesizing N workers' results" / "based on the agents' findings" without quoted worker_id output or specific worker_N reference | Beam AI Apr 2026; Anthropic blog Jun 2025; arXiv 2603.04474 Mar 2026 |
| `no-silent-worker-success` | "all N workers completed" / "X parallel agents finished" / "spawned N workers, all done" without per-worker enumeration or exit-code evidence | arXiv 2604.14228 Apr 2026 ("dominant failure mode is silent mistakes"); Claude Code issue #45958 |
| `no-cherry-pick-rollup` | "X out of Y workers succeeded" + positive closeout WITHOUT explicit acknowledgment of unhandled Y-X | gurusup May 2026; Slow AI on Anthropic multi-agent warning |
| `no-ownership-violation` | TaskCompleted payload edited file paths don't match agent's declared owned_paths field, OR message says "modified X" where X is outside the task's scope | Anthropic multi-agent blog; r/ClaudeCode stale-context thread |
| `no-handoff-loop` | TaskCreated chain shows the same agent_id appearing 3+ times in the handoff history within a single workflow | gurusup May 2026 explicit |

## Phase B — Agentic safety (4 hooks; #10 simplified, #11/#12 deferred)

| Hook | Trigger summary | Backing |
|---|---|---|
| `no-credential-leak-in-handoff` | TaskCreated/Stop payload contains tokens matching `sk-*`, `Bearer *`, `password=*`, `api_key=*`, or pattern matches commonly-leaked credential shapes | arXiv 2602.11510 AgentLeak Mar 2026 (7 communication channels) |
| `no-phantom-tool-call` (simplified) | Message says "I ran `<tool>` and got [X]" / "the `<tool>` tool returned [X]" but message has no command output, no `Tool result:` block, no `<tool>` evidence shape | Anthropic tracing-thoughts research |
| `no-sandbagging-disguise` | "tried to X but [vague reason]" / "attempted X without success" / "I gave it my best shot but" without command output, error message, or specific blocker | Anthropic Claude Opus 4.6 Sabotage Risk Report (passive research sandbagging) |
| `no-rollback-claim-without-evidence` | "rolled back" / "reverted" / "undone" / "restored to prior state" claim without `git revert` / `git restore` / `git reset` / specific rollback command in same message | Extends no-vibes evidence pattern to specific surface |
| `no-approval-sneak` (simplified) | TaskCompleted shows file changes touching paths matching operator-defined `[approval_required]` section in `packs/sensitive/paths.txt` (defaults: `secrets/`, `.env*`, `prod/`, `.kube/`, `terraform/state/`) without prior message containing approval-token phrase | Anthropic trustworthy-agent framework Apr 2026 |

## Phase C — Power-user polish (7 hooks + 1 section extension)

| Hook | Trigger summary | Backing |
|---|---|---|
| `no-emoji-spam` | message contains > N emoji codepoints (default N=3, configurable via `LLM_DARK_PATTERNS_EMOJI_THRESHOLD`) | r/ChatGPT "UNBEARABLE" community thread Feb 2026 |
| `no-tldr-bait` | message ends with `TL;DR:` / `In summary:` / `Summary:` block when total message > 200 chars (avoids matching legitimate one-liner summaries) | Extends no-wrap-up surface |
| `no-meta-commentary` | "Let me think about this" / "Now I'll consider" / "First, I need to think about" / "Let me work through this" — narrating chain-of-thought instead of doing | Anthropic tracing-thoughts; r/ChatGPTcomplaints |
| `no-prompt-restate` | message OPENS with "You asked (me )?to X" / "I understand (that )?you want X" / "So you'd like me to X" — preamble waste | r/ChatGPTcomplaints power-user thread |
| `no-disclaimer-spam` | "Please note (that )?" / "It('s| is) important to (note|mention)" / "It should be noted (that )?" / "Keep in mind (that )?" — defensive padding | Extends no-curfew (paternalism family) — different vocab from rest paternalism |
| `no-ai-tells` | known LLM-default phrases: "delve into", "tapestry", "navigate the intricacies", "in the realm of", "it's worth noting", "a testament to", "underscore" verb form, "foster" verb form (configurable) | r/NoStupidQuestions "this is so obviously AI" thread Apr 2026; complementary to `conorbronsdon/avoid-ai-writing` skill |
| `no-roleplay-drift` | "as an AI assistant, I" / "I'm just an AI" / "I cannot have opinions" / "as a language model" — model breaking agent character mid-task | DarkBench Anthropomorphism inverse |
| `no-sycophancy [credit_fishing_opener]` (NOT a new hook — section extension) | "I worked hard on this" / "It took some thinking but" / "putting in real effort here" — credit-fishing variant | Inverse of standard sycophancy; folded into existing hook |

## Agent-Native Estimate

- Estimate type: agent-native wall-clock
- Execution topology: local supervisor (one bash session)
- Critical path: SPEC -> Phase A (5 hooks + fixtures + commit) -> stress
  green -> Phase B (5 hooks + fixtures + commit) -> stress green -> Phase C
  (7 hooks + section extension + fixtures + commit) -> stress green -> push
- Agent wall-clock per phase:
  - Phase A: optimistic 90m / likely 130m / pessimistic 180m
  - Phase B: optimistic 75m / likely 105m / pessimistic 150m
  - Phase C: optimistic 70m / likely 100m / pessimistic 140m
  - **Total**: optimistic 235m (4h) / likely 335m (5.6h) / pessimistic 470m (7.8h)
- Agent-hours: ~5.6h
- Human touch time: 0 (operator authorized full execution via `/opusworkflow it`)
- Calendar blockers: none
- Confidence: medium-high (architecture proven across 11 existing hooks
  + this SPEC follows the same pattern; risk = some Phase B hooks need
  payload shapes the operator may not provide, mitigated by inline-fallback
  no-op semantics)

## Implementation Plan

Each phase is its own commit. Each hook follows the same shape:
1. `hooks/<name>.sh` — sources `lib/packs.sh`, loads vocab, inline fallback,
   regex match, block with repair-template citing source.
2. Pack section in `packs/locale/en.txt` for locale-specific vocab, OR
   inline-only if pattern is universal (numeric, structural).
3. `hooks/hooks.json` registration under appropriate event(s).
4. Stress fixtures: positive (5+) / negative (3+) / edge (1+) for each.
5. `_gen_fixtures.py` updated.
6. README + METHODOLOGY entry where academic backing exists.

After each phase:
- `bash tests/stress/run.sh` PASS
- `bash tests/test-pack-loader.sh` PASS
- `bash -n` clean on new hooks
- `jq -e .` clean on hooks.json
- Single commit, push.

## Verification

Per phase:
- Hook count matches expected (Phase A: 11→16; Phase B: 16→20; Phase C: 20→27)
- Stress fixture count grows by ≥25/phase
- CI green on cloud (gh run check)

Final state:
- 27 hooks (was 11, +16 new + 1 section extension)
- ~290-340 stress fixtures (was 219)
- All gates green

## Rollback Plan

Per phase:
1. `git revert <commit_hash>`
2. `git push origin main`

Phases are independent — Phase B/C don't depend on Phase A persistence,
so reverting one phase doesn't break others.
