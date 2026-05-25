#!/usr/bin/env bash
# Tests for the no-count-drift hook + lib/count_drift.py core.
# Run: bash tests/test-count-drift.sh   Exit: 0 on success, 1 on any failure.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/hooks/no-count-drift.sh"
SCORER="$ROOT/evaluation/v6/score_count_drift.py"

PASS=0; FAIL=0; FAILS=()
assert_exit() { # desc expected actual
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"
  else
    FAIL=$((FAIL + 1)); FAILS+=("$1")
    printf '  FAIL  %s (want exit %s, got %s)\n' "$1" "$2" "$3"
  fi
}
run_hook() { # message -> sets RC
  local msg="$1"
  printf '%s' "$(jq -n --arg m "$msg" \
    '{hook_event_name:"Stop",stop_hook_active:false,last_assistant_message:$m}')" \
    | bash "$HOOK" >/dev/null 2>&1
  RC=$?
}

# SC1 + SC2 + SC3: scorer exits 0 only when precision == 1.0 (zero FP) over the
# adversarial fixture set, with the seeded positives blocked.
python3 "$SCORER" >/dev/null 2>&1
assert_exit "scorer: 0 false positives (SC1), seeds blocked (SC2), abstain (SC3)" 0 "$?"

# Hook end-to-end.
run_hook "$(printf 'Six findings:\n- a\n- b\n- c\n- d\n- e')"
assert_exit "hook blocks headline-vs-list mismatch (exit 2)" 2 "$RC"

run_hook "$(printf 'Five findings:\n- a\n- b\n- c\n- d\n- e')"
assert_exit "hook passes a correct count (exit 0)" 0 "$RC"

run_hook "Coverage is 9/10 = 80% overall."
assert_exit "hook blocks wrong fraction-percent (exit 2)" 2 "$RC"

run_hook "$(printf '3 reasons: the top 2 are:\n- x\n- y')"
assert_exit "hook abstains on nested-colon trap (exit 0)" 0 "$RC"

# SC4 fail-open paths.
printf 'not json at all' | bash "$HOOK" >/dev/null 2>&1
assert_exit "fail-open on non-JSON input (SC4)" 0 "$?"

printf '%s' "$(jq -n '{hook_event_name:"Stop",last_assistant_message:""}')" | bash "$HOOK" >/dev/null 2>&1
assert_exit "fail-open on empty message (SC4)" 0 "$?"

printf '%s' "$(jq -n --arg m "$(printf 'Six findings:\n- a\n- b')" \
  '{hook_event_name:"Stop",stop_hook_active:true,last_assistant_message:$m}')" \
  | bash "$HOOK" >/dev/null 2>&1
assert_exit "re-entrancy guard: stop_hook_active=true never blocks" 0 "$?"

# SC5 determinism: identical scorer output across two runs.
A="$(python3 "$SCORER" 2>/dev/null)"
Bb="$(python3 "$SCORER" 2>/dev/null)"
[ "$A" = "$Bb" ]
assert_exit "determinism: identical scorer output twice (SC5)" 0 "$?"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -ne 0 ]; then
  printf 'FAILURES: %s\n' "${FAILS[*]}"
  exit 1
fi
echo "ALL TESTS PASSED"
