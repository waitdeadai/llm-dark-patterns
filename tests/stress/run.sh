#!/usr/bin/env bash
# Stress runner for the LLM Dark Patterns hooks suite.
# Walks tests/stress/<hook>/{positive,negative,edge}/*.json and validates
# each hook's exit code against the expected outcome for the category.
#
# Convention:
#   positive/  -> expect exit 2  (hook BLOCKED the message, as designed)
#   negative/  -> expect exit 0  (hook did NOT fire — false-positive guard)
#   edge/      -> expect exit 0 unless a sibling .expected file overrides it
#
# Per-fixture override: place a sibling file with the same basename and
# extension `.expected` containing a single integer (0 or 2). Example:
#   tests/stress/no-vibes/edge/empty-message.json
#   tests/stress/no-vibes/edge/empty-message.expected   <- contains "0"
#
# Usage:
#   bash tests/stress/run.sh                 # full run, exit 1 if any fail
#   bash tests/stress/run.sh --quiet         # only print summary + failures
#   bash tests/stress/run.sh --hook no-vibes # only one hook
#
# Output:
#   STDOUT: per-fixture verdict + final summary
#   FILE:   tests/stress/STRESS-REPORT.md (overwritten each run)

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOKS_DIR="${ROOT_DIR}/hooks"
STRESS_DIR="${ROOT_DIR}/tests/stress"
REPORT="${STRESS_DIR}/STRESS-REPORT.md"

QUIET=0
ONLY_HOOK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --quiet) QUIET=1; shift ;;
    --hook) ONLY_HOOK="$2"; shift 2 ;;
    --hook=*) ONLY_HOOK="${1#--hook=}"; shift ;;
    -h|--help)
      sed -n '2,25p' "$0"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 64 ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "FATAL: jq is required for stress test." >&2
  exit 127
fi

TOTAL=0
PASS=0
FAIL=0
SKIP=0
FAILURES=()

log() { [ "$QUIET" -eq 0 ] && printf '%s\n' "$*"; }
err() { printf '%s\n' "$*" >&2; }

# Run a Stop-event hook with a JSON fixture on stdin.
# Args: hook_path fixture_path
# Echoes captured stderr (truncated) and returns hook's exit code.
run_stop_hook() {
  local hook="$1" fixture="$2"
  local stderr_out actual_code
  # Capture stderr into the variable, discard stdout, preserve exit code.
  # Note: do NOT chain `|| true` — that would mask the hook's exit status.
  stderr_out="$(bash "$hook" < "$fixture" 2>&1 1>/dev/null)"
  actual_code=$?
  printf '%s' "$stderr_out"
  return $actual_code
}

# Run time-anchor hook (different shape — takes a positional arg).
# Args: fixture_path
# Reads fixture as JSON containing {"mode": "hook|prompt|session|text|json"}.
run_time_anchor() {
  local fixture="$1"
  local mode input stderr_out actual_code
  mode="$(jq -r '.mode // "hook"' < "$fixture" 2>/dev/null)" || mode="hook"
  input="$(jq -c '.input // {}' < "$fixture" 2>/dev/null)" || input="{}"
  stderr_out="$(printf '%s' "$input" | bash "${HOOKS_DIR}/time-anchor.sh" "$mode" 2>&1 1>/dev/null)"
  actual_code=$?
  printf '%s' "$stderr_out"
  return $actual_code
}

# Run state.sh hook (subcommand-based).
# Reads fixture as JSON containing {"command": "...", "stdin": {...}}.
# Runs in an isolated tmp workspace so the test does not pollute the repo.
run_state() {
  local fixture="$1"
  local command stdin_payload tmp_root code
  command="$(jq -r '.command // "status"' < "$fixture" 2>/dev/null)" || command="status"
  stdin_payload="$(jq -c '.stdin // {}' < "$fixture" 2>/dev/null)" || stdin_payload="{}"
  tmp_root="$(mktemp -d -t dpstate.XXXXXXXX)"
  (
    cd "$tmp_root" || exit 99
    git init -q 2>/dev/null
    git config user.email t@t 2>/dev/null
    git config user.name t 2>/dev/null
    : > placeholder.txt
    NO_AMNESIA_STATE_DIR="$tmp_root/.no-amnesia/state" \
      printf '%s' "$stdin_payload" | bash "${HOOKS_DIR}/state.sh" "$command" >/dev/null 2>&1
  )
  code=$?
  rm -rf "$tmp_root"
  return $code
}

# Determine expected exit code from category + override.
expected_code_for() {
  local fixture="$1" category="$2"
  local override="${fixture%.json}.expected"
  if [ -f "$override" ]; then
    tr -d '[:space:]' < "$override"
    return
  fi
  case "$category" in
    positive) echo 2 ;;
    negative) echo 0 ;;
    edge)     echo 0 ;;
    *)        echo 0 ;;
  esac
}

run_one() {
  local hook="$1" category="$2" fixture="$3"
  local hook_basename expected actual stderr_out
  hook_basename="$(basename "$hook" .sh)"
  expected="$(expected_code_for "$fixture" "$category")"

  TOTAL=$((TOTAL + 1))

  # Per-fixture env sidecar — `<fixture>.env` is sourced before the hook runs.
  # Allows fixtures to require specific locales (e.g.
  # LLM_DARK_PATTERNS_LOCALE=en,es,pl) without polluting the rest of the run.
  local env_sidecar="${fixture%.json}.env"
  local env_snapshot=""
  if [ -f "$env_sidecar" ]; then
    env_snapshot="$(env)"
    set -a
    # shellcheck disable=SC1090
    source "$env_sidecar"
    set +a
  fi

  case "$hook_basename" in
    time-anchor)
      stderr_out="$(run_time_anchor "$fixture")"; actual=$?
      ;;
    state)
      run_state "$fixture"; actual=$?
      stderr_out="(state.sh runs in isolated tmp; stderr suppressed)"
      ;;
    *)
      stderr_out="$(run_stop_hook "$hook" "$fixture")"; actual=$?
      ;;
  esac

  # Restore environment after each fixture to keep them independent.
  if [ -n "$env_snapshot" ]; then
    while IFS='=' read -r k _; do
      [ -z "$k" ] && continue
      # Only unset locale-related override vars that the sidecar might set;
      # avoid wiping inherited env that other fixtures depend on.
      case "$k" in
        LLM_DARK_PATTERNS_*|LANG|LC_*) unset "$k" ;;
      esac
    done < <(diff <(printf '%s\n' "$env_snapshot") <(env) | grep '^>' | sed 's/^> //')
  fi

  local fixture_rel="${fixture#${ROOT_DIR}/}"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1))
    log "  PASS  $fixture_rel  (exit=$actual)"
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("$fixture_rel|expected=$expected|actual=$actual|stderr=$(printf '%s' "$stderr_out" | head -c 200 | tr '\n' ' ')")
    log "  FAIL  $fixture_rel  (expected=$expected, actual=$actual)"
    if [ "$QUIET" -eq 0 ] && [ -n "$stderr_out" ]; then
      printf '        stderr: %s\n' "$(printf '%s' "$stderr_out" | head -c 200 | tr '\n' ' ')"
    fi
  fi
}

run_hook_dir() {
  local hook="$1"
  local hook_basename
  hook_basename="$(basename "$hook" .sh)"
  local stress_dir="${STRESS_DIR}/${hook_basename}"
  if [ ! -d "$stress_dir" ]; then
    SKIP=$((SKIP + 1))
    log "SKIP  hook=${hook_basename} (no fixtures dir)"
    return
  fi
  log ""
  log "=== ${hook_basename} ==="
  for category in positive negative edge; do
    local cat_dir="${stress_dir}/${category}"
    [ -d "$cat_dir" ] || continue
    shopt -s nullglob
    local fixtures=("$cat_dir"/*.json)
    shopt -u nullglob
    [ ${#fixtures[@]} -eq 0 ] && continue
    log "  -- ${category} (${#fixtures[@]} fixtures)"
    for fixture in "${fixtures[@]}"; do
      run_one "$hook" "$category" "$fixture"
    done
  done
}

# Hook discovery — every .sh in hooks/ except the small wrapper scripts that
# only delegate to state.sh (state-stop, state-precompact, etc.) since their
# behavior is covered by state fixtures.
HOOKS_TO_TEST=(
  "${HOOKS_DIR}/no-vibes.sh"
  "${HOOKS_DIR}/no-curfew.sh"
  "${HOOKS_DIR}/no-sycophancy.sh"
  "${HOOKS_DIR}/no-cliffhanger.sh"
  "${HOOKS_DIR}/no-wrap-up.sh"
  "${HOOKS_DIR}/no-aggregator-hallucination.sh"
  "${HOOKS_DIR}/no-silent-worker-success.sh"
  "${HOOKS_DIR}/no-cherry-pick-rollup.sh"
  "${HOOKS_DIR}/no-ownership-violation.sh"
  "${HOOKS_DIR}/no-handoff-loop.sh"
  "${HOOKS_DIR}/no-credential-leak-in-handoff.sh"
  "${HOOKS_DIR}/no-phantom-tool-call.sh"
  "${HOOKS_DIR}/no-sandbagging-disguise.sh"
  "${HOOKS_DIR}/no-rollback-claim-without-evidence.sh"
  "${HOOKS_DIR}/no-approval-sneak.sh"
  "${HOOKS_DIR}/no-emoji-spam.sh"
  "${HOOKS_DIR}/no-tldr-bait.sh"
  "${HOOKS_DIR}/no-meta-commentary.sh"
  "${HOOKS_DIR}/no-prompt-restate.sh"
  "${HOOKS_DIR}/no-disclaimer-spam.sh"
  "${HOOKS_DIR}/no-ai-tells.sh"
  "${HOOKS_DIR}/no-roleplay-drift.sh"
  "${HOOKS_DIR}/honest-eta.sh"
  "${HOOKS_DIR}/no-fake-recall.sh"
  "${HOOKS_DIR}/no-fake-stats.sh"
  "${HOOKS_DIR}/no-fake-cite.sh"
  "${HOOKS_DIR}/time-anchor.sh"
  "${HOOKS_DIR}/state.sh"
)

if [ -n "$ONLY_HOOK" ]; then
  HOOKS_TO_TEST=("${HOOKS_DIR}/${ONLY_HOOK}.sh")
fi

START_TS="$(date -Iseconds)"
log ""
log "LLM Dark Patterns — Stress Test"
log "Started: ${START_TS}"
log "Repo:    ${ROOT_DIR}"
log ""

for hook in "${HOOKS_TO_TEST[@]}"; do
  if [ ! -x "$hook" ] && [ ! -f "$hook" ]; then
    err "MISSING hook: $hook"
    SKIP=$((SKIP + 1))
    continue
  fi
  run_hook_dir "$hook"
done

END_TS="$(date -Iseconds)"

# Build report
{
  echo "# LLM Dark Patterns — Stress Test Report"
  echo ""
  echo "- Started: ${START_TS}"
  echo "- Ended:   ${END_TS}"
  echo "- Total fixtures: ${TOTAL}"
  echo "- Passed: ${PASS}"
  echo "- Failed: ${FAIL}"
  echo "- Hook dirs skipped (no fixtures): ${SKIP}"
  echo ""
  if [ "$FAIL" -eq 0 ]; then
    echo "**Result: PASS** — every fixture's actual exit code matched its expected outcome."
  else
    echo "**Result: FAIL** — ${FAIL} fixture(s) returned an unexpected exit code:"
    echo ""
    echo "| Fixture | Expected | Actual | Stderr (first 200B) |"
    echo "|---|---|---|---|"
    for failure in "${FAILURES[@]}"; do
      IFS='|' read -r f exp act stderr <<< "$failure"
      stderr_clean="$(printf '%s' "$stderr" | sed 's/|/\\|/g')"
      echo "| \`${f}\` | ${exp#expected=} | ${act#actual=} | ${stderr_clean#stderr=} |"
    done
  fi
  echo ""
  echo "## How to reproduce"
  echo ""
  echo "\`\`\`bash"
  echo "bash tests/stress/run.sh"
  echo "\`\`\`"
  echo ""
  echo "## Convention"
  echo ""
  echo "- \`tests/stress/<hook>/positive/*.json\` — fixture should BLOCK (exit 2)"
  echo "- \`tests/stress/<hook>/negative/*.json\` — fixture should NOT block (exit 0; false-positive guard)"
  echo "- \`tests/stress/<hook>/edge/*.json\`     — boundary cases; expect 0 unless a sibling \`.expected\` file overrides"
  echo ""
  echo "Per-fixture override: write the expected integer exit code to a sibling file with the same basename and \`.expected\` extension."
} > "$REPORT"

log ""
log "==============================="
log "Total:  ${TOTAL}"
log "Pass:   ${PASS}"
log "Fail:   ${FAIL}"
log "Report: ${REPORT}"
log "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
