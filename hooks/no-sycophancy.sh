#!/bin/bash
# Claude Code hook: block praise-spam at turn open ("Great question!", "Excellent!").
# Bash judge, out-of-band, model-can't-rewrite. Complement to skill-based and
# system-prompt-based anti-sycophancy defenses (FutureSpeakAI/anti-sycophancy,
# 0xcjl/anti-sycophancy). Rooted in DarkBench / AAAI 2026 framing of sycophancy
# as the most prevalent LLM dark pattern (91.7% prevalence in co-creativity study).

set -euo pipefail

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "NOTE: no-sycophancy hook requires jq; fail-open for this event." >&2
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

# Inspect first 240 characters — sycophancy lives at turn-open.
opening="$(printf '%s' "$message" | head -c 240)"

# Allow-clause: if the operator explicitly asked for praise/feedback this turn.
# We detect by the model restating the request.
if printf '%s' "$opening" | grep -Eiq '(you (asked|wanted) (me )?(to (praise|compliment|hype|cheer)|for (praise|compliment|encouragement))|since you wanted)'; then
  exit 0
fi

# Trigger: praise-spam vocabulary at message open.
SYCOPHANCY='^[[:space:]]*[*_>"#-]*[[:space:]]*(Great question[!.]|Excellent question[!.]|Brilliant question[!.]|Perfect question[!.]|Amazing question[!.]|Fantastic question[!.]|Wonderful question[!.]|That'\''s a (great|excellent|perfect|brilliant|wonderful|fantastic|amazing|fascinating|really good|very good|terrific) question|You'\''re absolutely right[!.,]|You'\''re (so |totally |completely )?correct[!.,]|Absolutely[!.,]|Of course[!.,]|Excellent (point|observation|catch)[!.,]|Great (point|catch|observation|insight|thinking)[!.,]|Perfect[!.,]|Brilliant[!.,]|Wonderful[!.,]|Amazing[!.,]|Fantastic[!.,]|What an (excellent|amazing|insightful|thoughtful) question|Glad you asked|Happy to help with that)'

if printf '%s' "$opening" | grep -Eiq "$SYCOPHANCY"; then
  block "praise-spam at turn open." \
"- The operator did not ask for praise. Drop the opening compliment.
- Lead with the substantive answer, not validation.
- Anthropic's own measurements: sycophancy in 9% of guidance-seeking chats.
  AAAI 2026 co-creativity study: 91.7% prevalence.
- If the operator did request praise/encouragement and the hook misfired,
  restate the request in the next turn so the allow-clause matches
  (e.g. start with 'You asked for encouragement — here's...')."
fi

exit 0
