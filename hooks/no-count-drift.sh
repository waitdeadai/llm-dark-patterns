#!/bin/bash
# Claude Code hook: block a count stated in the message that contradicts the
# message's OWN enumeration or arithmetic (count-vs-enumeration self-consistency).
#
# This is a FAITHFULNESS / self-consistency gate (MAST FM-3.2 "no/incomplete
# verification"), distinct from no-fake-stats, which is a FACTUALITY / citation
# gate. A citation does not resolve an internal mismatch, and small integers that
# no-fake-stats ignores are exactly where count drift hides.
#
# Deterministic, high-precision, abstain-on-ambiguity: it fires only on
# unambiguous self-contained mismatches and otherwise passes. The counting logic
# lives in lib/count_drift.py because counting is a rule-based-symbolic strength
# and an LLM weakness (errors are self-consistent on resample).

set -euo pipefail

INPUT="$(cat)"

# Fail-open if the toolchain is missing — never break a session.
command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || exit 0

# Re-entrancy guard, matching sibling Stop hooks.
if [ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // empty' 2>/dev/null)" = "true" ]; then
  exit 0
fi

message="$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)"
[ -z "$message" ] && exit 0

CORE="$(cd "$(dirname "$0")" && pwd)/../lib/count_drift.py"
[ -f "$CORE" ] || exit 0

VERDICT="$(printf '%s' "$message" | python3 "$CORE" 2>/dev/null || true)"
[ -z "$VERDICT" ] && exit 0

DECISION="$(printf '%s' "$VERDICT" | jq -r '.decision // empty' 2>/dev/null || true)"
if [ "$DECISION" = "block" ]; then
  RULE="$(printf '%s' "$VERDICT" | jq -r '.rule // "count_drift"' 2>/dev/null)"
  EVID="$(printf '%s' "$VERDICT" | jq -r '.evidence // ""' 2>/dev/null)"
  echo "BLOCKED: a stated count contradicts the message's own enumeration or arithmetic." >&2
  echo "Matched rule: $RULE" >&2
  [ -n "$EVID" ] && echo "Evidence: $EVID" >&2
  echo "" >&2
  echo "Repair guidance:" >&2
  echo "- Re-count the enumerated items (or re-check the fraction), then make the stated number match." >&2
  echo "- If the number and the list intentionally differ, say so explicitly (e.g. exclude a contrast item from the tally)." >&2
  echo "- This is a self-consistency check, not a citation check — adding a source does not fix an internal mismatch." >&2
  exit 2
fi

exit 0
