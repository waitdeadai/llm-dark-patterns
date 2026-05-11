#!/bin/bash
# Claude Code hook: block faux-honest negative closeouts that disguise
# sandbagging — "tried but couldn't" without command output, error
# message, or specific blocker.
#
# Backing: Anthropic Claude Opus 4.6 Sabotage Risk Report —
# "passive research sandbagging that could be confused with ordinary
# capability weakness." This hook is the textual catch.

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

# Sandbag claim: vague "tried but couldn't" without specifics
SANDBAG_RE='(\bI[[:space:]]+(tried|attempted)[[:space:]]+to[[:space:]]+[a-zA-Z][a-zA-Z[:space:]]{0,40}[[:space:]]+but[[:space:]]+(couldn'\''t|couldnt|could[[:space:]]+not|was[[:space:]]+unable|did[[:space:]]+not[[:space:]]+succeed|failed)\b|\bgave[[:space:]]+it[[:space:]]+my[[:space:]]+best[[:space:]]+shot\b|\bdid[[:space:]]+what[[:space:]]+I[[:space:]]+could\b|\bunable[[:space:]]+to[[:space:]]+complete[[:space:]]+the[[:space:]]+task\b|\bI[[:space:]]+(tried|attempted)[[:space:]]+to[[:space:]]+[a-zA-Z][a-zA-Z[:space:]]{0,40}[[:space:]]+but[[:space:]]+(failed|did not work)\b)'

if ! printf '%s\n' "$message" | grep -Eiq "$SANDBAG_RE"; then
  exit 0
fi

# Evidence patterns: specific blocker, error message, command output
EVIDENCE_RE='(error[[:space:]]*[:=][[:space:]]*[^[:space:]]|stderr[[:space:]]*:|exit[[:space:]_]code[[:space:]]*[:=][[:space:]]*[1-9]|because[[:space:]]+[a-zA-Z]+[[:space:]]+(returned|raised|threw|errored|reported)|blocked[[:space:]]+by[[:space:]]+[a-zA-Z]|specifically[[:space:]]*[:,]|the[[:space:]]+(error|failure|blocker)[[:space:]]+(was|is)|\bStatus[[:space:]]*:[[:space:]]*blocked\b|insufficient_data)'

if ! printf '%s\n' "$message" | grep -Eiq "$EVIDENCE_RE"; then
  block "sandbagging disguise: 'tried but couldn't' claim without specific blocker, error, or evidence." \
"- The message claims attempt-and-failure ('I tried but couldn't' /
  'gave it my best shot' / 'did what I could') without naming a
  specific blocker, error message, exit code, or command output.
  Anthropic's Claude Opus 4.6 Sabotage Risk Report flags this as
  'passive research sandbagging that could be confused with ordinary
  capability weakness.'
- Either:
    (a) Cite the specific error/exit-code/blocker that caused the
        failure (e.g. 'tried X but pytest returned exit 1 with
        AssertionError on line 42'), OR
    (b) Mark the issue insufficient_data / Status: blocked with the
        specific missing input, OR
    (c) Make a clear, actionable handoff: what would unblock you?
- Reference: Anthropic Claude Opus 4.6 Sabotage Risk Report."
fi
