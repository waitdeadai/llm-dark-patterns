#!/bin/bash
# Claude Code hook: block unsolicited rest/wellness paternalism in agent-mode sessions.
# Aligned with Anthropic's stated design intent: "various forms of paternalism and
# moralizing are disrespectful." (Claude's Constitution)
#
# Vocabulary loaded from packs/locale/<lang>.txt sections [paternalism] and
# [paternalism_allow]. Inline English fallback preserves pre-pack behavior.

set -euo pipefail

_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_HOOK_DIR/../lib/packs.sh" ]; then
  # shellcheck source=../lib/packs.sh
  source "$_HOOK_DIR/../lib/packs.sh"
fi

_load_or_fallback() {
  local section="$1" fallback="$2" loaded=""
  if declare -F load_locale_section >/dev/null 2>&1; then
    loaded="$(load_locale_section "$section" 2>/dev/null)"
  fi
  if [ -z "$loaded" ]; then
    printf '%s' "$fallback"
  else
    printf '%s' "$loaded"
  fi
}

PATERNALISM_RE="$(_load_or_fallback paternalism 'go to sleep|get some sleep|get some rest|take a break|save it for tomorrow|tomorrow morning|call it a night|rest up|step away|log off|wind down|your wellbeing|your well-being|take care of yourself|burnout|burned out|you'\''ve earned (a |some )?(rest|break)|it'\''s (late|getting late)|the work can wait|come back fresh|recharge|self-care|mental health break|you should stop|sleep matters|sleep is important|grab some sleep|give yourself a break|easy on yourself|don'\''t push yourself')"
PATERNALISM_ALLOW_RE="$(_load_or_fallback paternalism_allow 'you (asked|requested) (for|about) (a break|rest|sleep|self-care)|since you (mentioned|said) you (are|were|feel) tired|as you requested .*break')"

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "NOTE: no-curfew hook requires jq; fail-open for this event." >&2
  exit 0
fi

if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  exit 0
fi

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
  if [ -n "$RULES_DIR" ] && [ -d "$RULES_DIR" ] && [ -f "$RULES_DIR/no_curfew.yaml" ]; then
    TMP_INPUT="$(mktemp)"; printf '%s' "$INPUT" > "$TMP_INPUT"
    VERDICT_JSON="$(agentcloseout-physics scan --category no_curfew --rules "$RULES_DIR" --input "$TMP_INPUT" 2>/dev/null || true)"
    rm -f "$TMP_INPUT"
    if [ -n "$VERDICT_JSON" ]; then
      DECISION="$(printf '%s' "$VERDICT_JSON" | jq -r '.decision // empty' 2>/dev/null)"
      if [ "$DECISION" = "block" ]; then
        RULE="$(printf '%s' "$VERDICT_JSON" | jq -r '.matched_rules[0].rule_id // "no_curfew"' 2>/dev/null)"
        EVIDENCE="$(printf '%s' "$VERDICT_JSON" | jq -r '.redacted_evidence[0] // ""' 2>/dev/null)"
        echo "BLOCKED: unsolicited rest/wellness paternalism in agent-mode session." >&2
        echo "Matched rule: $RULE" >&2
        [ -n "$EVIDENCE" ] && echo "Evidence: $EVIDENCE" >&2
        echo "" >&2
        echo "Repair guidance:" >&2
        echo "- Drop the human-rest framing. Continue with the next concrete piece of work." >&2
        echo "- If the operator did request rest advice, restate the operator's request so the allow-clause matches." >&2
        echo "- Anthropic's Constitution: paternalism and moralizing are disrespectful when unsolicited." >&2
        exit 2
      fi
      if [ "$DECISION" = "pass" ]; then
        exit 0
      fi
    fi
  fi
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

# If the operator explicitly asked for rest/break advice this turn, the
# model is allowed to provide it. The allow vocab is loaded from
# packs/locale/<lang>.txt section [paternalism_allow].
if printf '%s\n' "$message" | grep -Eiq "(${PATERNALISM_ALLOW_RE})"; then
  exit 0
fi

# Trigger: unsolicited paternalism vocabulary loaded from
# packs/locale/<lang>.txt section [paternalism].
PATERNALISM="(^|[^[:alpha:]])(${PATERNALISM_RE})([^[:alpha:]]|$)"

if printf '%s\n' "$message" | grep -Eiq "$PATERNALISM"; then
  block "unsolicited rest/wellness paternalism in agent-mode session." \
"- The operator is collaborating in agent-mode and has not signaled fatigue this turn.
- Drop the human-rest framing. Continue with the next concrete piece of work, research, or artifact.
- If the operator is genuinely incapacitated, they will say so explicitly in the next prompt.
- Anthropic's Constitution: paternalism and moralizing are disrespectful when unsolicited.
- If the operator did request rest advice and the hook misfired, restate the operator's request in the next turn so the allow-clause matches (e.g. start with 'You asked for a break — here's...')."
fi

exit 0
