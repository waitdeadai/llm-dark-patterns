#!/usr/bin/env bash
# Truth table for the filesystem pack's rm patterns.
#
# The must-ALLOW half is the half that matters: a guard that fires on safe input
# is one the operator eventually disables, and a disabled guard protects nothing.
#
# Bug this pins: `git rm --cached` is an INDEX-ONLY operation — it unstages a
# path and never touches the working tree. The old pattern matched the bare
# substring " rm -r", so a git index operation was refused as a recursive
# filesystem delete. Observed repeatedly in real sessions.
#
# Fix: `rm` must sit at a genuine COMMAND POSITION — start of input, after a
# shell operator, or behind a known wrapper. In `git rm` it is a SUBCOMMAND.

set -uo pipefail
PACK="$(dirname "${BASH_SOURCE[0]}")/../packs/destructive/filesystem.txt"
[ -r "$PACK" ] || { echo "pack not found: $PACK" >&2; exit 3; }

# Load only the rm-related patterns from the pack under test.
mapfile -t PATS < <(grep -vE '^\s*#|^\s*$|^\[' "$PACK" | grep -E '\brm\b')
[ "${#PATS[@]}" -gt 0 ] || { echo "no rm patterns found in pack" >&2; exit 3; }

verdict() { # command -> block|allow
  local cmd="$1" p
  for p in "${PATS[@]}"; do
    printf '%s' "$cmd" | grep -qEi "$p" && { echo block; return; }
  done
  echo allow
}

pass=0; fail=0
check() { # want cmd label
  local got; got="$(verdict "$2")"
  if [ "$got" = "$1" ]; then pass=$((pass+1)); printf '  ok    want=%-5s %s\n' "$1" "$3"
  else fail=$((fail+1)); printf '  FAIL  want=%-5s got=%-5s %s\n      cmd: %s\n' "$1" "$got" "$3" "$2"; fi
}

echo "== rm command-position truth table =="
echo "MUST BLOCK — genuinely destructive:"
check block "rm -rf /tmp/scratch"                     "rm -rf at start of input"
check block "cd /tmp && rm -rf build"                 "after a shell operator"
check block "sudo rm -rf /var/log/old"                "via sudo"
check block "find . -name '*.o' | xargs rm -rf"       "via xargs"
check block "rm --recursive /data/tmp"                "long-form flag"
check block "rm -f /etc/hosts"                        "rm -f against an absolute path"

echo "MUST ALLOW — index-only or harmless:"
check allow "git rm --cached .gitignore"              "git rm --cached (INDEX ONLY)"
check allow "git rm -r --cached vendor"               "git rm -r --cached (INDEX ONLY)"
check allow "git rm --cached -r build"                "flag order swapped"
check allow "npm rm --save-dev eslint"                "npm rm subcommand"
check allow "ls /tmp"                                 "ordinary command"

echo
printf '  %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
