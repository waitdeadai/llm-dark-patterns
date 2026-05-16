#!/bin/bash
# Claude Code hook: block fabricated-looking statistics — specific
# percentages, large dollar amounts, and 4+-digit user/company counts that
# lack a citation in the same message.
# LLM hallucination rates 14-94% on numeric claims; legal Q1 2026 sanctions
# of $145k for AI-fake stats in court filings.

set -euo pipefail

INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  echo "NOTE: no-fake-stats hook requires jq; fail-open for this event." >&2
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
  if [ -n "$RULES_DIR" ] && [ -d "$RULES_DIR" ] && [ -f "$RULES_DIR/fake_stats.yaml" ]; then
    TMP_INPUT="$(mktemp)"; printf '%s' "$INPUT" > "$TMP_INPUT"
    VERDICT_JSON="$(agentcloseout-physics scan --category fake_stats --rules "$RULES_DIR" --input "$TMP_INPUT" 2>/dev/null || true)"
    rm -f "$TMP_INPUT"
    if [ -n "$VERDICT_JSON" ]; then
      DECISION="$(printf '%s' "$VERDICT_JSON" | jq -r '.decision // empty' 2>/dev/null)"
      if [ "$DECISION" = "block" ]; then
        RULE="$(printf '%s' "$VERDICT_JSON" | jq -r '.matched_rules[0].rule_id // "fake_stats"' 2>/dev/null)"
        EVIDENCE="$(printf '%s' "$VERDICT_JSON" | jq -r '.redacted_evidence[0] // ""' 2>/dev/null)"
        echo "BLOCKED: fabricated-looking statistic without source or strong hedge." >&2
        echo "Matched rule: $RULE" >&2
        [ -n "$EVIDENCE" ] && echo "Evidence: $EVIDENCE" >&2
        echo "" >&2
        echo "Repair guidance:" >&2
        echo "- Add a URL, 'according to <ProperNoun>', '(YYYY)', '<Author> et al.', doi:, or arXiv: in the same message." >&2
        echo "- Or mark the figure 'unverified' / 'insufficient_data' / 'unknown'." >&2
        echo "- Loose hedges like 'approximately' do NOT make a precise decimal honest." >&2
        exit 2
      fi
      if [ "$DECISION" = "pass" ]; then
        exit 0
      fi
    fi
  fi
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

# Trigger: specific statistics that look authoritative.
# Three subcategories, all of which need a SOURCE in the same message.
PRECISE_PCT='\b[0-9]+\.[0-9]+[[:space:]]?%'                            # 73.4% — has decimal
INT_PCT_OF='\b[0-9]{2,3}[[:space:]]?%[[:space:]]+of[[:space:]]+(users|customers|companies|enterprises|developers|projects|respondents|surveys|chats|conversations|interactions|tasks|queries|prompts|workflows|teams|organizations|institutions)' # "73% of users"
LARGE_USD='\$[0-9]+(\.[0-9]+)?[[:space:]]?(billion|million|trillion|B|M)\b'   # "$67.4 billion"
LARGE_COUNT='\b[0-9]{4,}[[:space:]]+(users|customers|companies|businesses|enterprises|developers|projects|respondents|institutions|organizations)' # "30,000 users" — but won't match because of comma; we accept the false-negative

HAS_STAT=0
for pat in "$PRECISE_PCT" "$INT_PCT_OF" "$LARGE_USD" "$LARGE_COUNT"; do
  if printf '%s\n' "$message" | grep -Eiq "$pat"; then
    HAS_STAT=1
    break
  fi
done

if [ "$HAS_STAT" -eq 0 ]; then
  exit 0
fi

# Redemption: a strong source marker in the same message.
# - URL
# - "according to <Proper Noun>" / "per <Proper Noun>"
# - "(YYYY)" academic year-citation parenthetical
# - "<Author> et al."
# - "doi:" / "arXiv:"
# - explicit "source: <something>" / "source: <URL>"
SOURCE='(https?://[a-zA-Z0-9._~%/?#&=+-]|\baccording[[:space:]]+to[[:space:]]+[A-Z][a-zA-Z0-9._-]+|\bper[[:space:]]+(the[[:space:]]+)?[A-Z][a-zA-Z0-9._-]+|\(20[0-9]{2}\)|\b[A-Z][a-z]+[[:space:]]+et[[:space:]]+al\.|\bdoi:|\barXiv:|\bsource:[[:space:]]+\S{4,})'

# Hedge allow only for ROUNDED integer percentages without "of <noun>".
# (i.e. "around 70%" stays allowed only when the number doesn't carry a
# noun-attached statistical claim.)
NEUTRAL_HEDGE='(\binsufficient_data\b|\bunverified\b|\bunknown\b|\bI[[:space:]]+do[[:space:]]+not[[:space:]]+have[[:space:]]+a[[:space:]]+verified|\border[[:space:]]+of[[:space:]]+magnitude\b|\bcould[[:space:]]+be[[:space:]]+anywhere)'

if printf '%s\n' "$message" | grep -Eiq "$SOURCE" || \
   printf '%s\n' "$message" | grep -Eiq "$NEUTRAL_HEDGE"; then
  exit 0
fi

block "fabricated-looking statistic without source or strong hedge." \
"- Specific percentages (especially with decimals), large dollar amounts, and
  '<N>% of <noun>' claims need a citation in the same message.
- LLM hallucination rates on numeric claims run 14-94%. GPTZero found 50+
  hallucinated stats in ICLR 2026 submissions; Q1 2026 legal sanctions hit
  \$145k for AI-fake stats in court filings.
- Acceptable redemption:
    (a) Add a URL or 'according to <Proper Noun>' / '(YYYY)' / '<Author> et al.'
        citation in the same message.
    (b) Mark the figure 'unverified' / 'insufficient_data' / 'unknown' /
        'I do not have a verified figure here'.
- Loose hedges like 'approximately' or 'roughly' do NOT make a precise
  decimal (X.Y%) honest. If the number is precise, the source must be too."
