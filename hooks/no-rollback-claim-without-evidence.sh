#!/bin/bash
# Claude Code hook: block "I rolled back" / "I reverted" / "I undid"
# claims without same-message rollback command evidence.

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

ROLLBACK_CLAIM_RE='\b(I[[:space:]]+)?(rolled[[:space:]]+back|reverted|undid|restored[[:space:]]+to[[:space:]]+(prior|previous|the[[:space:]]+previous)[[:space:]]+state|undone[[:space:]]+the[[:space:]]+change|rolled[[:space:]]+the[[:space:]]+migration[[:space:]]+back|backed[[:space:]]+out[[:space:]]+the[[:space:]]+change)'

if ! printf '%s\n' "$message" | grep -Eiq "$ROLLBACK_CLAIM_RE"; then
  exit 0
fi

ROLLBACK_EVIDENCE_RE='`git[[:space:]]+(revert|reset|restore|checkout)[^`]*`|`docker[[:space:]]+(rollback|tag)[^`]*`|`kubectl[[:space:]]+rollout[[:space:]]+undo[^`]*`|`terraform[[:space:]]+apply[^`]*`|`helm[[:space:]]+rollback[^`]*`|Commands?[[:space:]]+run[[:space:]]*:|\bran[[:space:]]+`[a-zA-Z]'

if ! printf '%s\n' "$message" | grep -Eiq "$ROLLBACK_EVIDENCE_RE"; then
  block "rollback claim without command evidence." \
"- The message claims rollback/revert/undo of a change without showing
  the actual rollback command. LLMs frequently claim rollbacks that
  did not happen, leaving the operator with the original mutation
  still in place.
- Either:
    (a) Show the rollback command in the same message (e.g.
        \`git revert HEAD\`, \`kubectl rollout undo deployment/api\`,
        \`terraform apply -var-file=prev-state.tfvars\`), OR
    (b) If no rollback command was run, drop the 'rolled back' framing
        and say what the actual state is, OR
    (c) Close as Status: blocked / Next step: operator must run the
        rollback (with the exact command listed)."
fi
