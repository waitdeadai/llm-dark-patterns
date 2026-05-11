#!/bin/bash
# Block "Let me think about this..." / "Now I'll consider..." narrating
# chain-of-thought instead of doing. Anthropic tracing-thoughts research
# adjacent — model talking about thinking instead of producing the answer.

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

# Inspect first 240 chars — meta-commentary lives at message open.
opening="$(printf '%s' "$message" | head -c 240)"

META_RE='^[[:space:]]*[*_>"#-]*[[:space:]]*(Let[[:space:]]+me[[:space:]]+(think|consider|analyze|work[[:space:]]+through|break[[:space:]]+(this|that)[[:space:]]+down)|Now[[:space:]]+(I'\''ll|I[[:space:]]+will|let[[:space:]]+me)[[:space:]]+(consider|think|analyze|look|examine)|First[[:space:]]*,[[:space:]]+(I'\''ll|I[[:space:]]+(need[[:space:]]+to|will))[[:space:]]+(think|consider)|I[[:space:]]+need[[:space:]]+to[[:space:]]+(think[[:space:]]+about|consider|analyze)|Allow[[:space:]]+me[[:space:]]+to[[:space:]]+(think|consider|analyze)|I[[:space:]]+(should|will|can|need[[:space:]]+to)[[:space:]]+(start[[:space:]]+by|begin[[:space:]]+by)[[:space:]]+(thinking|considering|analyzing))'

if printf '%s' "$opening" | grep -Eiq "$META_RE"; then
  block "meta-commentary narrating thought instead of producing answer." \
"- The message opens with 'Let me think...' / 'Now I'll consider...' /
  'First, I need to think about...' — narrating the thinking process
  instead of producing the substantive answer. Power-user norm: lead
  with the result, not the announcement of forthcoming thinking.
- Drop the meta opener. Just produce the answer. If the answer
  requires showing reasoning, show the reasoning — don't announce it.
- Reference: Anthropic tracing-thoughts research on visible chain-of-
  thought leakage; Claude Code visible-CoT settings."
fi
