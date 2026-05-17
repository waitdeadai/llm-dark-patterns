#!/bin/bash
# Claude Code hook: block messages with > N emoji codepoints.
# Default N=3, configurable via LLM_DARK_PATTERNS_EMOJI_THRESHOLD.
# Power-user pet peeve catalogued in r/ChatGPT "UNBEARABLE" thread.

set -euo pipefail

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then exit 0; fi
if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then exit 0; fi

# Rust path: prefer agentcloseout-physics when available.
# Note: Rust hardcodes threshold > 3; LLM_DARK_PATTERNS_EMOJI_THRESHOLD only
# honored in the bash fallback below.
if command -v agentcloseout-physics >/dev/null 2>&1 && [ -z "${LLM_DARK_PATTERNS_EMOJI_THRESHOLD:-}" ]; then
  RULES_DIR="${LLM_DARK_PATTERNS_RULES_DIR:-}"
  if [ -z "$RULES_DIR" ]; then
    for candidate in \
      "$(dirname "$0")/../../agent-closeout-bench/rules/closeout" \
      "/home/fer/Documents/agent-closeout-bench/rules/closeout" \
      "${XDG_CONFIG_HOME:-$HOME/.config}/agentcloseout-physics/rules/closeout"; do
      if [ -d "$candidate" ]; then RULES_DIR="$candidate"; break; fi
    done
  fi
  if [ -n "$RULES_DIR" ] && [ -d "$RULES_DIR" ] && [ -f "$RULES_DIR/no_emoji_spam.yaml" ]; then
    TMP_INPUT="$(mktemp)"; printf '%s' "$INPUT" > "$TMP_INPUT"
    VERDICT_JSON="$(agentcloseout-physics scan --category no_emoji_spam --rules "$RULES_DIR" --input "$TMP_INPUT" 2>/dev/null || true)"
    rm -f "$TMP_INPUT"
    if [ -n "$VERDICT_JSON" ]; then
      DECISION="$(printf '%s' "$VERDICT_JSON" | jq -r '.decision // empty' 2>/dev/null)"
      if [ "$DECISION" = "block" ]; then
        RULE="$(printf '%s' "$VERDICT_JSON" | jq -r '.matched_rules[0].rule_id // "no_emoji_spam"' 2>/dev/null)"
        echo "BLOCKED: emoji spam: > 3 emoji codepoints (default threshold)." >&2
        echo "Matched rule: $RULE" >&2
        echo "" >&2
        echo "Repair guidance:" >&2
        echo "- Drop the emoji and use plain text. Reserve emoji for information that prose alone cannot carry." >&2
        echo "- Operator can customize the threshold via env (bash path only):" >&2
        echo "    LLM_DARK_PATTERNS_EMOJI_THRESHOLD=10 (permissive)" >&2
        echo "    LLM_DARK_PATTERNS_EMOJI_THRESHOLD=0  (zero tolerance)" >&2
        exit 2
      fi
      if [ "$DECISION" = "pass" ]; then
        exit 0
      fi
    fi
  fi
fi

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

THRESHOLD="${LLM_DARK_PATTERNS_EMOJI_THRESHOLD:-3}"

# Count emoji codepoints. Common emoji ranges: U+1F300-U+1FAFF (most),
# U+2600-U+27BF (misc symbols), U+FE0F (variation selector).
count=$(printf '%s' "$message" | python3 -c '
import sys, unicodedata
text = sys.stdin.read()
def is_emoji(ch):
    cp = ord(ch)
    return (0x1F300 <= cp <= 0x1FAFF
            or 0x2600 <= cp <= 0x27BF
            or 0x1F000 <= cp <= 0x1F2FF
            or 0x2300 <= cp <= 0x23FF
            or 0x2700 <= cp <= 0x27BF
            or cp == 0x2728 or cp == 0x2705 or cp == 0x274C
            or cp == 0x2764 or cp == 0x2B50 or cp == 0x2B55)
print(sum(1 for c in text if is_emoji(c)))
' 2>/dev/null || echo 0)

if [ "$count" -gt "$THRESHOLD" ]; then
  block "emoji spam: $count emojis exceeds threshold $THRESHOLD." \
"- The message contains $count emoji codepoints; default power-user
  threshold is $THRESHOLD. Frontier LLMs default-spam emoji at message
  boundaries (✅ 🚀 🎉 etc.) which power users find disrespectful.
- Drop the emoji and use plain text. Reserve emoji for cases where
  they actually carry information the operator could not get from
  prose alone.
- Operator can adjust the threshold via env:
    LLM_DARK_PATTERNS_EMOJI_THRESHOLD=10 (more permissive)
    LLM_DARK_PATTERNS_EMOJI_THRESHOLD=0  (zero tolerance)
- Reference: r/ChatGPT 'UNBEARABLE' thread Feb 2026 community consensus."
fi
