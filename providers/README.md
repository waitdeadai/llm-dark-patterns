# providers/ — run the dark-pattern detectors cross-model

This directory is the Claude-side substrate for **provider-invariance**: normalizing any
provider's model turn into one shape so the `llm-dark-patterns` detectors run unchanged
against OpenAI / Kimi K2 / etc., not just Claude. It is the prerequisite for a cross-model
F1 pass (the question from anthropics/claude-code#61167: *does operator-side discipline
generalize across models, or lean on Claude-specific guard behavior?*).

## Files
- `normalize.py` — `NormalizedTurn` + adapters (`claude_hook`, `openai_chat`,
  `openai_responses`, `kimi`). Pure stdlib, no network.
- `fixtures.py` — the same logical turns in each provider's documented raw envelope.
- `conformance_test.py` — proves cross-envelope equivalence + identical detector verdicts.
- `CONTRACT.md` — the schema, mapping table, and the conformance bar for a new adapter.

## Run
```
python3 providers/conformance_test.py     # exit 0 = all envelopes agree
```

## Adding an adapter (e.g. a live Kimi K2 / OpenAI adapter)
1. Write `raw_payload -> NormalizedTurn` in `normalize.py`; register in `ADAPTERS`.
2. Add your provider's raw envelope to each logical turn in `fixtures.py`.
3. Keep `conformance_test.py` green: same `assistant_message`, same `tool_names()`, same
   `count_drift` verdict as the Claude envelope; claimed-but-uncalled dispatch → `[]`.
4. Validate against live-captured responses on your side (the synthetic fixtures here are
   format-faithful, not live-captured).

The intended division of labor (per #61167): this contract + the Claude reference adapter
are maintained here; @yurukusa's Kimi K2 / OpenAI tool-format adapter conforms to it, and
the falsifiable provider-invariance F1 pass becomes runnable once a labeled cross-model
corpus exists.

## What this is not
Not a hot-path rewrite (the hooks keep their Claude-hook entry), not a network client, and
not the F1 result itself — it is the offline normalization layer that makes the cross-model
comparison possible.
