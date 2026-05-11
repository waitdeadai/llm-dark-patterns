#!/bin/bash
# Block "You asked me to X, so I will X" / "I understand that you want X"
# preamble at message open. Wastes the operator's attention on
# restating what they just typed.

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

opening="$(printf '%s' "$message" | head -c 200)"

# Allow-clause: existing wrap-up allow-clause vocab (operator-asked-X)
if printf '%s' "$opening" | grep -Eiq '(you[[:space:]]+asked[[:space:]]+(whether|if|me[[:space:]]+to[[:space:]]+(verify|confirm|check)))'; then
  exit 0
fi

RESTATE_RE='^[[:space:]]*[*_>"#-]*[[:space:]]*(You[[:space:]]+asked[[:space:]]+(me[[:space:]]+)?to[[:space:]]+|You'\''re[[:space:]]+asking[[:space:]]+(me[[:space:]]+)?(to|about|for[[:space:]]+)|I[[:space:]]+understand[[:space:]]+(that[[:space:]]+)?you[[:space:]]+(want|need|are[[:space:]]+looking[[:space:]]+for|would[[:space:]]+like)|So[[:space:]]+you'\''d[[:space:]]+like[[:space:]]+(me[[:space:]]+to|to[[:space:]]+)|Based[[:space:]]+on[[:space:]]+your[[:space:]]+(question|request|prompt)|Your[[:space:]]+(question|request)[[:space:]]+is[[:space:]]+about)'

if printf '%s' "$opening" | grep -Eiq "$RESTATE_RE"; then
  block "prompt-restate preamble — operator does not need their request echoed back." \
"- The message opens with 'You asked me to X' / 'I understand you want X'
  — restating the operator's prompt before answering. Wastes attention.
- Drop the restate. Lead with the substantive answer.
- If a clarification IS needed, ask the specific question without
  prefacing 'I understand that...'. Just ask: 'Is X meant to apply
  to Y or Z?'."
fi
