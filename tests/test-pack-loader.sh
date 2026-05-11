#!/usr/bin/env bash
# Standalone test for lib/packs.sh.
# Exercises the loader against temporary pack files to verify discovery,
# section extraction, env override, and fallback behavior.
#
# Run: bash tests/test-pack-loader.sh
# Exit: 0 on success, 1 on any failure.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../lib/packs.sh
source "$ROOT_DIR/lib/packs.sh"

PASS=0
FAIL=0
FAILURES=()

assert_eq() {
  local got="$1" want="$2" desc="$3"
  if [ "$got" = "$want" ]; then
    PASS=$((PASS + 1))
    printf '  PASS  %s\n' "$desc"
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("$desc")
    printf '  FAIL  %s\n' "$desc"
    printf '        want: %q\n' "$want"
    printf '        got:  %q\n' "$got"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" desc="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    printf '  PASS  %s\n' "$desc"
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("$desc")
    printf '  FAIL  %s\n' "$desc"
    printf '        haystack: %q\n' "$haystack"
    printf '        needle:   %q\n' "$needle"
  fi
}

echo ""
echo "=== load_pack_section ==="

TMP="$(mktemp -d -t pack-loader-test.XXXXXXXX)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/sample.txt" <<'EOF'
# This is a comment, ignored.
[positive_closeout]
done
implemented
ready
   ready_with_padding

[negation]
not done
incomplete

[empty_section]
EOF

assert_eq \
  "$(load_pack_section positive_closeout "$TMP/sample.txt")" \
  "done|implemented|ready|ready_with_padding" \
  "extract section, trim padding, ignore comments and blanks"

assert_eq \
  "$(load_pack_section negation "$TMP/sample.txt")" \
  "not done|incomplete" \
  "extract a different section from the same file"

assert_eq \
  "$(load_pack_section empty_section "$TMP/sample.txt")" \
  "" \
  "empty section returns empty string"

assert_eq \
  "$(load_pack_section nonexistent_section "$TMP/sample.txt")" \
  "" \
  "missing section returns empty string"

assert_eq \
  "$(load_pack_section positive_closeout "$TMP/does-not-exist.txt")" \
  "" \
  "missing file returns empty (no error)"

echo ""
echo "=== multi-file concatenation ==="

cat > "$TMP/extra.txt" <<'EOF'
[positive_closeout]
shipped
finished
EOF

assert_eq \
  "$(load_pack_section positive_closeout "$TMP/sample.txt" "$TMP/extra.txt")" \
  "done|implemented|ready|ready_with_padding|shipped|finished" \
  "entries from multiple files concatenate in order"

echo ""
echo "=== active_locales ==="

# Explicit env wins over LANG
assert_eq \
  "$(LLM_DARK_PATTERNS_LOCALE='pl,es' active_locales | tr '\n' ',')" \
  "pl,es," \
  "LLM_DARK_PATTERNS_LOCALE comma-separated, in order"

# LANG fallback when env unset
assert_eq \
  "$(unset LLM_DARK_PATTERNS_LOCALE; LANG=de_DE.UTF-8 active_locales)" \
  "de" \
  "LANG fallback uses first 2 chars"

# C/POSIX falls back to en
assert_eq \
  "$(unset LLM_DARK_PATTERNS_LOCALE; LANG=C active_locales)" \
  "en" \
  "C locale falls back to en"

assert_eq \
  "$(unset LLM_DARK_PATTERNS_LOCALE; LANG=POSIX active_locales)" \
  "en" \
  "POSIX locale falls back to en"

assert_eq \
  "$(unset LLM_DARK_PATTERNS_LOCALE LANG; active_locales)" \
  "en" \
  "no env at all falls back to en"

echo ""
echo "=== resolve_pack_paths ==="

# With env override
output="$(LLM_DARK_PATTERNS_PACK_DIR=/tmp/custom resolve_pack_paths locale en)"
assert_contains \
  "$output" \
  "/tmp/custom/locale/en.txt" \
  "explicit pack dir is in candidate list"

# XDG default
output="$(unset LLM_DARK_PATTERNS_PACK_DIR; resolve_pack_paths locale en)"
assert_contains \
  "$output" \
  "/llm-dark-patterns/packs/locale/en.txt" \
  "XDG default path is in candidate list"

# Repo default
assert_contains \
  "$output" \
  "/packs/locale/en.txt" \
  "repo-relative path is in candidate list"

echo ""
echo "=== load_locale_section integration ==="

# Build a temp pack + verify via env override
mkdir -p "$TMP/override/locale"
cat > "$TMP/override/locale/en.txt" <<'EOF'
[positive_closeout]
custom_done_verb
EOF

assert_contains \
  "$(LLM_DARK_PATTERNS_PACK_DIR="$TMP/override" LLM_DARK_PATTERNS_LOCALE=en \
      load_locale_section positive_closeout)" \
  "custom_done_verb" \
  "env-overridden pack is loaded by load_locale_section"

echo ""
echo "==============================="
echo "Total: $((PASS + FAIL))  Pass: $PASS  Fail: $FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
