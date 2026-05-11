#!/bin/bash
# Claude Code hook: block supervisor messages that synthesize "the workers'
# results" without actually citing per-worker output. Catches the dark
# pattern where a coordinator agent fabricates consensus that no underlying
# worker actually produced.
#
# Backing:
# - Beam AI 2026 multi-agent patterns: "The aggregation step itself
#   introduces error. LLM-based synthesis can hallucinate consensus that
#   doesn't exist in the underlying results."
# - Anthropic multi-agent research blog (Jun 2025): "minor system failures
#   can be catastrophic for agents."
# - arXiv 2603.04474 (Mar 2026): "Modeling and Mitigating Error Cascades
#   in LLM-Based Multi-Agent Systems."
#
# Vocabulary loaded from packs/locale/<lang>.txt section [aggregator_claim]
# and [aggregator_evidence]. Inline English fallback preserves working
# behavior when packs are unavailable.

set -euo pipefail

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "NOTE: no-aggregator-hallucination hook requires jq; fail-open." >&2
  exit 0
fi

if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  exit 0
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

AGG_CLAIM_RE="$(_load_or_fallback aggregator_claim 'synthesizing[[:space:]]+(the[[:space:]]+)?(workers|agents|subagents|parallel[[:space:]]+(workers|agents))[\47]?[[:space:]]+(results|findings|output|reports)|based[[:space:]]+on[[:space:]]+(the[[:space:]]+)?(workers|agents|subagents)[\47]?[[:space:]]+(results|findings|output|reports|work)|combining[[:space:]]+(the[[:space:]]+)?(results|outputs|findings)[[:space:]]+from[[:space:]]+([0-9]+|all|the)[[:space:]]+(workers|agents|subagents)|aggregating[[:space:]]+(the[[:space:]]+)?(results|findings)[[:space:]]+from[[:space:]]+([0-9]+|all|the)?[[:space:]]?(workers|agents|subagents)|consensus[[:space:]]+(across|among|from)[[:space:]]+(the[[:space:]]+)?([0-9]+|all|the|multiple)[[:space:]]+(workers|agents|subagents)|the[[:space:]]+(workers|agents|subagents)[[:space:]]+(all[[:space:]]+)?(report|reported|conclude|concluded|agreed|agree)')"
AGG_EVIDENCE_RE="$(_load_or_fallback aggregator_evidence 'worker[[:space:]_-]*[0-9]+[[:space:]]*[:=]|agent[[:space:]_-]*[0-9]+[[:space:]]*[:=]|subagent[[:space:]_-]*[0-9]+[[:space:]]*[:=]|worker[[:space:]_-]*(id|name)[[:space:]]*[:=]|`?worker_[a-zA-Z0-9_-]+`?[[:space:]]*[:=]|^>[[:space:]]+\S')"

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

if printf '%s\n' "$message" | grep -Eiq "$AGG_CLAIM_RE"; then
  if ! printf '%s\n' "$message" | grep -Eiq "$AGG_EVIDENCE_RE"; then
    block "aggregator hallucination: synthesis claim without per-worker evidence." \
"- The supervisor message claims to synthesize/aggregate/combine results
  from N workers, but no per-worker output is quoted (no \`worker_1:\`,
  no \`agent_2:\`, no markdown blockquote of worker text, no worker_id).
- LLM-based synthesis hallucinates consensus that does not exist in the
  underlying results. The Beam AI 2026 production-pattern report names
  this as the canonical multi-agent failure mode.
- Either:
    (a) Quote the per-worker output that actually justifies the synthesis
        (e.g. \`worker_1: { result: pass }, worker_2: { result: pass }\`
        or markdown blockquotes of each worker's text), OR
    (b) Drop the synthesis framing and report the result as a single
        agent's work, OR
    (c) Close as Status: partial / Verification: pending until per-worker
        outputs are available.
- Citation: Beam AI 2026 multi-agent orchestration patterns; Anthropic
  multi-agent research blog (Jun 2025); arXiv:2603.04474 error-cascade
  modeling."
  fi
fi

exit 0
