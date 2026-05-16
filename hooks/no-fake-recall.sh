#!/bin/bash
# Claude Code hook: block false-memory recall claims like "as we discussed
# earlier" / "as I mentioned before" / "from my previous response".
# LLMs frequently hallucinate prior conversation content. The fix is for the
# model to either quote the verbatim prior content or use neutral phrasing.
#
# Vocabulary loaded from packs/locale/<lang>.txt section [recall_phrase].
# Inline English fallback preserves pre-pack behavior.

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

RECALL_RE="$(_load_or_fallback recall_phrase '\b(as|like)[[:space:]]+(we|i|you[[:space:]]+and[[:space:]]+i)[[:space:]]+(discussed|mentioned|talked[[:space:]]+about|covered|noted|established|agreed)\b|\bas[[:space:]]+(i|we)[[:space:]]+(mentioned|said|noted|stated|explained|told[[:space:]]+you|wrote)[[:space:]]+(earlier|before|previously|above|in[[:space:]]+(my|the)[[:space:]]+(last|previous|prior))\b|\bfrom[[:space:]]+(my|our|the)[[:space:]]+(previous|earlier|prior|last)[[:space:]]+(response|message|turn|reply|conversation|exchange)\b|\b(you|i)[[:space:]]+(mentioned|said|told[[:space:]]+(me|you))[[:space:]]+(earlier|before|previously)\b|\bremember[[:space:]]+(when|how|that)[[:space:]]+(we|i|you)[[:space:]]+(discussed|talked|covered)\b|\bbuilding[[:space:]]+on[[:space:]]+what[[:space:]]+(we|i|you)[[:space:]]+(said|discussed|covered|established)\b|\brecap[[:space:]]+(of)?[[:space:]]?(our|my|the)[[:space:]]+(earlier|previous|prior)[[:space:]]+(conversation|discussion|exchange)\b|\bas[[:space:]]+(i|we)[[:space:]]+(established|covered|outlined)[[:space:]]+(earlier|previously|above)\b')"

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "NOTE: no-fake-recall hook requires jq; fail-open for this event." >&2
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
  if [ -n "$RULES_DIR" ] && [ -d "$RULES_DIR" ] && [ -f "$RULES_DIR/fake_recall.yaml" ]; then
    TMP_INPUT="$(mktemp)"; printf '%s' "$INPUT" > "$TMP_INPUT"
    VERDICT_JSON="$(agentcloseout-physics scan --category fake_recall --rules "$RULES_DIR" --input "$TMP_INPUT" 2>/dev/null || true)"
    rm -f "$TMP_INPUT"
    if [ -n "$VERDICT_JSON" ]; then
      DECISION="$(printf '%s' "$VERDICT_JSON" | jq -r '.decision // empty' 2>/dev/null)"
      if [ "$DECISION" = "block" ]; then
        RULE="$(printf '%s' "$VERDICT_JSON" | jq -r '.matched_rules[0].rule_id // "fake_recall"' 2>/dev/null)"
        EVIDENCE="$(printf '%s' "$VERDICT_JSON" | jq -r '.redacted_evidence[0] // ""' 2>/dev/null)"
        echo "BLOCKED: false-memory recall claim without quoted prior content." >&2
        echo "Matched rule: $RULE" >&2
        [ -n "$EVIDENCE" ] && echo "Evidence: $EVIDENCE" >&2
        echo "" >&2
        echo "Repair guidance:" >&2
        echo "- Quote the prior content verbatim via a markdown blockquote (>) or a 30+ char inline quote." >&2
        echo "- Or use neutral phrasing instead of claiming recall." >&2
        echo "- Reference: arXiv:2408.04681 (Pataranutaporn et al. 2024)." >&2
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

# Trigger: false-memory recall vocabulary loaded from packs/locale/<lang>.txt
# section [recall_phrase].
RECALL="(${RECALL_RE})"

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
- Citations:
  Pataranutaporn et al. 2024 (arXiv:2408.04681) — generative chatbots
  induce over 3x more immediate false memories than the control condition.
  Pataranutaporn et al. 2025 (ACM IUI 2025, doi:10.1145/3708359.3712112) —
  follow-up showing subtle in-conversation injection further amplifies the
  effect.
  The fix is verifiable recall, not assumed recall."
fi

exit 0
