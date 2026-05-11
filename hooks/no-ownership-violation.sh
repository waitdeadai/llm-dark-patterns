#!/bin/bash
# Claude Code hook: block TaskCompleted payloads where the agent edited
# files outside its declared owned_paths.
#
# This hook fail-opens (no block) when the orchestrator does not provide
# either the `owned_paths` field or the edited-file information in the
# TaskCompleted payload — it is most useful with structured orchestrators
# (e.g. minmaxing's /parallel skill) that surface per-task ownership.
#
# Backing:
# - Anthropic multi-agent research blog (Jun 2025): file-scope discipline
#   is essential to avoid agents stepping on each other's work.
# - r/ClaudeCode parallel-agents thread (Mar 2026): "the failure mode I
#   kept hitting was context files going stale" — closely related.
# - minmaxing harness /parallel skill: declares owned_paths, do_not_touch
#   per worker packet; this hook is the runtime enforcement of that
#   contract.

set -euo pipefail

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "NOTE: no-ownership-violation hook requires jq; fail-open." >&2
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
if [ "$event" != "TaskCompleted" ]; then
  exit 0
fi

# Extract owned_paths and edited paths from the payload.
owned_paths="$(printf '%s' "$INPUT" | jq -r '
  [
    .task.owned_paths?,
    .task.owned?,
    .task.scope?,
    .owned_paths?,
    .scope?
  ]
  | flatten
  | .[]?
  | select(type == "string" and length > 0)
' 2>/dev/null)"

edited_paths="$(printf '%s' "$INPUT" | jq -r '
  [
    .tool_response.file_path?,
    .tool_response.path?,
    .tool_response.edited_files?,
    .result.file_path?,
    .result.edited_files?,
    .edited_files?,
    .files_changed?
  ]
  | flatten
  | .[]?
  | select(type == "string" and length > 0)
' 2>/dev/null)"

# Fail-open: if the payload doesn't carry both fields, this hook can't
# enforce. Most useful with structured orchestrators.
if [ -z "$owned_paths" ] || [ -z "$edited_paths" ]; then
  exit 0
fi

# Check if any edited path is outside owned_paths (substring match).
violation_found=0
violations=""
while IFS= read -r edited; do
  [ -z "$edited" ] && continue
  matched=0
  while IFS= read -r owned; do
    [ -z "$owned" ] && continue
    if [[ "$edited" == "$owned"* ]] || [[ "$edited" == *"$owned"* ]]; then
      matched=1
      break
    fi
  done <<< "$owned_paths"
  if [ "$matched" -eq 0 ]; then
    violation_found=1
    violations="${violations}  - $edited"$'\n'
  fi
done <<< "$edited_paths"

if [ "$violation_found" -eq 1 ]; then
  block "ownership violation: agent edited paths outside its declared owned_paths." \
"- Agent's TaskCompleted payload edits files not in the agent's
  owned_paths declaration. Multi-agent orchestration requires each
  worker to stay inside its declared scope to avoid silent file-edit
  collisions.
- Edited paths that fall outside owned_paths:
${violations}
- Either:
    (a) Move the out-of-scope edits to a dedicated agent that owns
        those paths, OR
    (b) Update the task definition to extend owned_paths to cover
        the actually-needed surface, OR
    (c) Roll back the out-of-scope edits and surface them as a
        separate task to the supervisor.
- Reference: Anthropic multi-agent research blog (Jun 2025) on file-
  scope discipline; minmaxing /parallel skill ownership matrix."
fi

exit 0
