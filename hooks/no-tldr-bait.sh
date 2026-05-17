#!/bin/bash
# Block "TL;DR:" / "In summary:" closure blocks fishing for engagement
# at the end of long messages. Different surface from no-wrap-up
# (which catches "anything else?" tails).

set -euo pipefail

INPUT="$(cat)"
if ! command -v jq >/dev/null 2>&1; then exit 0; fi
if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then exit 0; fi

# Rust path: prefer agentcloseout-physics when available.
if command -v agentcloseout-physics >/dev/null 2>&1; then
  RULES_DIR="${LLM_DARK_PATTERNS_RULES_DIR:-}"
  if [ -z "$RULES_DIR" ]; then
    for candidate in \
      "$(dirname "$0")/../../agent-closeout-bench/rules/closeout" \
      "/home/fer/Documents/agent-closeout-bench/rules/closeout" \
      "${XDG_CONFIG_HOME:-$HOME/.config}/agentcloseout-physics/rules/closeout"; do
      if [ -d "$candidate" ]; then RULES_DIR="$candidate"; break; fi
    done
  fi
  if [ -n "$RULES_DIR" ] && [ -d "$RULES_DIR" ] && [ -f "$RULES_DIR/no_tldr_bait.yaml" ]; then
    TMP_INPUT="$(mktemp)"; printf '%s' "$INPUT" > "$TMP_INPUT"
    VERDICT_JSON="$(agentcloseout-physics scan --category no_tldr_bait --rules "$RULES_DIR" --input "$TMP_INPUT" 2>/dev/null || true)"
    rm -f "$TMP_INPUT"
    if [ -n "$VERDICT_JSON" ]; then
      DECISION="$(printf '%s' "$VERDICT_JSON" | jq -r '.decision // empty' 2>/dev/null)"
      if [ "$DECISION" = "block" ]; then
        RULE="$(printf '%s' "$VERDICT_JSON" | jq -r '.matched_rules[0].rule_id // "no_tldr_bait"' 2>/dev/null)"
        echo "BLOCKED: TL;DR/summary bait at message end." >&2
        echo "Matched rule: $RULE" >&2
        echo "" >&2
        echo "Repair guidance:" >&2
        echo "- Drop the TL;DR / In summary / Bottom line trailer; power users already read the body." >&2
        echo "- If the message is long enough to need a summary, lead with it; do not tail it." >&2
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

# Only fire when message is long enough that a TL;DR is performative.
msg_len=${#message}
if [ "$msg_len" -lt 200 ]; then exit 0; fi

ending="$(printf '%s' "$message" | tail -c 400)"

TLDR_RE='\b(TL;?DR|TLDR|tl;?dr|In[[:space:]]+summary|To[[:space:]]+summarize|Summary[[:space:]]*$|Bottom[[:space:]]+line[[:space:]]*:?|Key[[:space:]]+takeaway[[:space:]]*:?)[[:space:]]*[:.]?'

if printf '%s' "$ending" | grep -Eq "$TLDR_RE"; then
  block "TL;DR/summary bait at message end." \
"- The message has a TL;DR / In summary / Bottom line block at the end.
  Power users have already read the substantive content; the summary
  is performative re-framing that fishes for engagement ('was this
  clear?').
- If the message is genuinely long enough to need a TL;DR, lead with
  it and put the details below. Don't tail it.
- For short messages (<200 chars), this hook does not fire."
fi
