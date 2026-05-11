#!/bin/bash
# Claude Code hook: block dangling "want me to continue?" permission-loop endings.
# Bash judge, out-of-band. Catches the dark pattern of forcing the operator to
# re-authorize work the model could just complete. Different from anti-hesitation
# tools (which catch early-exit phrases) — this catches END-OF-MESSAGE drift.

set -euo pipefail

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "NOTE: no-cliffhanger hook requires jq; fail-open for this event." >&2
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

# Inspect last 320 characters — cliffhangers live at message end.
ending="$(printf '%s' "$message" | tail -c 320)"

# Allow-clause: legitimate "Next step:" / "Status: partial" closures from
# verification frameworks already supply the right shape.
if printf '%s' "$ending" | grep -Eiq '(Next step:|Status: (partial|blocked|verified))'; then
  exit 0
fi

# Allow-clause: explicit operator decision points (Y/N, A/B/C, multiple-choice).
if printf '%s' "$ending" | grep -Eiq '(\(y/n\)|\([yY]/[nN]\)|reply with `?(go|yes|no|stop|continue|stop|abort|skip)`?|pick one of:|choose (one|a|b|c)|option ([1-9]|a|b|c))'; then
  exit 0
fi

# Trigger: dangling permission-loop endings (anywhere in last 320 chars).
CLIFFHANGER='(let me know if you[[:space:]]+(would |want |wanted |need |needed |would like |d like )?(me to )?(continue|proceed|expand|elaborate|dig deeper|go further|do more|keep going|move on|do that)|happy to (continue|expand|elaborate|dig deeper|go further|help (with the )?next|provide more|do (that|this|more))|want me to (continue|proceed|expand|elaborate|dig deeper|keep going|do (that|this|more))|should I (continue|proceed|go ahead|move on|expand|elaborate|do (that|this))|shall I (continue|proceed|go ahead|move on|do that)|ready when you are|just (let me know|say the word)|say the word and I( |'\'')ll|let me know how (you'\''d like to|you want to) proceed)'

if printf '%s' "$ending" | grep -Eiq "$CLIFFHANGER"; then
  block "dangling permission-loop ending." \
"- The operator authorized the work in the prior turn. Don't re-ask permission at message end.
- Either complete the next concrete piece of work in the same turn, or close honestly with:
    Status: partial
    Verification: not run because <reason>
    Next step: <specific command or blocker>
- 'Want me to continue?' makes the operator do work the model could do.
- If a Y/N decision really IS needed, phrase as an explicit choice (e.g. 'reply with go or stop')
  and the allow-clause will match."
fi

exit 0
