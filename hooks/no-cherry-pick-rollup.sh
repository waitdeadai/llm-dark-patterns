#!/bin/bash
# Claude Code hook: block supervisor closeouts that cite partial worker
# success ("4 of 5 workers succeeded") and then declare overall success
# WITHOUT explicitly handling the unsuccessful worker(s).
#
# Backing:
# - gurusup May 2026: "Handoff loops, where Agent A passes to Agent B
#   which passes back to Agent A, are a common failure mode requiring
#   careful guard conditions."
# - The Slow AI on Anthropic multi-agent (5d ago): "discharge summary
#   contains errors a human reading the notes would have caught."
# - Anthropic multi-agent blog (Jun 2025): supervisor synthesis must
#   account for partial failure honestly.

set -euo pipefail

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "NOTE: no-cherry-pick-rollup hook requires jq; fail-open." >&2
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
  if [ -n "$RULES_DIR" ] && [ -d "$RULES_DIR" ] && [ -f "$RULES_DIR/no_cherry_pick_rollup.yaml" ]; then
    TMP_INPUT="$(mktemp)"; printf '%s' "$INPUT" > "$TMP_INPUT"
    VERDICT_JSON="$(agentcloseout-physics scan --category no_cherry_pick_rollup --rules "$RULES_DIR" --input "$TMP_INPUT" 2>/dev/null || true)"
    rm -f "$TMP_INPUT"
    if [ -n "$VERDICT_JSON" ]; then
      DECISION="$(printf '%s' "$VERDICT_JSON" | jq -r '.decision // empty' 2>/dev/null)"
      if [ "$DECISION" = "block" ]; then
        RULE="$(printf '%s' "$VERDICT_JSON" | jq -r '.matched_rules[0].rule_id // "no_cherry_pick_rollup"' 2>/dev/null)"
        EVIDENCE="$(printf '%s' "$VERDICT_JSON" | jq -r '.redacted_evidence[0] // ""' 2>/dev/null)"
        echo "BLOCKED: cherry-pick rollup: partial worker success + positive closeout WITHOUT handling failed workers." >&2
        echo "Matched rule: $RULE" >&2
        [ -n "$EVIDENCE" ] && echo "Evidence: $EVIDENCE" >&2
        echo "" >&2
        echo "Repair guidance:" >&2
        echo "- Explicitly handle failed workers (retried, blocking, ignored-with-reason)." >&2
        echo "- Or close as Status: partial / Next step: investigate failed worker." >&2
        echo "- Or drop the rollup framing and report only the verified-succeeded portion." >&2
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

PARTIAL_RE="$(_load_or_fallback cherry_pick_partial '\b([0-9]+)[[:space:]]*(out[[:space:]]+of|of|/)[[:space:]]*([0-9]+)[[:space:]]+(workers|agents|subagents|lanes|instances|tasks)[[:space:]]+(succeeded|completed|finished|passed|reported[[:space:]]+success)|\b([0-9]+)[[:space:]]+(workers|agents|subagents|lanes|tasks)[[:space:]]+(failed|errored|timed[[:space:]]+out|crashed)|the[[:space:]]+(other|remaining)[[:space:]]+([0-9]+)[[:space:]]+(workers|agents|subagents)[[:space:]]+(failed|errored|did[[:space:]]+not)')"
HANDLED_RE="$(_load_or_fallback cherry_pick_handled '(failed|errored|crashed|timed[[:space:]]+out)[[:space:]]+(workers?|agents?|subagents?)[[:space:]]+(because|due[[:space:]]+to|with[[:space:]]+error)|will[[:space:]]+retry[[:space:]]+(the[[:space:]]+)?failed|requeued[[:space:]]+(the[[:space:]]+)?failed|the[[:space:]]+failed[[:space:]]+(workers?|agents?|tasks?)[[:space:]]+(blocked|caused|require)|blocker[[:space:]]+(from|on)[[:space:]]+the[[:space:]]+failed|status[[:space:]]*:[[:space:]]*(partial|blocked)|next[[:space:]]+step[[:space:]]*:[[:space:]]+(retry|investigate|fix)[[:space:]]+(the[[:space:]]+)?failed')"
POSITIVE_CLOSE_RE="$(_load_or_fallback positive_closeout 'all set|done|completed|complete|implemented|fixed|finished|ready|passes|passed|shipped')"

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

# Step 1: did the message acknowledge partial failure?
if ! printf '%s\n' "$message" | grep -Eiq "$PARTIAL_RE"; then
  exit 0
fi

# Step 2: does it ALSO have a positive overall closeout?
if ! printf '%s\n' "$message" | grep -Eiq "(^|[^[:alpha:]])(${POSITIVE_CLOSE_RE})([^[:alpha:]]|$)"; then
  exit 0
fi

# Step 3: did the supervisor explicitly handle the failed workers?
if printf '%s\n' "$message" | grep -Eiq "$HANDLED_RE"; then
  exit 0
fi

block "cherry-pick rollup: partial worker success cited + positive closeout WITHOUT handling failed workers." \
"- The supervisor message acknowledges that some workers failed (e.g. 'X
  out of Y succeeded' / 'N workers failed') AND closes positively, but
  does NOT explain how the failed workers are handled (retried? blocking?
  ignored? fixed?). This is the dominant cherry-pick failure mode in
  2026 multi-agent deployments — supervisor reports success based on
  partial data while the failed lanes silently rot.
- Either:
    (a) Explicitly handle the failed workers in the same close: 'failed
        workers W,X retried' / 'failed workers W,X blocking — Status:
        partial' / 'failed worker W's task is non-critical, ignored
        because [reason]', OR
    (b) Close as Status: partial / Verification: not run on the failed
        portion / Next step: investigate worker W failure, OR
    (c) Drop the rollup framing entirely and report only the verified-
        succeeded portion as its own scope.
- Reference: Anthropic multi-agent blog (Jun 2025); The Slow AI report
  on Anthropic multi-agent warning (5 days ago — discharge-summary
  errors a human would have caught)."
