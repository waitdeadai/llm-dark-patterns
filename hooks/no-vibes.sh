#!/bin/bash
# Claude Code hook: block destructive Bash and low-evidence positive closeout.
# Extra hook events fail open unless the payload is clearly dangerous.
#
# Vocabulary is loaded from packs/locale/<lang>.txt (Phase 1 of the loadable
# packs roadmap, see ROADMAP.md). The hook still works without packs — each
# load falls back to an inline English default that matches the pre-pack
# behavior verbatim, so no fixture regresses.

set -euo pipefail

# Load the shared pack helper. The plugin format puts hooks/ and lib/ as
# siblings under ${CLAUDE_PLUGIN_ROOT}; resolve relative to this script.
_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_HOOK_DIR/../lib/packs.sh" ]; then
  # shellcheck source=../lib/packs.sh
  source "$_HOOK_DIR/../lib/packs.sh"
fi

# Resolve vocab from active locale packs, or fall back to the inline English
# defaults if the loader is unavailable or the pack section is empty.
_load_with_fallback() {
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

POSITIVE_VERBS_RE="$(_load_with_fallback positive_closeout 'all set|done|completed|complete|implemented|fixed|finished|ready|passes|passed|shipped')"
NEGATIONS_RE="$(_load_with_fallback negation 'not done|not complete|not completed|not ready|incomplete|unfinished|never ran|did not (run|execute|test|verify)')"

# Phase 3: evidence binaries pack. Resolves which backtick-quoted tokens
# count as a real command. Sections are opt-in via env or all-by-default.
_load_evidence_binaries() {
  local section_filter="${LLM_DARK_PATTERNS_EVIDENCE_CATEGORIES:-}"
  if ! declare -F resolve_pack_paths >/dev/null 2>&1; then
    return
  fi
  local pack_paths=()
  local path
  while IFS= read -r path; do
    pack_paths+=("$path")
  done < <(resolve_pack_paths "evidence" "binaries")

  local section combined=""
  if [ -z "$section_filter" ]; then
    # Default: load every known section in the pack.
    for section in app-dev containers k8s devops cloud database shell-tools system archive http; do
      local part
      part="$(load_pack_section "$section" "${pack_paths[@]}" 2>/dev/null)"
      [ -z "$part" ] && continue
      if [ -z "$combined" ]; then
        combined="$part"
      else
        combined="${combined}|${part}"
      fi
    done
  else
    while IFS= read -r section; do
      [ -z "$section" ] && continue
      local part
      part="$(load_pack_section "$section" "${pack_paths[@]}" 2>/dev/null)"
      [ -z "$part" ] && continue
      if [ -z "$combined" ]; then
        combined="$part"
      else
        combined="${combined}|${part}"
      fi
    done < <(printf '%s\n' "$section_filter" | tr ',' '\n')
  fi
  printf '%s' "$combined"
}

EVIDENCE_BINARIES_RE="$(_load_evidence_binaries)"
if [ -z "$EVIDENCE_BINARIES_RE" ]; then
  EVIDENCE_BINARIES_RE='bash|git|npm|pnpm|yarn|pytest|python3?|ruff|cargo|go test|make'
fi

# Phase 4: destructive command surface packs. Each surface is a separate pack
# file under packs/destructive/. Operators choose which surfaces apply via
# LLM_DARK_PATTERNS_DESTRUCTIVE_PACKS=filesystem,container,git-protected
# (default: all).
_DESTRUCTIVE_PATTERNS=()
_load_destructive_patterns() {
  if ! declare -F resolve_pack_paths >/dev/null 2>&1; then
    return
  fi
  local pack_filter="${LLM_DARK_PATTERNS_DESTRUCTIVE_PACKS:-filesystem,container,git-protected,config-overwrite,cloud-prod,database,service}"
  local pack
  while IFS= read -r pack; do
    [ -z "$pack" ] && continue
    local pack_paths=()
    local path
    while IFS= read -r path; do
      pack_paths+=("$path")
    done < <(resolve_pack_paths "destructive" "$pack")
    local file
    for file in "${pack_paths[@]}"; do
      [ -f "$file" ] || continue
      while IFS= read -r line; do
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        [ -z "$trimmed" ] && continue
        case "$trimmed" in
          \#*|\[*) continue ;;
        esac
        _DESTRUCTIVE_PATTERNS+=("$trimmed")
      done < "$file"
    done
  done < <(printf '%s\n' "$pack_filter" | tr ',' '\n')
}

_load_destructive_patterns

# Inline fallback if no packs loaded — preserves original behavior exactly.
if [ "${#_DESTRUCTIVE_PATTERNS[@]}" -eq 0 ]; then
  _DESTRUCTIVE_PATTERNS=(
    '(^|[[:space:];&|])sudo[[:space:]]+r''m[[:space:]].*(-[[:alnum:]]*r|--recursive)([[:space:]]|$)'
    '(^|[[:space:];&|])r''m[[:space:]]+(-[[:alnum:]]*r[[:alnum:]]*|--recursive)([[:space:]]|$)'
    '(^|[[:space:];&|])r''m[[:space:]]+-[[:alnum:]]*f[[:alnum:]]*[[:space:]]+/'
    '(^|[[:space:];&|])git[[:space:]]+reset[[:space:]]+--hard([[:space:]]|$)'
    '(^|[[:space:];&|])git[[:space:]]+clean[[:space:]]+-[[:alnum:]]*(f[[:alnum:]]*d|d[[:alnum:]]*f)'
    '(^|[[:space:];&|])git[[:space:]]+checkout[[:space:]]+--[[:space:]]'
    '(^|[[:space:];&|])find[[:space:]].*[[:space:]]-delete([[:space:]]|$)'
    '(^|[[:space:];&|])mkfs(\.[[:alnum:]_-]+)?([[:space:]]|$)'
    '(^|[[:space:];&|])dd[[:space:]].*[[:space:]]of=/dev/'
    '(^|[[:space:];&|])chmod[[:space:]]+-R[[:space:]]+777([[:space:]]|$)'
  )
fi

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "NOTE: no-vibes hook requires jq; fail-open for this event." >&2
  exit 0
fi

json_get() {
  local filter="$1"
  printf '%s' "$INPUT" | jq -r "$filter // empty" 2>/dev/null || true
}

extract_file_paths() {
  printf '%s' "$INPUT" | jq -r '
    [
      .tool_input.file_path?,
      .tool_input.path?,
      .tool_input.filename?,
      .tool_input.file?,
      .tool_input.files?,
      .tool_input.paths?,
      .tool_input.edits[]?.file_path?,
      .tool_response.file_path?,
      .tool_response.path?,
      .result.file_path?,
      .result.path?
    ]
    | flatten
    | .[]?
    | select(type == "string" and length > 0)
  ' 2>/dev/null || true
}

collect_task_text() {
  printf '%s' "$INPUT" | jq -r '
    [
      .task.title?,
      .task.description?,
      .task.prompt?,
      .task.instructions?,
      .task_input?,
      .prompt?,
      .description?,
      .message?,
      .tool_input.description?,
      .tool_input.prompt?,
      .tool_input.input?,
      .tool_input.tasks[]?.title?,
      .tool_input.tasks[]?.description?,
      .tool_input.tasks[]?.prompt?
    ]
    | flatten
    | .[]?
    | select(type == "string" and length > 0)
  ' 2>/dev/null || true
}

collect_completion_text() {
  printf '%s' "$INPUT" | jq -r '
    [
      .task.result?,
      .task.summary?,
      .task_result?,
      .result?,
      .summary?,
      .last_assistant_message?,
      .assistant_message?,
      .message?,
      .output?,
      .tool_response.content?,
      .tool_response.result?
    ]
    | flatten
    | .[]?
    | select(type == "string" and length > 0)
  ' 2>/dev/null || true
}

collect_failure_text() {
  printf '%s' "$INPUT" | jq -r '
    [
      .error?,
      .tool_error?,
      .message?,
      .tool_response.error?,
      .tool_response.stderr?,
      .result.error?,
      .result.stderr?
    ]
    | flatten
    | .[]?
    | select(type == "string" and length > 0)
  ' 2>/dev/null || true
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

if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  exit 0
fi

event="$(json_get '.hook_event_name')"

is_destructive_bash() {
  # Phase 4: patterns are loaded from packs/destructive/<surface>.txt at
  # script startup into _DESTRUCTIVE_PATTERNS. Operators choose surfaces
  # via LLM_DARK_PATTERNS_DESTRUCTIVE_PACKS (default: all). This function
  # is unchanged in shape — only the source of patterns moved out.
  local command="$1"
  local candidate
  local pattern

  for candidate in "$command" "$(printf '%s\n' "$command" | sed "s/['\"\\\\]/ /g")"; do
    for pattern in "${_DESTRUCTIVE_PATTERNS[@]}"; do
      if printf '%s\n' "$candidate" | grep -Eiq -- "$pattern"; then
        return 0
      fi
    done
  done

  return 1
}

is_write_tool() {
  case "$1" in
    Edit|Write|MultiEdit|NotebookEdit) return 0 ;;
    *) return 1 ;;
  esac
}

is_sensitive_write_path() {
  local path="$1"
  path="${path#./}"

  case "$path" in
    .env|.env.*|*/.env|*/.env.*) return 0 ;;
    secrets|secrets/*|*/secrets|*/secrets/*) return 0 ;;
    .claude/settings.local.json|*/.claude/settings.local.json) return 0 ;;
    *) return 1 ;;
  esac
}

is_read_only_text() {
  local message="$1"
  printf '%s\n' "$message" | grep -Eiq '(^|[^[:alpha:]])(read-only|read only|audit only|research only|analysis only|inspect only|review only|no edits?|no file changes?|without edits?|without editing|do not edit|do not modify)([^[:alpha:]]|$)'
}

is_implementation_like_text() {
  local message="$1"
  if is_read_only_text "$message"; then
    return 1
  fi
  printf '%s\n' "$message" | grep -Eiq '(^|[^[:alpha:]])(implement|implementation|edit|write|modify|patch|fix|refactor|build|create|add|update|delete|change|wire|integrate|land|ship)(ing|ed|es|s)?([^[:alpha:]]|$)'
}

has_task_ownership() {
  local message="$1"
  printf '%s\n' "$message" | grep -Eiq '(ownership|owned files?|owned paths?|owns?:|owner:|must not touch|do not edit|do not modify|only edit|scope:|disjoint files?)'
}

block_sensitive_write_paths() {
  local file_paths file_path
  file_paths="$(extract_file_paths)"
  if [ -z "$file_paths" ]; then
    return 0
  fi

  while IFS= read -r file_path; do
    if [ -n "$file_path" ] && is_sensitive_write_path "$file_path"; then
      block "write tool touched sensitive env/secret path: $file_path" \
        "- Do not edit .env, .env.*, .claude/*.local.json, or secrets/**.
- Ask the operator for a safe non-secret target path or a redacted example file."
    fi
  done <<< "$file_paths"
}

has_positive_closeout() {
  # Detects positive-closeout verbs UNLESS each occurrence is negated within
  # the same clause. Splits on sentence delimiters (.!?) and conjunctions
  # (but/however/though/except/although) so a hedge in one clause does not
  # silence a positive claim in the next. Closes issue #5 (negation
  # early-return bypass). Vocabulary loaded from packs/locale/* with inline
  # English fallback (Phase 1).
  local message="$1"
  local POSITIVE="(^|[^[:alpha:]])(${POSITIVE_VERBS_RE})([^[:alpha:]]|$)"
  local NEGATIONS="(^|[^[:alpha:]])(${NEGATIONS_RE})([^[:alpha:]]|$)"

  local clauses
  clauses="$(printf '%s' "$message" \
    | sed -E 's/[.!?]+/\n/g' \
    | sed -E 's/(,|;)?[[:space:]]+(but|however|though|except|although)[[:space:]]+/\n/gI')"

  while IFS= read -r clause; do
    [ -z "$clause" ] && continue
    if printf '%s' "$clause" | grep -Eiq "$POSITIVE"; then
      if ! printf '%s' "$clause" | grep -Eiq "$NEGATIONS"; then
        return 0
      fi
    fi
  done <<< "$clauses"

  return 1
}

has_missing_verification() {
  local message="$1"
  printf '%s\n' "$message" | grep -Eiq '(^|[^[:alpha:]])(no[[:space:]]+tests?[[:space:]]+(run|ran)|tests?[[:space:]]+(not[[:space:]]+run|not[[:space:]]+ran|skipped|omitted)|not[[:space:]]+tested|untested|unverified|not[[:space:]]+verified|verification[[:space:]]+(not[[:space:]]+run|not[[:space:]]+ran|skipped|omitted|pending|missing)|verification[[:space:]]+was[[:space:]]+not[[:space:]]+run|could[[:space:]]+not[[:space:]]+verify|unable[[:space:]]+to[[:space:]]+verify)([^[:alpha:]]|$)' && return 0
  return 1
}

has_command_evidence() {
  # Evidence requires either:
  #   (a) explicit "Commands run:" header followed by a backtick command, OR
  #   (b) a backtick command in the closing window (last 240 chars of the
  #       message) preceded within ~80 chars by an action verb that asserts
  #       the command was actually executed (ran/executed/output/returned/
  #       passed/result of/exit code/stderr/stdout).
  # Closes issue #4 (backtick-anywhere-counts-as-evidence bypass). A backtick
  # buried mid-message inside a parenthetical disclaiming execution no
  # longer counts as evidence.
  local message="$1"

  if printf '%s\n' "$message" | grep -Eiq "(^|[[:space:]])commands?[[:space:]]+run:[^[:cntrl:]]{0,40}\`(${EVIDENCE_BINARIES_RE})[^\`]*\`"; then
    return 0
  fi

  local closing
  closing="$(printf '%s' "$message" | tail -c 240)"
  if printf '%s\n' "$closing" | grep -Eiq "(\bran\b|\bexecuted\b|\brunning\b|\boutput\b|\bresult of\b|\bpassed\b|\bexit code\b|\bstderr\b|\bstdout\b|\breturned\b)[^\`]{0,80}\`(${EVIDENCE_BINARIES_RE})[^\`]*\`"; then
    return 0
  fi

  return 1
}

has_verification_evidence() {
  local message="$1"
  # Match a verification keyword followed within ~50 chars by either a colon
  # (e.g., "Verification done (cite exact evidence):") OR a success token
  # (passed, pass, ok, succeeded, clean, green). The original tighter form
  # missed real evidence like "Verification: passed" preceded by a parens
  # block, blocking honest closeouts that did the verification work.
  printf '%s\n' "$message" | grep -Eiq '(^|[[:space:]])(verification|verified|verifying|tests?|smoke|lint|build|smoke[- ]test|typecheck)[^[:cntrl:]]{0,60}(:|passed|pass|ok|succeeded|clean|green|exit[[:space:]]*0)' && return 0
  return 1
}

has_artifact_evidence() {
  local message="$1"
  # Expanded noun set to recognize SOTA-2026 release artifacts (tarballs,
  # release assets, dist manifests, sha256 sidecars, packaged binaries) plus
  # the broader research-trail nouns (sources cited / referenced) used in
  # honest closeouts of multi-step work.
  printf '%s\n' "$message" | grep -Eiq '(^|[[:space:]])(changed[[:space:]]+files?|files?[[:space:]]+changed|files?[[:space:]]+inspected|sources?[[:space:]]+(reviewed|cited|referenced)|source[[:space:]]+ledger|diff|artifacts?|assets?|tarballs?|release[[:space:]]+(assets|notes|tag)?|manifest|checksum|sha256|evidence)(:|[[:space:]]|[.,)])' && return 0
  return 1
}

has_evidence() {
  local message="$1"
  has_command_evidence "$message" && return 0
  has_verification_evidence "$message" && return 0
  has_artifact_evidence "$message" && return 0
  return 1
}

has_closeout_evidence() {
  local message="$1"
  has_command_evidence "$message" && return 0
  has_verification_evidence "$message" && return 0
  if is_read_only_text "$message" && has_artifact_evidence "$message"; then
    return 0
  fi
  return 1
}

has_failed_verification() {
  local message="$1"
  has_missing_verification "$message" && return 0
  printf '%s\n' "$message" | grep -Eiq '(verification|verify|tests?|smoke|lint|build)[^[:cntrl:]]*(failed|failing|failure|error|errors|could not run|did not run|not run|unable to run|blocked)' && return 0
  printf '%s\n' "$message" | grep -Eiq '(failed|failing|failure|error|errors|could not run|did not run|not run|unable to run|blocked)[^[:cntrl:]]*(verification|verify|tests?|smoke|lint|build)' && return 0
  return 1
}

failed_verification_repair() {
  cat <<'EOF'
- Do not close with done/ready/passed/shipped while verification failed or did not run.
- Either run the missing verification and cite the exact command evidence, or close as partial/blocked/runtime-pending.
- Use a final shape like:
  Status: partial
  Verification: not run because <reason>
  Next step: <specific command or blocker>
EOF
}

missing_evidence_repair() {
  cat <<'EOF'
- Positive closeout needs concrete evidence, not just "done" or "ready".
- Add at least one of:
  Commands run: `<exact command>`
  Verification: passed/blocked with detail
- For implementation closeout, changed files alone are not enough.
- For read-only work, include files inspected / sources reviewed.
- If evidence is unavailable, close as partial/blocked/verification pending instead of done.
EOF
}

tool_name="$(json_get '.tool_name')"

if [ "$tool_name" = "Bash" ]; then
  command="$(json_get '.tool_input.command')"
  if [ -n "$command" ] && is_destructive_bash "$command"; then
    block "destructive Bash command requires explicit human approval and a rollback plan." \
      "- Ask the operator for explicit approval before destructive commands.
- Include the exact command, affected paths, and rollback plan."
  fi
fi

if is_write_tool "$tool_name"; then
  block_sensitive_write_paths
fi

if [ "$event" = "PreToolUse" ] && [ "$tool_name" = "Bash" ]; then
  exit 0
fi

if [ "$event" = "PostToolUse" ] && is_write_tool "$tool_name"; then
  exit 0
fi

if [ "$event" = "TaskCreated" ]; then
  task_text="$(collect_task_text)"
  if [ -z "$task_text" ]; then
    exit 0
  fi

  if is_implementation_like_text "$task_text" && ! has_task_ownership "$task_text"; then
    block "implementation-like TaskCreated payload needs explicit ownership or read-only scope." \
      "- Add owned paths, forbidden paths, and stop conditions to the task.
- Or mark the task as read-only/audit-only if it must not edit files."
  fi

  exit 0
fi

if [ "$event" = "TaskCompleted" ]; then
  task_text="$(collect_task_text)"
  completion_text="$(collect_completion_text)"
  combined_text="$(printf '%s\n%s' "$task_text" "$completion_text")"

  if [ -z "$combined_text" ] || [ -z "$completion_text" ]; then
    exit 0
  fi

  if is_implementation_like_text "$combined_text"; then
    if has_failed_verification "$completion_text" && has_positive_closeout "$completion_text"; then
      block "implementation task closeout conflicts with failed or missing verification." "$(failed_verification_repair)"
    fi

    if ! has_closeout_evidence "$completion_text"; then
      block "implementation TaskCompleted payload needs concrete evidence." "$(missing_evidence_repair)"
    fi
  fi

  exit 0
fi

if [ "$event" = "PostToolUseFailure" ]; then
  failure_text="$(collect_failure_text)"
  if [ -n "$failure_text" ]; then
    echo "NOTE: tool failure observed; record command/error evidence before positive closeout." >&2
  fi
  exit 0
fi

has_prescribed_status_header() {
  # Recognize the hook's own prescribed repair shape as a self-declared honest
  # closeout. If the message opens with "Status: partial|blocked|runtime-pending"
  # in the first 800 chars (allowing for a markdown ** prefix), the model has
  # explicitly accepted partial status and should not be re-blocked for positive
  # verbs that appear later in the body (e.g., describing what DID get done).
  #
  # This matches the canonical repair guidance emitted by both
  # failed_verification_repair() and missing_evidence_repair(): "Use a final
  # shape like: Status: partial / Verification: ... / Next step: ...". Without
  # this allow-clause the hook contradicts its own repair guidance.
  #
  # Source: arxiv 2410.02916 (Oct 2024) — LLM safeguard false positives can be
  # exploited for denial-of-service; the standard mitigation is recognizing
  # the prescribed safe form as an early-pass signal. Source: openai.com/index/
  # why-language-models-hallucinate (Sept 2025) — calibrated abstention should
  # be REWARDED, not penalized.
  local message="$1"
  printf '%s' "$message" \
    | head -c 800 \
    | grep -Eiq '(^|\n)[[:space:]]*\*{0,2}[[:space:]]*Status:[[:space:]]+(partial|blocked|runtime-pending|paused|in[- ]progress|unverified)\b' && return 0
  return 1
}

if [ "$event" = "Stop" ] || [ "$event" = "SubagentStop" ]; then
  if [ "$(json_get '.stop_hook_active')" = "true" ]; then
    exit 0
  fi

  message="$(json_get '.last_assistant_message')"
  if [ -z "$message" ]; then
    exit 0
  fi

  # Allow-clause: self-declared partial/blocked/runtime-pending status header
  # in the first 800 chars. The model has accepted the honest framing
  # explicitly — trust the self-declaration rather than scanning for verb-
  # shaped false positives in the body.
  if has_prescribed_status_header "$message"; then
    exit 0
  fi

  if has_failed_verification "$message" && has_positive_closeout "$message"; then
    block "positive closeout conflicts with failed or missing verification." "$(failed_verification_repair)"
  fi

  if has_positive_closeout "$message" && ! has_closeout_evidence "$message"; then
    block "closeout needs concrete evidence." "$(missing_evidence_repair)"
  fi
fi

exit 0
