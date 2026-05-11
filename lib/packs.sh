#!/bin/bash
# Shared pack loader for the LLM Dark Patterns hooks suite.
#
# Provides three helpers:
#   active_locales         — locale codes to load, in priority order
#   resolve_pack_paths     — file paths to look for a named pack
#   load_pack_section      — pipe-joined entries from a section across files
#
# Pack file format (one entry per line, blank lines and `#` comments ignored,
# `[section]` headers group entries):
#
#     # packs/locale/en.txt
#     [positive_closeout]
#     done
#     complete
#     implemented
#
#     [negation]
#     not done
#     not complete
#     never ran
#
# Discovery priority (highest first):
#   1. $LLM_DARK_PATTERNS_PACK_DIR/<subdir>/<name>.txt    (explicit override)
#   2. ${XDG_CONFIG_HOME:-$HOME/.config}/llm-dark-patterns/packs/<subdir>/<name>.txt
#   3. <hook_script_dir>/../packs/<subdir>/<name>.txt    (ships with repo)
#
# Each hook calls load_pack_section after computing the list of files via
# resolve_pack_paths for every active locale. Entries from all existing files
# are concatenated, so an operator can extend a packed locale by dropping a
# file at the XDG location without forking.

# Echo active locale codes, one per line, in priority order.
#
# Behavior:
#   - If LLM_DARK_PATTERNS_LOCALE is set, it is the exact operator choice
#     (no implicit additions). Comma-separated values become one per line.
#   - Otherwise, English is always loaded as a base, plus the LANG-detected
#     locale if non-trivial. This matches real Claude usage where code keywords
#     stay English while prose is in the operator's language.
#   - C / POSIX / unset LANG → just "en".
active_locales() {
  if [ -n "${LLM_DARK_PATTERNS_LOCALE:-}" ]; then
    printf '%s\n' "$LLM_DARK_PATTERNS_LOCALE" | tr ',' '\n' | grep -v '^[[:space:]]*$'
    return
  fi
  echo "en"
  if [ -n "${LANG:-}" ] && [ "${LANG:0:1}" != "C" ] && [ "${LANG:0:1}" != "P" ]; then
    local detected="${LANG:0:2}"
    if [ "$detected" != "en" ]; then
      printf '%s\n' "$detected"
    fi
  fi
}

# Echo candidate file paths for a pack, one per line, in priority order.
# Args: subdir (e.g. "locale"), name (e.g. "en")
# The caller passes ALL paths to load_pack_section; that function reads
# every path that exists (so operator local overrides extend, don't replace).
resolve_pack_paths() {
  local subdir="$1" name="$2"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)"

  if [ -n "${LLM_DARK_PATTERNS_PACK_DIR:-}" ]; then
    printf '%s\n' "$LLM_DARK_PATTERNS_PACK_DIR/$subdir/$name.txt"
  fi
  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/llm-dark-patterns/packs/$subdir/$name.txt"
  printf '%s\n' "$script_dir/../packs/$subdir/$name.txt"
}

# Echo the pipe-joined entries from a given [section] across one or more
# pack files. Suitable for use in grep -E alternation, e.g.:
#   POSITIVE_VERBS="$(load_pack_section positive_closeout file1.txt file2.txt)"
#   grep -Eiq "(^|[^[:alpha:]])($POSITIVE_VERBS)([^[:alpha:]]|$)"
load_pack_section() {
  local section="$1"
  shift

  local entries=()
  local file line trimmed
  for file in "$@"; do
    [ -z "$file" ] && continue
    [ -f "$file" ] || continue
    while IFS= read -r line; do
      trimmed="${line#"${line%%[![:space:]]*}"}"
      trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
      [ -z "$trimmed" ] && continue
      entries+=("$trimmed")
    done < <(awk -v sec="[$section]" '
      $0 == sec { in_section=1; next }
      /^\[.*\][[:space:]]*$/ { in_section=0; next }
      in_section && NF > 0 && $0 !~ /^[[:space:]]*#/ { print }
    ' "$file")
  done

  if [ "${#entries[@]}" -eq 0 ]; then
    return
  fi

  local IFS="|"
  printf '%s' "${entries[*]}"
}

# Convenience wrapper: load a section from the active locale packs.
# Args: section (e.g. "positive_closeout")
# Echoes the pipe-joined alternation regex.
load_locale_section() {
  local section="$1"
  local locale paths_array=()
  local path

  while IFS= read -r locale; do
    [ -z "$locale" ] && continue
    while IFS= read -r path; do
      paths_array+=("$path")
    done < <(resolve_pack_paths "locale" "$locale")
  done < <(active_locales)

  load_pack_section "$section" "${paths_array[@]}"
}
