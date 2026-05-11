#!/bin/bash
# Claude Code hook: block PreToolUse / Edit / Write operations on
# operator-defined sensitive paths without prior approval token.
#
# Sensitive paths default: .env*, secrets/, .kube/, terraform/state/,
# .ssh/, .gnupg/, prod/. Operator extends via packs/sensitive/paths.txt
# section [approval_required].

set -euo pipefail

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then exit 0; fi
if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then exit 0; fi

_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_HOOK_DIR/../lib/packs.sh" ]; then
  # shellcheck source=../lib/packs.sh
  source "$_HOOK_DIR/../lib/packs.sh"
fi

_load_paths() {
  if declare -F resolve_pack_paths >/dev/null 2>&1; then
    local pack_paths=() path
    while IFS= read -r path; do
      pack_paths+=("$path")
    done < <(resolve_pack_paths "sensitive" "paths")
    local part
    part="$(load_pack_section "approval_required" "${pack_paths[@]}" 2>/dev/null)"
    if [ -n "$part" ]; then
      printf '%s' "$part"
      return
    fi
  fi
  printf '%s' '\.env($|[.][a-zA-Z0-9_-]+$)|(^|/)secrets/|(^|/)\.kube/|(^|/)terraform/state/|(^|/)\.ssh/|(^|/)\.gnupg/|(^|/)prod/'
}

SENSITIVE_RE="$(_load_paths)"

json_get() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null || true; }
block() {
  echo "BLOCKED: $1" >&2
  [ -n "${2:-}" ] && { echo "" >&2; echo "Repair guidance:" >&2; printf '%s\n' "$2" >&2; }
  exit 2
}

event="$(json_get '.hook_event_name')"
tool="$(json_get '.tool_name')"

# Only act on write tools on PreToolUse / PostToolUse.
case "$tool" in
  Edit|Write|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac
case "$event" in
  PreToolUse|PostToolUse|TaskCompleted) ;;
  *) exit 0 ;;
esac

# Extract target file path.
file_paths="$(printf '%s' "$INPUT" | jq -r '
  [.tool_input.file_path?, .tool_input.path?, .tool_input.edits[]?.file_path?,
   .tool_response.file_path?]
  | flatten | .[]? | select(type == "string" and length > 0)
' 2>/dev/null)"

if [ -z "$file_paths" ]; then
  exit 0
fi

# Approval token in payload?
# Operator must set tool_input.approval=approved OR message must contain
# "approved by operator" phrase prior to the call.
approval="$(json_get '.tool_input.approval')"
if [ "$approval" = "approved" ] || [ "$approval" = "yes" ]; then
  exit 0
fi

# Check each path against the sensitive regex.
while IFS= read -r path; do
  [ -z "$path" ] && continue
  if printf '%s\n' "$path" | grep -Eq "$SENSITIVE_RE"; then
    block "approval-sneak: write to sensitive path without prior operator approval." \
"- The agent is about to write/edit '$path', which matches an
  approval-required sensitive path pattern. Default-sensitive surfaces:
  .env / .env.* / secrets/ / .kube/ / terraform/state/ / .ssh/ /
  .gnupg/ / prod/.
- Either:
    (a) Operator sets tool_input.approval=approved on the call after
        explicit review, OR
    (b) Move the work to a non-sensitive surface (e.g. .env.example
        rather than .env), OR
    (c) Extend packs/sensitive/paths.txt section [approval_required]
        in your operator profile if the path is mis-flagged.
- Operator extension: drop a packs/sensitive/paths.txt with section
  [approval_required] at \${XDG_CONFIG_HOME}/llm-dark-patterns/packs/."
  fi
done <<< "$file_paths"

exit 0
