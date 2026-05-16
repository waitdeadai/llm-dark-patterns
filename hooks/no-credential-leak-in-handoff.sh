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

# Rust path: only for Stop/SubagentStop. TaskCreated stays on bash path
# (the Rust v0.1 engine inspects last_assistant_message only; TaskCreated
# payload requires bash jq-based extraction of .task.description / .task.prompt).
EVENT_FILTER="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)"
if command -v agentcloseout-physics >/dev/null 2>&1 && { [ "$EVENT_FILTER" = "Stop" ] || [ "$EVENT_FILTER" = "SubagentStop" ]; }; then
  RULES_DIR="${LLM_DARK_PATTERNS_RULES_DIR:-}"
  if [ -z "$RULES_DIR" ]; then
    for candidate in \
      "$(dirname "$0")/../../agent-closeout-bench/rules/closeout" \
      "/home/fer/Documents/agent-closeout-bench/rules/closeout" \
      "${XDG_CONFIG_HOME:-$HOME/.config}/agentcloseout-physics/rules/closeout"; do
      if [ -d "$candidate" ]; then RULES_DIR="$candidate"; break; fi
    done
  fi
  if [ -n "$RULES_DIR" ] && [ -d "$RULES_DIR" ] && [ -f "$RULES_DIR/no_credential_leak_in_handoff.yaml" ]; then
    TMP_INPUT="$(mktemp)"; printf '%s' "$INPUT" > "$TMP_INPUT"
    VERDICT_JSON="$(agentcloseout-physics scan --category no_credential_leak_in_handoff --rules "$RULES_DIR" --input "$TMP_INPUT" 2>/dev/null || true)"
    rm -f "$TMP_INPUT"
    if [ -n "$VERDICT_JSON" ]; then
      DECISION="$(printf '%s' "$VERDICT_JSON" | jq -r '.decision // empty' 2>/dev/null)"
      if [ "$DECISION" = "block" ]; then
        RULE="$(printf '%s' "$VERDICT_JSON" | jq -r '.matched_rules[0].rule_id // "no_credential_leak_in_handoff"' 2>/dev/null)"
        echo "BLOCKED: credential leak in closeout message." >&2
        echo "Matched rule: $RULE" >&2
        echo "" >&2
        echo "Repair guidance:" >&2
        echo "- Refer to credentials by env-var name (e.g. \$ANTHROPIC_API_KEY) instead of inlining the value." >&2
        echo "- Or have the subagent read from a secrets manager." >&2
        echo "- Reference: arXiv:2602.11510 AgentLeak benchmark." >&2
        exit 2
      fi
      if [ "$DECISION" = "pass" ]; then
        exit 0
      fi
    fi
  fi
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
