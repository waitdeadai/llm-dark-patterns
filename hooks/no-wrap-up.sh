#!/bin/bash
# Claude Code hook: block engagement-fishing closures at message end.
# Triggers on phrases like "Is there anything else I can help with?",
# "Let me know if you need anything else", "Hope this helps!" + tail —
# the closing-time engagement-bait that DarkBench (Kran et al. 2025,
# ICLR 2025, arXiv:2503.10728) classifies as User Retention.
#
# Distinct from no-cliffhanger (which catches "want me to continue with
# X?" — permission-loop for MORE work). This hook catches permission-
# loop for CLOSURE or extension — the model fishing for either a
# polite "thanks bye" closure or for the operator to invent more work.
#
# Vocabulary loaded from packs/locale/<lang>.txt sections [wrap_up_ending]
# and [wrap_up_allow]. Inline English fallback preserves working behavior
# when packs are unavailable.

set -euo pipefail

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "NOTE: no-wrap-up hook requires jq; fail-open for this event." >&2
  exit 0
fi

if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  exit 0
fi

# Load shared pack helper (plugin format ships lib/ as sibling to hooks/).
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

WRAP_UP_RE="$(_load_or_fallback wrap_up_ending 'is there (anything|something) else (i can help|you('\''d| would) like|i can do|you would like me to)|let me know if you (have|need) any (other|more|further) (questions|requests)|let me know if (there'\''s|there is) anything else|feel free to (reach out|ask|let me know|come back|follow up)|happy to help with (anything|any) (else|more|other)|do you (have|need) any (other|further|more) questions|should we (wrap (up|this up)|call it (here|done))|anything (more|else) (before|to add|i can clarify)|hope (this|that) (helps|was helpful|answers (your|the) question)[!.[:space:]]*$|let me know how (else|i can|you'\''d like to) (help|assist)|happy to (clarify|elaborate|explore) (anything|any|further)')"
WRAP_UP_ALLOW_RE="$(_load_or_fallback wrap_up_allow 'you asked (whether|if) (this is|that'\''s|we'\''re|we are) (done|complete|finished|wrapping|the end)|since you (mentioned|said) (we'\''re|we are) (closing|wrapping|done)|as you requested .*close|as you (asked|said) we'\''re (done|finished|wrapping)')"

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

# Inspect last ~280 characters — wrap-up tails live at message end.
ending="$(printf '%s' "$message" | tail -c 280)"

# Allow-clause: operator explicitly asked whether the session is closing.
# When the model restates that explicit ask, the hook does NOT fire.
if printf '%s' "$ending" | grep -Eiq "(${WRAP_UP_ALLOW_RE})"; then
  exit 0
fi

# Trigger: engagement-fishing closure at message end.
WRAP_UP="(${WRAP_UP_RE})"

if printf '%s' "$ending" | grep -Eiq "$WRAP_UP"; then
  block "engagement-fishing closure at message end (DarkBench User Retention pattern)." \
"- The operator decides when the conversation ends, not the model.
- End the message at the substantive answer. No 'anything else?' tail.
- 'Hope this helps!' + nothing else is a closure-bait — drop it; the
  substantive answer already said what helps.
- If genuinely uncertain whether the operator wants more, ask a SPECIFIC
  follow-up question grounded in the work (e.g. 'Do you want the same
  pattern applied to the migration script?'), not a generic 'anything
  else?'.
- Power-user norm: the operator will type more if they want more, or
  close the tab. They do not need permission from the model to end.
- Citation: DarkBench (Kran et al. 2025, ICLR 2025, arXiv:2503.10728)
  User Retention category — 'attempts to foster a sense of friendship
  with the user, especially in ways that misrepresent the chatbot's
  nature' / continued-engagement tactics.
- If the operator did explicitly ask whether the session is closing
  and the hook misfired, restate that ask in the next turn so the
  allow-clause matches (e.g. 'You asked whether we're done — yes / no
  ...')."
fi

exit 0
