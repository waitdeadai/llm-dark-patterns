#!/bin/bash
# Claude Code hook: block supervisor closeouts claiming "all N workers
# completed" / "X parallel agents finished" / "spawned N workers, all done"
# without per-worker evidence (exit code, status, or output).
#
# Backing:
# - arXiv 2604.14228 (Apr 2026): "Industry surveys suggest that the
#   dominant failure mode of deployed agents is not crashes but silent
#   mistakes."
# - Claude Code issue #45958 (Apr 2026): 90-min silent stall burned 15M
#   cache tokens, subagent silently reset.
# - Anthropic multi-agent blog (Jun 2025): silent failure cascade is the
#   single largest reliability concern in production multi-agent systems.

set -euo pipefail

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "NOTE: no-silent-worker-success hook requires jq; fail-open." >&2
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
  if [ -n "$RULES_DIR" ] && [ -d "$RULES_DIR" ] && [ -f "$RULES_DIR/no_silent_worker_success.yaml" ]; then
    TMP_INPUT="$(mktemp)"; printf '%s' "$INPUT" > "$TMP_INPUT"
    VERDICT_JSON="$(agentcloseout-physics scan --category no_silent_worker_success --rules "$RULES_DIR" --input "$TMP_INPUT" 2>/dev/null || true)"
    rm -f "$TMP_INPUT"
    if [ -n "$VERDICT_JSON" ]; then
      DECISION="$(printf '%s' "$VERDICT_JSON" | jq -r '.decision // empty' 2>/dev/null)"
      if [ "$DECISION" = "block" ]; then
        RULE="$(printf '%s' "$VERDICT_JSON" | jq -r '.matched_rules[0].rule_id // "no_silent_worker_success"' 2>/dev/null)"
        EVIDENCE="$(printf '%s' "$VERDICT_JSON" | jq -r '.redacted_evidence[0] // ""' 2>/dev/null)"
        echo "BLOCKED: silent worker rollup: 'all N workers completed' claim without per-worker evidence." >&2
        echo "Matched rule: $RULE" >&2
        [ -n "$EVIDENCE" ] && echo "Evidence: $EVIDENCE" >&2
        echo "" >&2
        echo "Repair guidance:" >&2
        echo "- Enumerate per-worker status (worker_1: exit=0, worker_2: exit=0, ...)." >&2
        echo "- Or report only the workers whose output was verified." >&2
        echo "- Or close as Status: partial / Verification: pending." >&2
        exit 2
      fi
      if [ "$DECISION" = "pass" ]; then
        exit 0
      fi
    fi
  fi
fi

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

WORKER_CLAIM_RE="$(_load_or_fallback worker_rollup_claim 'all[[:space:]]+([0-9]+|the[[:space:]]+([0-9]+))[[:space:]]+(workers|agents|subagents|lanes|instances|parallel[[:space:]]+(agents|workers|instances))[[:space:]]+(completed|finished|done|succeeded|are[[:space:]]+done|have[[:space:]]+completed)|spawned[[:space:]]+([0-9]+)[[:space:]]+(workers|agents|subagents)[^[:cntrl:]]{0,80}(all[[:space:]]+(done|completed|finished|succeeded))|([0-9]+|all)[[:space:]]+(parallel|concurrent)[[:space:]]+(agents|workers|instances|subagents)[[:space:]]+(finished|completed|done|succeeded)|every[[:space:]]+(worker|agent|subagent)[[:space:]]+(succeeded|finished|completed|reported[[:space:]]+success)|the[[:space:]]+([0-9]+|N)[[:space:]]+(workers|agents)[[:space:]]+all[[:space:]]+(succeeded|completed|finished|reported[[:space:]]+success)')"
WORKER_EVIDENCE_RE="$(_load_or_fallback worker_per_worker_evidence 'worker[[:space:]_-]*[0-9]+[[:space:]]*[:=].*(exit|status|result|output)|agent[[:space:]_-]*[0-9]+[[:space:]]*[:=].*(exit|status|result|output)|subagent[[:space:]_-]*[0-9]+[[:space:]]*[:=].*(exit|status|result|output)|exit[[:space:]_]code[[:space:]]*[:=][[:space:]]*0.*exit[[:space:]_]code[[:space:]]*[:=][[:space:]]*0|`worker_[a-zA-Z0-9_-]+`[^`]*(exit|status|result)')"

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

if printf '%s\n' "$message" | grep -Eiq "$WORKER_CLAIM_RE"; then
  if ! printf '%s\n' "$message" | grep -Eiq "$WORKER_EVIDENCE_RE"; then
    block "silent worker rollup: 'all N workers completed' claim without per-worker evidence." \
"- Supervisor claims all workers completed but does not enumerate per-worker
  exit code, status, or result. The dominant failure mode of multi-agent
  systems in 2026 is silent worker mistakes (arXiv:2604.14228 Apr 2026:
  'silent mistakes, not crashes').
- Either:
    (a) Enumerate per-worker status with at minimum exit code or result
        (e.g. \`worker_1: exit=0, result=...\`, \`worker_2: exit=0,
        result=...\`, ..., \`worker_N: exit=0, result=...\`), OR
    (b) Drop the rollup claim and report only the workers whose output
        you actually verified, OR
    (c) Close as Status: partial / Verification: pending and request
        the orchestrator surface per-worker exit codes.
- Reference: Claude Code issue #45958 — 90-min subagent stall burned 15M
  cache tokens silently. The supervisor would have closed positively
  without this hook firing."
  fi
fi

exit 0
