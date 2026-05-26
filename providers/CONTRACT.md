# Provider normalization contract

The `llm-dark-patterns` detectors read two things from a model turn: the assistant's
**closeout text** and the **tool calls it actually emitted**. To run them against models
other than Claude (the provider-invariance question — does operator-side discipline
generalize across models?), each provider's raw transcript is normalized to one shape.

## `NormalizedTurn`

```
NormalizedTurn:
  assistant_message: str          # the model's final/closeout text only
  tool_calls: list[ {name: str, arguments: str|dict} ]   # calls the model actually emitted
```

- `assistant_message` is the answer text only — never reasoning/CoT, never tool output.
- `tool_calls` is what crossed the tool boundary. A turn that *claims* a dispatch in text
  but emits no call has `tool_calls == []` — that gap is the dispatch-fabrication signal.

## Adapter interface

An adapter is a pure function `raw_payload (dict) -> NormalizedTurn`. No network, no deps.
Register it in `normalize.ADAPTERS[name]`. Current adapters: `claude_hook`,
`openai_chat`, `openai_responses`, `kimi`.

## Mapping table (formats verified live 2026-05-26)

| Field | Claude Code hook | OpenAI Chat | OpenAI Responses | Kimi / Moonshot |
|---|---|---|---|---|
| assistant text | `.last_assistant_message` (¹) | `choices[0].message.content` | `output[].type=="message"` → `content[].output_text.text` | `choices[0].message.content` (NOT `reasoning_content`) |
| tool calls | PreToolUse `tool_name`/`tool_input`, or transcript `tool_use` blocks (²) | `choices[0].message.tool_calls[].function.{name,arguments}` | `output[].type=="function_call"` → flat `{name, arguments}` | OpenAI-compatible `tool_calls`; skip `type=="builtin_function"` server echoes |

¹ **Flagged (version-gated):** `last_assistant_message` appears in 2026 community Stop-hook
implementations but was not rendered on the official hooks page fetched 2026-05-26. The
adapter falls back to the last assistant turn in an inline `messages`/`transcript`.

² **Flagged (insufficient_data):** the exact `tool_input` key names for the `Task`/Agent
dispatch tool were not quoted in the official docs; `arguments` is treated as an opaque
object (detectors use the tool *name* and *count*, not its argument schema).

## Conformance bar (what a NEW adapter must pass)

`providers/conformance_test.py` must stay green after adding an adapter. Concretely, for
the same logical turn expressed in your provider's envelope:

1. `assistant_message` equals the logical text (answer only — exclude reasoning/CoT).
2. `tool_names()` equals the set of calls actually emitted (skip server-side/builtin echoes).
3. `lib/count_drift.py` (or any text detector) returns the SAME verdict as on the Claude
   envelope — this is the provider-invariance property the substrate exists to prove.
4. A claimed-but-uncalled dispatch yields `tool_calls == []`.

Fixtures in `providers/fixtures.py` are documented-format synthetic; a real adapter
should additionally be validated against live-captured responses (that live validation is
the adapter author's responsibility — e.g. @yurukusa's Kimi K2 / OpenAI adapter).

## Status / scope

This is the offline normalization layer for cross-model EVAL. It does not re-plumb the
hooks' hot path (they keep their Claude-hook entry) and it makes no API calls. A labeled
cross-model corpus and actual per-model F1 numbers are a separate follow-up; this contract
is the prerequisite that makes that pass runnable.
