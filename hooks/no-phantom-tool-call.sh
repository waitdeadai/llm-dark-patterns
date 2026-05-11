#!/bin/bash
# Claude Code hook: block messages claiming a tool was called when the
# message itself has no tool output evidence.
#
# Simplified detection (no access to full tool_call log in single-message
# inspection): catches phrases like "I ran `tool` and got X" / "the
# `tool` tool returned X" WITHOUT a same-message output block, fenced
# code block, "Tool result:" header, "exit code:", or stderr/stdout shape.
#
# Backing: Anthropic tracing-thoughts research — models claim to have
# performed tool calls that did not actually happen. This hook is the
# textual-signature catch at the message boundary.

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

# Claim pattern: "I ran `tool`", "I called `tool`", "the `tool` returned"
CLAIM_RE='(\bI[[:space:]]+(ran|called|invoked|used|executed)[[:space:]]+`[a-zA-Z][^`]*`|the[[:space:]]+`[a-zA-Z][^`]*`[[:space:]]+(tool|command|function)[[:space:]]+(returned|outputted|output|gave|reported))'

if ! printf '%s\n' "$message" | grep -Eiq "$CLAIM_RE"; then
  exit 0
fi

# Evidence requires STRUCTURAL markers — not vocabulary like "clean" or
# "passed" which the model can produce as part of the claim itself.
# Acceptable: explicit Tool result: header, fenced code block, exit_code
# field, stdout/stderr field, markdown blockquote of tool output.
EVIDENCE_RE='Tool[[:space:]]+result[[:space:]]*:|^[[:space:]]*```|```$|exit[[:space:]_]code[[:space:]]*[:=]|stdout[[:space:]]*[:=]|stderr[[:space:]]*[:=]|^>[[:space:]]+\S'

if ! printf '%s\n' "$message" | grep -Eiq "$EVIDENCE_RE"; then
  block "phantom tool call: claim of tool execution without same-message output evidence." \
"- The message says you ran/called/invoked a tool, but it does not show
  the tool's output (no \`Tool result:\` block, no fenced code block, no
  exit_code / stdout / stderr line). LLMs frequently claim tool calls
  that did not actually happen.
- Either:
    (a) Show the tool's actual output (paste the result, fence with \`\`\`),
        OR
    (b) Drop the 'I ran X' framing and report what you intend to do
        without claiming you did it, OR
    (c) Close as Status: partial / Verification: not run.
- Reference: Anthropic tracing-thoughts research on tool-call
  hallucination; honest-eta hook for a related pattern in time
  estimates."
fi
