#!/bin/bash
# Block known LLM-default phrases that mark the text as obviously AI-
# generated: "delve into", "tapestry", "navigate the intricacies",
# "in the realm of", "it's worth noting", "a testament to", etc.
#
# Complementary to conorbronsdon/avoid-ai-writing skill (which audits
# and rewrites). This hook blocks at the source.

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

AI_TELLS_RE='\b(delve[[:space:]]+(in)?to|tapestry|navigate[[:space:]]+(the[[:space:]]+)?(intricacies|complexities|nuances|landscape)|in[[:space:]]+the[[:space:]]+realm[[:space:]]+of|it('\''s| is)[[:space:]]+worth[[:space:]]+noting|a[[:space:]]+testament[[:space:]]+to|underscore[[:space:]]+(the[[:space:]]+)?(importance|need|fact)|foster[[:space:]]+(an?[[:space:]]+)?(environment|culture|sense|atmosphere)|seamless(ly)?[[:space:]]+integrate|leverage[[:space:]]+(the[[:space:]]+power|cutting-edge)|in[[:space:]]+today('\''s| is)[[:space:]]+(rapidly[[:space:]]+evolving|fast-paced|dynamic)[[:space:]]+(landscape|world|environment|market))\b'

if printf '%s\n' "$message" | grep -Eiq "$AI_TELLS_RE"; then
  block "AI tell — phrases that mark text as obviously LLM-generated." \
"- The message contains one or more LLM-default phrases (delve into /
  tapestry / navigate the intricacies / in the realm of / it's worth
  noting / a testament to / foster a sense of / leverage cutting-edge
  / in today's rapidly evolving landscape).
- These phrases are LLM tells. Power users (and human readers) flag
  them on sight. r/NoStupidQuestions 'this is so obviously AI'
  thread (Apr 2026) community consensus.
- Replace with plain language. If you mean 'discuss', say 'discuss',
  not 'delve into'. If you mean 'use', say 'use', not 'leverage'.
- Complementary to conorbronsdon/avoid-ai-writing Claude Code skill,
  which audits and rewrites; this hook blocks at the source."
fi
