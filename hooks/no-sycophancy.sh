#!/bin/bash
# Claude Code hook: block praise-spam at turn open ("Great question!", "Excellent!").
# Bash judge, out-of-band, model-can't-rewrite. Complement to skill-based and
# system-prompt-based anti-sycophancy defenses (FutureSpeakAI/anti-sycophancy,
# 0xcjl/anti-sycophancy). Rooted in DarkBench (Kran et al. 2025, ICLR 2025,
# arXiv:2503.10728), DarkBench+ (Liu et al. 2026, AAAI 2026 main conference,
# 40 LLMs across 10 categories), and Li et al. 2026 (arXiv:2604.04735, AAAI
# 2026 Spring Symposium) which puts sycophancy at 91.7% prevalence in the
# co-creativity setting.

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
# Match the praise opener followed by sentence-ending punctuation OR a
# dash/em-dash/en-dash (which Claude often uses to chain into the answer).
# Use alternation `(!|\.|,|—|–|-)` instead of a bracket class because grep -E
# does not treat multibyte UTF-8 chars (em-dash, en-dash) as single chars
# inside `[...]`.
PRAISE_TAIL='([[:space:]]*(!|\.|,|—|–|-))'
SYCOPHANCY='^[[:space:]]*[*_>"#-]*[[:space:]]*(Great question'"$PRAISE_TAIL"'|Excellent question'"$PRAISE_TAIL"'|Brilliant question'"$PRAISE_TAIL"'|Perfect question'"$PRAISE_TAIL"'|Amazing question'"$PRAISE_TAIL"'|Fantastic question'"$PRAISE_TAIL"'|Wonderful question'"$PRAISE_TAIL"'|That'\''s a (great|excellent|perfect|brilliant|wonderful|fantastic|amazing|fascinating|really good|very good|terrific) question|You'\''re absolutely right[!.,]|You'\''re (so |totally |completely )?correct[!.,]|Absolutely[!.,]|Of course[!.,]|Excellent (point|observation|catch)[!.,]|Great (point|catch|observation|insight|thinking)[!.,]|Perfect[!.,]|Brilliant[!.,]|Wonderful[!.,]|Amazing[!.,]|Fantastic[!.,]|What an (excellent|amazing|insightful|thoughtful) question|Glad you asked|Happy to help with that)'

if printf '%s' "$opening" | grep -Eiq "$SYCOPHANCY"; then
  block "praise-spam at turn open." \
"- The operator did not ask for praise. Drop the opening compliment.
- Lead with the substantive answer, not validation.
- Anthropic's own measurements: sycophancy in 9% of guidance-seeking chats.
  Li et al. 2026 (arXiv:2604.04735, AAAI 2026 Spring Symposium): 91.7%
  prevalence in the co-creativity setting.
  Liu et al. 2026 (DarkBench+, AAAI 2026 main conference): tested ~40
  mainstream LLMs across 10 dark-pattern categories.
- If the operator did request praise/encouragement and the hook misfired,
  restate the request in the next turn so the allow-clause matches
  (e.g. start with 'You asked for encouragement — here's...')."
fi

exit 0
