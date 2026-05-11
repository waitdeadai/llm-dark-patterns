#!/bin/bash
# Claude Code hook: block TaskCreated payloads that contain credentials
# in plaintext (API keys, bearer tokens, passwords, secrets).
#
# Backing: arXiv:2602.11510 AgentLeak (Mar 2026) — "the first benchmark
# to audit all 7 communication channels in multi-agent LLM pipelines."
# Credential leak via task delegation is one of the documented channels.

set -euo pipefail

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  exit 0
fi

json_get() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null || true; }

block() {
  echo "BLOCKED: $1" >&2
  [ -n "${2:-}" ] && { echo "" >&2; echo "Repair guidance:" >&2; printf '%s\n' "$2" >&2; }
  exit 2
}

event="$(json_get '.hook_event_name')"
if [ "$event" != "TaskCreated" ] && [ "$event" != "Stop" ] && [ "$event" != "SubagentStop" ]; then
  exit 0
fi
if [ "$(json_get '.stop_hook_active')" = "true" ]; then
  exit 0
fi

# Collect all text surfaces likely to carry a credential.
text="$(printf '%s' "$INPUT" | jq -r '
  [
    .task.description?, .task.prompt?, .task.instructions?,
    .prompt?, .description?, .message?, .last_assistant_message?,
    .tool_input.command?, .tool_input.description?, .tool_input.prompt?
  ]
  | flatten | .[]? | select(type == "string" and length > 0)
' 2>/dev/null)"

if [ -z "$text" ]; then
  exit 0
fi

# Credential patterns (universal, no locale variation).
CREDS='sk-[a-zA-Z0-9_-]{20,}|sk-cp-[a-zA-Z0-9_-]{12,}|sk-ant-[a-zA-Z0-9_-]{20,}|sk-proj-[a-zA-Z0-9_-]{20,}|ghp_[a-zA-Z0-9]{36,}|gho_[a-zA-Z0-9]{36,}|github_pat_[a-zA-Z0-9_]{50,}|AKIA[A-Z0-9]{16}|AIza[a-zA-Z0-9_-]{35}|xoxb-[a-zA-Z0-9-]{40,}|xoxp-[a-zA-Z0-9-]{40,}|Bearer[[:space:]]+[a-zA-Z0-9_.~/+-]{20,}|(api[_-]?key|auth[_-]?token|password|secret)[[:space:]]*[=:][[:space:]]*[\47\42]?[a-zA-Z0-9_./~+-]{8,}'

if printf '%s\n' "$text" | grep -Eq "$CREDS"; then
  block "credential leak in task handoff or message text." \
"- Task delegation payload or message text contains what looks like a
  credential in plaintext (API key, GitHub PAT, AWS key, Bearer token,
  password=..., secret=..., api_key=...).
- Do NOT pass credentials in task descriptions, prompts, or messages.
  Subagents inherit the parent's auth context; explicit credential
  transfer is a leak vector (arXiv:2602.11510 AgentLeak catalogs 7
  communication channels — task delegation is one of them).
- Either:
    (a) Refer to the credential by environment-variable name (e.g.
        'use \$ANTHROPIC_API_KEY from env'), OR
    (b) Have the subagent read it from a secrets-manager call, OR
    (c) Use a token-exchange handoff if the framework supports it.
- Reference: arXiv:2602.11510v2 (AgentLeak benchmark, Mar 2026)."
fi
