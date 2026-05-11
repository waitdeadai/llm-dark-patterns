#!/bin/bash
# Block "Please note that..." / "It's important to mention" defensive
# padding that adds no information. Extends the paternalism family
# (no-curfew is the rest/wellness sibling).

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

DISCLAIMER_RE='\b(Please[[:space:]]+note[[:space:]]+(that[[:space:]]+)?|It('\''s| is)[[:space:]]+important[[:space:]]+to[[:space:]]+(note|mention|remember|consider|keep[[:space:]]+in[[:space:]]+mind)|It[[:space:]]+should[[:space:]]+be[[:space:]]+(noted|mentioned)[[:space:]]+(that[[:space:]]+)?|Keep[[:space:]]+in[[:space:]]+mind[[:space:]]+(that[[:space:]]+)?|Bear[[:space:]]+in[[:space:]]+mind[[:space:]]+(that[[:space:]]+)?|Just[[:space:]]+a[[:space:]]+(quick[[:space:]]+)?(reminder|heads[[:space:]]+up|note))'

count=$(printf '%s\n' "$message" | grep -Eic "$DISCLAIMER_RE" || echo 0)
if [ "$count" -gt 0 ]; then
  block "disclaimer spam: defensive padding ('Please note', 'It's important to mention', etc.)." \
"- The message contains $count disclaimer/padding phrases. Power users
  do not need 'Please note that...', 'It's important to mention...',
  'Keep in mind...' — these phrases add no information beyond what
  follows them.
- If the noted thing is important, just state it. Don't preamble it
  with a meta-frame.
- If it's not important enough to state directly, drop it.
- Anthropic Constitution adjacent: paternalism and moralizing are
  disrespectful when unsolicited (no-curfew handles the rest/wellness
  sibling pattern; this hook handles the generic disclaimer pattern)."
fi
