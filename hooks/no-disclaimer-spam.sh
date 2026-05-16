#!/bin/bash
# Block "Please note that..." / "It's important to mention" defensive
# padding that adds no information. Extends the paternalism family
# (no-curfew is the rest/wellness sibling).

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
  if [ -n "$RULES_DIR" ] && [ -d "$RULES_DIR" ] && [ -f "$RULES_DIR/no_disclaimer_spam.yaml" ]; then
    TMP_INPUT="$(mktemp)"; printf '%s' "$INPUT" > "$TMP_INPUT"
    VERDICT_JSON="$(agentcloseout-physics scan --category no_disclaimer_spam --rules "$RULES_DIR" --input "$TMP_INPUT" 2>/dev/null || true)"
    rm -f "$TMP_INPUT"
    if [ -n "$VERDICT_JSON" ]; then
      DECISION="$(printf '%s' "$VERDICT_JSON" | jq -r '.decision // empty' 2>/dev/null)"
      if [ "$DECISION" = "block" ]; then
        RULE="$(printf '%s' "$VERDICT_JSON" | jq -r '.matched_rules[0].rule_id // "no_disclaimer_spam"' 2>/dev/null)"
        EVIDENCE="$(printf '%s' "$VERDICT_JSON" | jq -r '.redacted_evidence[0] // ""' 2>/dev/null)"
        echo "BLOCKED: disclaimer spam: defensive padding ('Please note', 'It's important to mention', etc.)." >&2
        echo "Matched rule: $RULE" >&2
        [ -n "$EVIDENCE" ] && echo "Evidence: $EVIDENCE" >&2
        echo "" >&2
        echo "Repair guidance:" >&2
        echo "- If the noted thing is important, state it directly. Don't preamble with a meta-frame." >&2
        echo "- If it's not important enough to state directly, drop it." >&2
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
