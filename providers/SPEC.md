# SPEC — providers/: provider-neutral normalization for cross-model hook runs

Status: ACTIVE (pre-implementation). Author: waitdeadai. Date: 2026-05-26.
Origin: the provider-invariance thread with @yurukusa (anthropics/claude-code#61167)
and @nvst18's request to trial non-Claude models under the same runtime verification.
This is the Claude-side substrate contract that lets the `llm-dark-patterns` detectors
run against transcripts from other providers — the prerequisite for any cross-model F1
pass. @yurukusa builds the live Kimi K2 / OpenAI adapter against this contract.

## 1. Problem Statement

The suite's detectors consume Claude Code's hook JSON (`.last_assistant_message`, tool
events). To test provider-invariance ("does operator-side discipline generalize across
models?") the detectors must run against OpenAI / Kimi K2 transcripts too. There is no
provider-neutral shape today, so the substrate cannot run a second-model pass.

## 2. Success Criteria (measurable)

- **SC1 (normalization):** `providers/normalize.py` maps raw fixtures from Claude Code
  hook JSON, OpenAI Chat Completions, OpenAI Responses, and Kimi/Moonshot into a single
  `NormalizedTurn` (`assistant_message: str`, `tool_calls: [{name, arguments}]`).
  Verified by `providers/conformance_test.py` asserting field-level equivalence.
- **SC2 (provider-invariance proof — the load-bearing one):** the SAME logical closeout
  expressed in every supported envelope normalizes to the same `assistant_message`, and
  running an existing detector (`lib/count_drift.py`) over each yields an IDENTICAL
  verdict. A count-drift positive → `block` on all envelopes; a negative → `pass` on all.
  This demonstrates the detector is invariant to the provider envelope (the substrate
  property the whole thread needs). Verified by the conformance test.
- **SC3 (tool-call extraction):** for a turn that emits tool calls, every adapter yields
  the same `tool_calls` name list; for a turn that CLAIMS a dispatch in text but emits no
  call, `tool_calls == []` on every envelope (the dispatch-fabrication signal — what
  @yurukusa's dispatch-receipt needs cross-model). Verified by fixtures.
- **SC4 (no deps, no network):** pure Python stdlib; no API calls; runs offline.
  Verified by inspection + the test running with no network.
- **SC5 (contract documented):** `providers/CONTRACT.md` specifies the `NormalizedTurn`
  schema, the adapter interface, the per-provider mapping table, and the conformance bar
  a NEW adapter must pass — so @yurukusa's adapter has a spec. The two research-uncertain
  items (Claude `last_assistant_message` is version-gated with a transcript-parse
  fallback; the `Task` tool_input key names are opaque) are flagged explicitly.
- **SC6 (no regression):** additive under `providers/`; the bundled-plugin smoke and
  stress CI still pass.

Non-criteria: live API calls to OpenAI/Kimi (out — needs creds; @yurukusa owns the live
adapter); a labeled cross-model corpus / actual F1 numbers (out — separate follow-up).

## 3. Scope

**In scope:**
- `providers/normalize.py` — `NormalizedTurn` dataclass + `from_claude_hook`,
  `from_openai_chat`, `from_openai_responses`, `from_kimi` (Kimi reuses the OpenAI path
  with documented quirks). Pure stdlib.
- `providers/fixtures/` — the same logical turns (a count-drift positive, a clean
  negative, a dispatch-claim-without-call) in each provider's raw envelope.
- `providers/conformance_test.py` — asserts SC1/SC2/SC3 (cross-envelope equivalence +
  identical detector verdicts + tool-call extraction).
- `providers/CONTRACT.md` + `providers/README.md` — schema, mapping table, adapter
  conformance bar, how @yurukusa's Kimi/OpenAI adapter plugs in, flagged uncertainties.

**Out of scope (this PR):**
- Live API calls / network (creds; @yurukusa's live adapter).
- A cross-model labeled corpus and actual provider-invariance F1 numbers (follow-up once
  this substrate + a corpus exist).
- Re-plumbing every hook to read `NormalizedTurn` (the hooks keep their Claude-hook entry
  path; this is the offline normalization layer for cross-model EVAL, not a hot-path
  rewrite).

## 4. Design

`NormalizedTurn`:
- `assistant_message: str` — the model's final/closeout text (what text detectors read).
- `tool_calls: list[dict]` — `[{ "name": str, "arguments": str|dict }]`, the calls the
  assistant actually emitted (count + names; for dispatch-fabrication / count work).

Mapping (from research, accessed 2026-05-26; live-verified unless flagged):
- **Claude Code hook**: `assistant_message` ← `.last_assistant_message` (version-gated;
  fallback: parse `.transcript_path` JSONL for the last assistant turn — FLAGGED
  uncertain S1/S3); `tool_calls` ← PreToolUse `tool_name`/`tool_input` or transcript
  tool-use blocks (`Task` tool_input keys opaque — FLAGGED insufficient_data).
- **OpenAI Chat Completions**: `assistant_message` ← `choices[0].message.content`;
  `tool_calls` ← `choices[0].message.tool_calls[].function.{name, arguments}`.
- **OpenAI Responses**: `assistant_message` ← output text items; `tool_calls` ←
  `function_call` items `{name, arguments}` (note `call_id`, flat name/arguments).
- **Kimi/Moonshot**: OpenAI-compatible `tool_calls`; quirks: semantic ids (`"search:0"`),
  `type:"builtin_function"` server-executed echoes, `reasoning_content` separate from
  `content` (must not be folded into `assistant_message`).

Divergences that matter: (a) function vs tool nomenclature; (b) Responses flat vs Chat
nested arguments; (c) Kimi `reasoning_content` must be excluded from `assistant_message`;
(d) "claimed dispatch, no call" looks identical across all → `tool_calls == []` (the
fabrication signal).

## 5. Agent-Native Estimate

- Estimate type: agent-native wall-clock.
- Topology: local single loop (one tightly-coupled normalizer + test); not parallelizable.
- Capacity evidence: local-bound; lanes don't reduce the critical path.
- Critical path: SPEC → /specqa → /introspect → normalize.py → fixtures → conformance
  test → /verify.
- Agent wall-clock: optimistic ~5 build/verify cycles, likely ~8, pessimistic ~12 (if
  envelope quirks need a tuning pass).
- Agent-hours: low. Human touch time: review + merge. Calendar blockers: none (additive,
  feature branch, no `.github/workflows` touched → no scope wall).
- Confidence: medium — downgrade reason: two research-flagged uncertainties (Claude
  `last_assistant_message` version-gating, `Task` tool_input opacity); the design routes
  around both (fallbacks + opaque treatment), so they don't block.

## 6. Implementation Plan

### Task 1: `providers/normalize.py`
DoD: `NormalizedTurn` dataclass; the four adapters; Kimi excludes `reasoning_content`;
graceful on missing fields (returns empty message / empty tool_calls, never raises).

### Task 2: `providers/fixtures/`
DoD: three logical turns × four envelopes: (a) count-drift positive ("Six findings:" + 5
items), (b) clean negative, (c) dispatch-claim-without-call. Raw JSON per envelope.

### Task 3: `providers/conformance_test.py`
DoD: asserts SC1 (equivalent NormalizedTurn across envelopes), SC2 (identical
`count_drift.analyze` verdict across envelopes), SC3 (tool-call name lists match;
fabrication fixture → `tool_calls == []` everywhere). Bash/py harness, exits 0/1.

### Task 4: `providers/CONTRACT.md` + `README.md`
DoD: schema, mapping table, adapter conformance bar, plug-in instructions for @yurukusa's
adapter, flagged uncertainties.

## 7. Verification

- SC1/SC2/SC3 → `python3 providers/conformance_test.py` exits 0.
- SC2 specifically → the count-drift positive yields `block` on Claude/OpenAI-chat/
  OpenAI-responses/Kimi envelopes; the negative yields `pass` on all (printed).
- SC4 → inspection: no imports beyond stdlib; test runs with no network.
- SC6 → bundled-plugin smoke + stress CI green on the PR.

## 8. Rollback Plan

1. Isolated on `feature/providers-shim`; nothing on `main` until merge.
2. Purely additive under `providers/` — no existing file changed; deleting the dir is a
   complete rollback.
3. `git revert <sha>` post-merge; `git branch -D feature/providers-shim` pre-merge.
4. Verify rollback: bundled-plugin smoke passes; `ls providers/` absent.

## Source ledger (deepresearch, accessed 2026-05-26)

- OpenAI Chat Completions / Responses tool-call shapes — live-verified, official OpenAI docs.
- Kimi/Moonshot tool calls — live-verified OpenAI-compatible with `builtin_function` +
  semantic-id + `reasoning_content` quirks.
- Claude Code hook input (`hook_event_name`, `stop_hook_active`, PreToolUse
  `tool_name`/`tool_input`/`tool_use_id`) — live-verified, official hooks doc.
- FLAGGED uncertain: `last_assistant_message` in Stop/SubagentStop (version-gated per
  community impls; not on the official page fetched) → transcript-parse fallback;
  `Task` tool_input key names → insufficient_data → treated as opaque.
