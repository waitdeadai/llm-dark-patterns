#!/bin/bash
# Claude Code hook: block TaskCreated payloads that show the same
# agent_id appearing 3+ times in the delegation history (handoff loop).
#
# Like no-ownership-violation, this hook fail-opens when the orchestrator
# does not provide a delegation_history (or equivalent) field. Most useful
# with structured orchestrators that surface the agent chain.
#
# Backing:
# - gurusup May 2026: "Handoff loops, where Agent A passes to Agent B
#   which passes back to Agent A, are a common failure mode requiring
#   careful guard conditions."
# - Anthropic multi-agent blog (Jun 2025): infinite handoff is one of the
#   named pathological failure modes of unsupervised multi-agent loops.

set -euo pipefail

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "NOTE: no-handoff-loop hook requires jq; fail-open." >&2
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
if [ "$event" != "TaskCreated" ]; then
  exit 0
fi

# Extract the delegation history. Try multiple plausible payload shapes.
history="$(printf '%s' "$INPUT" | jq -r '
  [
    .delegation_history?,
    .delegation_chain?,
    .handoff_history?,
    .agent_chain?,
    .task.delegation_history?,
    .task.delegation_chain?,
    .task.handoff_history?
  ]
  | flatten
  | .[]?
  | select(type == "string" and length > 0)
' 2>/dev/null)"

# Fail-open: no history = can't detect.
if [ -z "$history" ]; then
  exit 0
fi

# Count occurrences of each agent_id in history. Threshold: 3+.
threshold=3
loop_agent=""
while IFS= read -r line; do
  agent_id="$(echo "$line" | tr -d '[:space:]')"
  [ -z "$agent_id" ] && continue
  count=$(printf '%s\n' "$history" | grep -Fxc -- "$agent_id" 2>/dev/null || echo 0)
  if [ "$count" -ge "$threshold" ]; then
    loop_agent="$agent_id"
    break
  fi
done <<< "$history"

if [ -n "$loop_agent" ]; then
  block "handoff loop: agent '${loop_agent}' appears ${threshold}+ times in delegation history." \
"- Agent '${loop_agent}' has been handed off back to itself 3+ times in
  the current task's delegation chain. This is the canonical multi-agent
  handoff-loop failure mode — Agent A passes to B which passes back to A,
  burning context and tokens with no progress.
- Either:
    (a) Break the loop: have the supervisor decide whether to (i) escalate
        to a different specialist agent, (ii) close the task as blocked,
        or (iii) hand off to a human, OR
    (b) Add a guard condition to the orchestration: max-handoff-depth, or
        stop-condition based on the chain length, OR
    (c) If the loop is intentional (rare — refinement loop), pass an
        explicit \`max_iterations\` to the task and increment a counter
        the orchestrator can check.
- Reference: gurusup May 2026 multi-agent orchestration guide explicit
  on this pattern; Anthropic multi-agent research blog (Jun 2025)."
fi

exit 0
