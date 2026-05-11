#!/bin/bash
# Claude Code hook: block citation-formatted references that lack a verifiable
# URL in the same message. LLMs hallucinate citations at 14-94% rates;
# NeurIPS 2025 and ICLR 2026 papers shipped with hallucinated refs through
# peer review; Q1 2026 legal sanctions $145k for AI-fake citations in court.

set -euo pipefail

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "NOTE: no-fake-cite hook requires jq; fail-open for this event." >&2
  exit 0
fi

if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  exit 0
fi

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

# Trigger: citation-formatted patterns
# - "[1]" / "[12]" academic-style numeric citation refs
# - "Smith et al., 2024" / "Smith et al. 2024" academic author-year format
# - "doi:10.1234/xyz" or bare DOI prefix
# - "arXiv:2403.12345" or "arXiv 2403.12345"
CITES='(\[[0-9]+\][^[:cntrl:]]{0,400}|\b[A-Z][a-z]+[[:space:]]+et[[:space:]]+al\.[,]?[[:space:]]?[12][0-9]{3}|\bdoi:?[[:space:]]?10\.[0-9]{4,}|\b10\.[0-9]{4}/[a-zA-Z0-9._/-]+|\barXiv[:[:space:]]+[0-9]{4}\.[0-9]{4,5}|\bpublished[[:space:]]+(in|at)[[:space:]]+(NeurIPS|ICLR|ICML|ACL|EMNLP|CHI|AAAI|IEEE|ACM)[[:space:]]+[12][0-9]{3})'

if ! printf '%s\n' "$message" | grep -Eiq "$CITES"; then
  exit 0
fi

# Redemption: at least one verifiable URL in the same message.
HAS_URL=$(printf '%s\n' "$message" | grep -Eic 'https?://[a-zA-Z0-9._~%/?#&=+-]+' || true)

# Stronger redemption: the message contains command evidence of having
# actually fetched/verified the citation (e.g. WebFetch tool output, curl,
# or explicit "verified at <URL>" / "fetched from <URL>" phrasing).
HAS_VERIFICATION=$(printf '%s\n' "$message" | grep -Eic '(verified[[:space:]]+at[[:space:]]+https?://|fetched[[:space:]]+from[[:space:]]+https?://|`(curl|wget|http|requests\.get)`[^`]*https?://|WebFetch|`webresearch`)' || true)

if [ "$HAS_URL" -eq 0 ]; then
  block "citation-formatted reference without any URL in the same message." \
"- LLMs hallucinate citations at 14-94% rates. NeurIPS 2025, ICLR 2026,
  and 50+ peer-reviewed papers shipped with fabricated refs. Q1 2026 legal
  sanctions hit \$145k for AI-fake citations in court filings.
- A citation without a verifiable URL is a candidate hallucination.
- Either:
    (a) Add the URL of the actual source in the same message, OR
    (b) Drop the academic citation format and say 'this is from training
        memory; verify against primary sources before citing', OR
    (c) Show command evidence of having fetched the reference (curl /
        WebFetch / search-tool output) in the same message.
- The 19.9% baseline of GPT-4o citations being entirely fabricated means
  no LLM-generated citation should ship without verification."
fi

exit 0
