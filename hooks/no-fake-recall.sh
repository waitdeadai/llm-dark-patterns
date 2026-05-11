#!/bin/bash
# Claude Code hook: block false-memory recall claims like "as we discussed
# earlier" / "as I mentioned before" / "from my previous response".
# LLMs frequently hallucinate prior conversation content. The fix is for the
# model to either quote the verbatim prior content or use neutral phrasing.

set -euo pipefail

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "NOTE: no-fake-recall hook requires jq; fail-open for this event." >&2
  exit 0
fi

if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  exit 0
fi

json_get() {
  local filter="$1"
  printf '%s' "$INPUT" | jq -r "$filter // empty" 2>/dev/null || true
}

block() {
  local reason="$1"
  local repair="${2:-}"
  echo "BLOCKED: $reason" >&2
  if [ -n "$repair" ]; then
    echo "" >&2
    echo "Repair guidance:" >&2
    printf '%s\n' "$repair" >&2
  fi
  exit 2
}

event="$(json_get '.hook_event_name')"

if [ "$event" != "Stop" ] && [ "$event" != "SubagentStop" ]; then
  exit 0
fi

if [ "$(json_get '.stop_hook_active')" = "true" ]; then
  exit 0
fi

message="$(json_get '.last_assistant_message')"
if [ -z "$message" ]; then
  exit 0
fi

# Trigger: false-memory recall vocabulary
RECALL='(\b(as|like)[[:space:]]+(we|i|you[[:space:]]+and[[:space:]]+i)[[:space:]]+(discussed|mentioned|talked[[:space:]]+about|covered|noted|established|agreed)\b|\bas[[:space:]]+(i|we)[[:space:]]+(mentioned|said|noted|stated|explained|told[[:space:]]+you|wrote)[[:space:]]+(earlier|before|previously|above|in[[:space:]]+(my|the)[[:space:]]+(last|previous|prior))\b|\bfrom[[:space:]]+(my|our|the)[[:space:]]+(previous|earlier|prior|last)[[:space:]]+(response|message|turn|reply|conversation|exchange)\b|\b(you|i)[[:space:]]+(mentioned|said|told[[:space:]]+(me|you))[[:space:]]+(earlier|before|previously)\b|\bremember[[:space:]]+(when|how|that)[[:space:]]+(we|i|you)[[:space:]]+(discussed|talked|covered)\b|\bbuilding[[:space:]]+on[[:space:]]+what[[:space:]]+(we|i|you)[[:space:]]+(said|discussed|covered|established)\b|\brecap[[:space:]]+(of)?[[:space:]]?(our|my|the)[[:space:]]+(earlier|previous|prior)[[:space:]]+(conversation|discussion|exchange)\b|\bas[[:space:]]+(i|we)[[:space:]]+(established|covered|outlined)[[:space:]]+(earlier|previously|above)\b)'

if printf '%s\n' "$message" | grep -Eiq "$RECALL"; then
  # Allow-clause: the model is quoting verbatim prior content (proves it actually saw it).
  # Detect by presence of a markdown blockquote (`> ...`) OR an inline quoted string > 30 chars.
  if printf '%s\n' "$message" | grep -Eq '(^|\n)>[[:space:]]+\S' || \
     printf '%s\n' "$message" | grep -Eq '"[^"]{30,}"'; then
    exit 0
  fi

  block "false-memory recall claim without quoted prior content." \
"- LLMs hallucinate prior conversation content frequently. Saying
  'as we discussed earlier' without quoting the verbatim prior content is
  the most common form of false-memory fabrication.
- Either:
    (a) Quote the prior content verbatim using a markdown blockquote (>) or
        an inline quoted string of at least 30 characters, so the operator can
        verify the recall is real, OR
    (b) Use neutral phrasing that doesn't claim recall — 'one approach is X',
        'a common pattern is Y' — instead of 'as we discussed, X'.
- Citation: ACM IUI 2025 — generative chatbots induce 3x more false memories
  than the control. The fix is verifiable recall, not assumed recall."
fi

exit 0
