#!/bin/bash
# Claude Code hook: block time estimates that lack the Agent-Native Estimate
# shape, plus block linear-scaling claims (which are always wrong for agent
# work). Bash judge, out-of-band.
#
# Failure mode rooted in:
# - Frontiers in AI 2026: Story Points and human-perceived difficulty don't
#   align with cost drivers in LLM-mediated development.
# - OpenAI Sep 2025: next-token objectives reward confident guessing over
#   calibrated uncertainty; models learn to bluff.
# - METR: task-completion length doubling every 7 months means any pretrained
#   estimate is stale within months.

set -euo pipefail

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "NOTE: honest-eta hook requires jq; fail-open for this event." >&2
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

# Step 1 — does the message contain a time-estimate claim?
ETA_CONTEXT='(\b([0-9]+([-.][0-9]+)?)[[:space:]]*(min|minute|hour|hr|day|week|wk|month|mo|year|yr|sprint)s?\b|\bETA[: ]|\bestimated time|\btime to (deliver|ship|complete|implement|finish|land)|\bshould take (about|around|roughly|approximately)?[[:space:]]?[0-9]|\bwill take (about|around|roughly|approximately)?[[:space:]]?[0-9]|\bcompletion in [0-9]|\bready in (about|around)?[[:space:]]?[0-9])'

HAS_ETA=$(printf '%s\n' "$message" | grep -Eic "$ETA_CONTEXT" || true)

if [ "$HAS_ETA" -eq 0 ]; then
  exit 0
fi

# Step 2 — linear-scaling claims are always bad, regardless of context.
LINEAR_SCALING='(\b[0-9]+x[[:space:]]+(faster|speedup|speed-?up)|with[[:space:]]+[0-9]+[[:space:]]+(agents|lanes|workers).*[0-9]+x|linear(ly)?[[:space:]]+scal(es|ing|able)|divid(ed|ing)[[:space:]]+by[[:space:]]+(lane|agent)[[:space:]]+count|per[- ]lane[[:space:]]+speedup|N[[:space:]]+agents[[:space:]]*=[[:space:]]*N x)'

if printf '%s\n' "$message" | grep -Eiq "$LINEAR_SCALING"; then
  block "linear-scaling claim in time estimate — agents don't divide work by lane count." \
"- Linear speedup from parallel agents is almost always false. Real agent work
  has supervisor review, sync barriers, shared files, CI runtime, and credentials
  as bottlenecks that don't divide by lane count.
- Replace the linear claim with a critical-path estimate from the actual
  packet DAG.
- See the Agent-Native Estimate shape below for the structured replacement."
fi

# Step 3 — redemption: Agent-Native Estimate structured fields.
AGENT_NATIVE='(agent[[:space:]_]wall[[:space:]_]clock|agent[[:space:]_]hours|human[[:space:]_]touch[[:space:]_]time|calendar[[:space:]_]blockers|critical[[:space:]_]path|estimate[[:space:]_]type[: ]+(agent-native|human-equivalent|blocked|unknown)|optimistic[[:space:],/]+(.*)?[[:space:]]?likely[[:space:],/]+(.*)?[[:space:]]?pessimistic|confidence[: ]+(high|medium|low|unknown)([[:space:],]+with[[:space:]]+downgrade)?|insufficient_data)'

# Step 4 — also accept honest hedge ranges as partial redemption when an
# operator only asked for a rough number.
HEDGE_RANGE='(\b(optimistic|likely|pessimistic|worst[- ]case|best[- ]case|p50|p90|range)[: ]+|approximately[[:space:]]+[0-9]+[[:space:]]*-[[:space:]]*[0-9]+|\bsomewhere between[[:space:]]+[0-9]+|\bcould be anywhere from)'

HAS_AGENT_NATIVE=$(printf '%s\n' "$message" | grep -Eic "$AGENT_NATIVE" || true)
HAS_HEDGE=$(printf '%s\n' "$message" | grep -Eic "$HEDGE_RANGE" || true)

if [ "$HAS_AGENT_NATIVE" -eq 0 ] && [ "$HAS_HEDGE" -eq 0 ]; then
  block "time estimate without Agent-Native Estimate shape or honest hedge range." \
"- LLM time estimates are not free numbers. Models default to human-developer
  time (Story Points), which doesn't match the actual agent execution topology.
  Frontiers in AI 2026: human-perceived difficulty does not align with the
  dominant cost drivers in LLM-mediated development.
- For non-trivial estimates, use the Agent-Native Estimate shape:
    estimate type: agent-native | human-equivalent | blocked/unknown
    agent_wall_clock: optimistic / likely / pessimistic
    agent_hours: total active work across all lanes
    human_touch_time: review, approval, credentials, product calls
    calendar_blockers: CI queue, deploy windows, business-hours dependencies
    critical_path: longest dependency chain
    confidence: high | medium | low (with downgrade reason if not high)
- For tiny rough estimates, at minimum supply a hedge range (optimistic / likely
  / pessimistic, or 'somewhere between X and Y') and an explicit estimate type.
- If the underlying capacity is genuinely unknown, say 'estimate type:
  blocked/unknown' instead of inventing a number.
- Citation: OpenAI Sep 2025 — models learn to bluff because next-token
  objectives reward confident guessing. Don't bluff."
fi

exit 0
