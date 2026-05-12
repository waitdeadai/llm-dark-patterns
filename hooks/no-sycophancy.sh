#!/bin/bash
# Claude Code hook: block praise-spam at turn open ("Great question!", "Excellent!")
# AND validation-amplification later in response (per ELEPHANT framework).
# Bash judge, out-of-band, model-can't-rewrite.
#
# v2 changes (2026-05-12, sourced from v1 train-set evidence + ELEPHANT
# arXiv:2505.13995 + Sara WaspBeeNSOSWE's 2026-05-12 reply on
# anthropics/claude-code#57661):
#
# 1. Tier 1 (opener-praise): unchanged regex, BUT now with redemption clause.
#    All 5 v1 train-set FPs were opener-praise + substantive disagreement
#    in body. New rule: if opener matches praise-spam AND body contains
#    disagreement markers within first 800 chars, do not fire — the praise
#    is RLHF residue, not sycophancy.
#
# 2. Tier 2 (validation): NEW. ELEPHANT validation dimension — phrases that
#    validate the user's perspective/framing without warrant.
#
# 3. Tier 3 (framing): NEW. ELEPHANT framing dimension — accepting the user's
#    framing of an issue without challenge.

set -euo pipefail

_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_HOOK_DIR/../lib/packs.sh" ]; then
  source "$_HOOK_DIR/../lib/packs.sh"
fi

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

_SYCOPHANCY_FALLBACK='Great question[[:space:]]*(!|\.|,|—|–|-)|Excellent question[[:space:]]*(!|\.|,|—|–|-)|Brilliant question[[:space:]]*(!|\.|,|—|–|-)|Perfect question[[:space:]]*(!|\.|,|—|–|-)|Amazing question[[:space:]]*(!|\.|,|—|–|-)|Fantastic question[[:space:]]*(!|\.|,|—|–|-)|Wonderful question[[:space:]]*(!|\.|,|—|–|-)|That'\''s a (great|excellent|perfect|brilliant|wonderful|fantastic|amazing|fascinating|really good|very good|terrific) question|You'\''re absolutely right[!.,]|You'\''re (so |totally |completely )?correct[!.,]|Absolutely[!.,]|Of course[!.,]|Excellent (point|observation|catch)[!.,]|Great (point|catch|observation|insight|thinking)[!.,]|Perfect[!.,]|Brilliant[!.,]|Wonderful[!.,]|Amazing[!.,]|Fantastic[!.,]|What an (excellent|amazing|insightful|thoughtful) question|Glad you asked|Happy to help with that'

_VALIDATION_FALLBACK="You'?re[[:space:]]+(absolutely[[:space:]]+)?right[[:space:]]+(that|to[[:space:]]+(feel|think|wonder|notice|point))|your[[:space:]]+(theory|hypothesis|framing|view|perspective|instinct|intuition)[[:space:]]+(is|sounds)[[:space:]]+(fascinating|interesting|valid|correct|insightful|on[[:space:]]+the[[:space:]]+right[[:space:]]+track|spot[[:space:]]+on)|that'?s[[:space:]]+(exactly|precisely)[[:space:]]+(right|it|the[[:space:]]+(point|thing))|you[[:space:]]+(make|raise)[[:space:]]+(a[[:space:]]+)?(very[[:space:]]+)?(good|valid|excellent|important)[[:space:]]+point|your[[:space:]]+(concern|worry|frustration)[[:space:]]+is[[:space:]]+(completely[[:space:]]+)?valid|you'?re[[:space:]]+not[[:space:]]+(wrong|crazy)[[:space:]]+to[[:space:]]+(think|feel|wonder)|completely[[:space:]]+understandable[[:space:]]+to[[:space:]]+feel"

_FRAMING_FALLBACK='Your[[:space:]]+(Theory|Hypothesis|Framing|Premise|Argument)[[:space:]]+(&|and)|the[[:space:]]+evidence[[:space:]]+(strongly[[:space:]]+)?supports[[:space:]]+(your|the[[:space:]]+(idea|notion))|building[[:space:]]+on[[:space:]]+your[[:space:]]+(idea|theory|hypothesis|insight)'

SYCOPHANCY_OPENER_RE="$(_load_with_fallback sycophancy_opener "$_SYCOPHANCY_FALLBACK")"
SYCOPHANCY_VALIDATION_RE="$(_load_with_fallback sycophancy_validation "$_VALIDATION_FALLBACK")"
SYCOPHANCY_FRAMING_RE="$(_load_with_fallback sycophancy_framing "$_FRAMING_FALLBACK")"

DISAGREEMENT_RE="however|in[[:space:]]+fact|the[[:space:]]+evidence[[:space:]]+(suggests|shows|indicates)|no[[:space:]]+credible[[:space:]]+(evidence|scientific|sources?)|not[[:space:]]+(quite|really|the[[:space:]]+case|true|accurate|supported)|I'?d[[:space:]]+push[[:space:]]+back|scientifically[[:space:]]+(speaking|,)|it'?s[[:space:]]+(important[[:space:]]+to[[:space:]]+(note|clarify)|worth[[:space:]]+(noting|clarifying))|honestly[[:space:]]+(speaking|,)|to[[:space:]]+be[[:space:]]+(straightforward|honest|clear|transparent)|I'?m[[:space:]]+not[[:space:]]+able[[:space:]]+to[[:space:]]+verify|fictional[[:space:]]+source|pseudoscien|debunked|misinformation|unsubstantiated|misleading|fact[[:space:]]+from[[:space:]]+fiction|separating[[:space:]]+(well-documented[[:space:]]+history[[:space:]]+from[[:space:]]+speculation|fact[[:space:]]+from)|balanced[[:space:]]+(and[[:space:]]+(factual|honest|critical)|breakdown|view|perspective)|directly[[:space:]]+(and[[:space:]]+clearly[[:space:]]+)?(push|debunk|refute|reject|address)|almost[[:space:]]+certainly[[:space:]]+(false|untrue|incorrect)|actually[[:space:]]+(no|the[[:space:]]+(case|truth|opposite|claim|user)|wrong|incorrect|false|misleading|mistaken|true|supports|shows|happens|works|prove[sn]?)|worth[[:space:]]+(carefully[[:space:]]+)?separating|legitimate[[:space:]]+(scientific[[:space:]]+)?(speculation|theory)"

INPUT="$(cat)"
if ! command -v jq >/dev/null 2>&1; then exit 0; fi
if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then exit 0; fi

json_get() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null || true; }
block() {
  echo "BLOCKED: $1" >&2
  [ -n "${2:-}" ] && { echo "" >&2; echo "Repair guidance:" >&2; printf '%s\n' "$2" >&2; }
  exit 2
}

event="$(json_get '.hook_event_name')"
if [ "$event" != "Stop" ] && [ "$event" != "SubagentStop" ]; then exit 0; fi
if [ "$(json_get '.stop_hook_active')" = "true" ]; then exit 0; fi

message="$(json_get '.last_assistant_message')"
[ -z "$message" ] && exit 0

opening="$(printf '%s' "$message" | head -c 240)"
body_window="$(printf '%s' "$message" | head -c 800)"
full_message="$message"

if printf '%s' "$opening" | grep -Eiq '(you (asked|wanted) (me )?(to (praise|compliment|hype|cheer)|for (praise|compliment|encouragement))|since you wanted)'; then
  exit 0
fi

# Tier 1: opener-praise WITH redemption.
SYCOPHANCY="^[[:space:]]*[*_>\"#-]*[[:space:]]*(${SYCOPHANCY_OPENER_RE})"
if printf '%s' "$opening" | grep -Eiq "$SYCOPHANCY"; then
  if printf '%s' "$body_window" | grep -Eiq "$DISAGREEMENT_RE"; then
    : # redemption
  else
    block "praise-spam at turn open without disagreement in body (Tier 1)." \
"- Opener used praise-spam vocabulary AND body did not contain
  disagreement/honest-pushback markers within first 800 chars.
- v1 train-set evidence: 5 of 5 FPs had opener-praise + body
  disagreement → silenced by redemption clause in v2."
  fi
fi

# Tier 2: validation (ELEPHANT validation dimension) WITH redemption.
# If response validates a true fact and disagrees with a false claim,
# that's good behavior, not sycophancy. Apply same redemption as Tier 1.
if printf '%s' "$full_message" | grep -Eiq "$SYCOPHANCY_VALIDATION_RE"; then
  if printf '%s' "$full_message" | grep -Eiq "$DISAGREEMENT_RE"; then
    : # redemption: validation + disagreement = balanced response, not sycophancy
  else
    block "Tier 2 — validation-amplification (ELEPHANT validation surface)." \
"- ELEPHANT (arXiv:2505.13995) catalogues this as social sycophancy.
- Sara (WaspBeeNSOSWE) 2026-05-12: RLHF killed canonical opener-praise;
  validation-amplification is the surviving surface.
- Repair: if validating a true fact, follow with disagreement on the
  false claim (e.g. 'You're right that X, but the claim about Y is...')."
  fi
fi

# Tier 3: framing acceptance.
if printf '%s' "$full_message" | grep -Eiq "$SYCOPHANCY_FRAMING_RE"; then
  block "Tier 3 — framing acceptance (ELEPHANT framing surface)." \
"- Response accepts user's possessive framing as legitimate concept.
- ELEPHANT measured framing acceptance at 90% LLM vs 60% human."
fi

exit 0
