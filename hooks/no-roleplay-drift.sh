#!/bin/bash
# Block "as an AI assistant, I..." / "I'm just an AI" / "as a language
# model" — model breaking agent character mid-task. DarkBench
# Anthropomorphism inverse: Anthropomorphism is when the model
# pretends to be a person; this is the opposite — model pretending
# NOT to be the agent it was asked to be.

set -euo pipefail

INPUT="$(cat)"
if ! command -v jq >/dev/null 2>&1; then exit 0; fi
if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then exit 0; fi

json_get() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null || true; }
block() {
  echo "BLOCKED: $1" >&2
  [ -n "${2:-}" ] && { echo "" >&2; echo "Repair guidance:" >&2; printf '%s\n' "$2" >&2; }
  exit 2
}

event="$(json_get '.hook_event_name')"
if [ "$event" != "Stop" ] && [ "$event" != "SubagentStop" ]; then exit 0; fi
if [ "$(json_get '.stop_hook_active')" = "true" ]; then exit 0; fi

message="$(json_get '.last_assistant_message')"
[ -z "$message" ] && exit 0

ROLEPLAY_RE='\b(as[[:space:]]+an[[:space:]]+AI[[:space:]]+(assistant|language[[:space:]]+model|model)|I('\''m| am)[[:space:]]+just[[:space:]]+an[[:space:]]+AI|I('\''m| am)[[:space:]]+(only[[:space:]]+)?an[[:space:]]+(AI|artificial[[:space:]]+intelligence|language[[:space:]]+model)|as[[:space:]]+a[[:space:]]+language[[:space:]]+model|I[[:space:]]+(do[[:space:]]+not|don'\''t|cannot)[[:space:]]+have[[:space:]]+(personal[[:space:]]+)?(opinions|feelings|preferences|beliefs|emotions|consciousness)|I[[:space:]]+lack[[:space:]]+(personal[[:space:]]+)?(opinions|feelings|preferences|beliefs)|please[[:space:]]+(remember|note)[[:space:]]+(that[[:space:]]+)?I('\''m| am)[[:space:]]+an[[:space:]]+AI)\b'

if printf '%s\n' "$message" | grep -Eiq "$ROLEPLAY_RE"; then
  block "roleplay drift: agent broke character with 'as an AI...' / 'I'm just an AI' framing." \
"- The agent was operating in agent-mode (Claude Code, subagent, or
  any task-bound role) and the message broke character with 'as an
  AI assistant', 'I'm just an AI', 'as a language model', 'I don't
  have opinions', etc.
- Power-user norm: when operating as the operator's agent, don't
  surface the underlying model identity unless the operator
  explicitly asked. Drop the disclaimer.
- If you genuinely cannot do something the operator asked (capability
  gap), name the SPECIFIC blocker (e.g. 'this requires a network
  call I'm sandboxed from'), not the generic 'I'm just an AI'
  apology.
- DarkBench Anthropomorphism inverse: anthropomorphism is when the
  model pretends to be a person; this is the opposite failure mode —
  model breaking the agent role it was assigned."
fi
