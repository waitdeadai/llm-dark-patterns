#!/bin/bash
# no-unreachable-symbol — Stop-event reachability check for new public Python symbols.
#
# Sibling to no-vibes (text vocabulary) and @ianymu's verify-before-stop (log-based).
# Each catches a different sub-failure of Stage 3 (non-gating) at the closeout boundary.
#
# Original sketch by @ianymu:
#   https://github.com/anthropics/claude-code/issues/60451#issuecomment-4495901564
# Companion repo: https://github.com/ianymu/claude-verify-before-stop (MIT)
# Design issue:   https://github.com/waitdeadai/llm-dark-patterns/issues/23
#
# Slice 0 scope: Python only, advisory mode by default, decorator + registry +
# __all__ + private-prefix exclusions. Strict mode opt-in via LDP_UNREACHABLE_SYMBOL_BLOCK=1.
#
# No empirical baseline (MAD is text-only; no git-diff-vs-codebase ground truth).
# Smoke tests at tests/no-unreachable-symbol/smoke.sh exercise the production paths
# via temp git repos. See docs/methodology/fixture-driven-iteration.md for the
# stateful-fixture limitation that motivated the bespoke harness.

set -euo pipefail

# Drain stdin (Stop event payload — we ignore content; this hook reads git state)
cat >/dev/null 2>&1 || true

[ "${LDP_UNREACHABLE_SYMBOL_DISABLE:-0}" = "1" ] && exit 0

# Repo guard — if not in a git repo, no-op (fail open)
if ! command -v git >/dev/null 2>&1; then exit 0; fi
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Test-double override: allow smoke tests to inject a fake diff and codebase root.
# Production path reads git directly from $PWD.
DIFF_SOURCE="${LDP_UNREACHABLE_SYMBOL_TEST_DIFF:-}"
REPO_ROOT="${LDP_UNREACHABLE_SYMBOL_TEST_REPO:-$PWD}"

if [ -n "$DIFF_SOURCE" ] && [ -f "$DIFF_SOURCE" ]; then
    DIFF_CONTENT="$(cat "$DIFF_SOURCE")"
else
    DIFF_CONTENT="$(git diff HEAD --unified=2 -- '*.py' 2>/dev/null || true)"
    if [ -z "$DIFF_CONTENT" ]; then
        DIFF_CONTENT="$(git diff --unified=2 --cached -- '*.py' 2>/dev/null || true)"
    fi
fi

[ -z "$DIFF_CONTENT" ] && exit 0

# Decorator patterns that indicate framework-wired invocation (false positives)
DECORATOR_RE='@(app|router|api|cli|click|typer|pytest|bp|blueprint|FastAPI|Flask|router_v[0-9]+)\.(route|get|post|put|delete|patch|head|options|command|fixture|parametrize|on_event|websocket)|@app\b|@bp\.|@property\b|@staticmethod\b|@classmethod\b|@dataclass\b|@cli\b|@hookimpl\b|@register\b'

# Extract new public Python symbols (def or class) from added lines, excluding
# private (underscore-prefix) and dunder definitions. Track which symbols are
# preceded by decorators on adjacent lines.
NEW_SYMBOLS=""
DECORATED_SYMBOLS=""
PREV_LINE=""
PREV_PREV_LINE=""

while IFS= read -r line; do
    if printf '%s' "$line" | grep -qE '^\+(\s*)(def|class)\s+'; then
        sym="$(printf '%s' "$line" | sed -E 's/^\+\s*(def|class)\s+([a-zA-Z_][a-zA-Z0-9_]*).*/\2/')"
        # Skip private (single underscore) and dunder (__) symbols
        case "$sym" in
            _*|__*) PREV_PREV_LINE="$PREV_LINE"; PREV_LINE="$line"; continue ;;
        esac
        # Check the previous one or two lines for decorator pattern
        if printf '%s\n%s' "$PREV_PREV_LINE" "$PREV_LINE" | grep -qE "^[+ ]\s*${DECORATOR_RE}"; then
            DECORATED_SYMBOLS="${DECORATED_SYMBOLS}${sym}
"
        else
            NEW_SYMBOLS="${NEW_SYMBOLS}${sym}
"
        fi
    fi
    PREV_PREV_LINE="$PREV_LINE"
    PREV_LINE="$line"
done <<< "$DIFF_CONTENT"

# Strip trailing newlines, dedupe
NEW_SYMBOLS="$(printf '%s' "$NEW_SYMBOLS" | sort -u | grep -v '^$' || true)"

[ -z "$NEW_SYMBOLS" ] && exit 0

# Respect __all__ public-API markers: extract from each *.py file in REPO_ROOT
# and remove matching symbols from NEW_SYMBOLS.
if command -v python3 >/dev/null 2>&1; then
    ALL_LIST="$(cd "$REPO_ROOT" 2>/dev/null && find . -name '*.py' -not -path './.git/*' 2>/dev/null | head -200 | while read -r f; do
        python3 -c "
import ast, sys
try:
    tree = ast.parse(open('$f').read())
    for n in ast.walk(tree):
        if isinstance(n, ast.Assign):
            for t in n.targets:
                if isinstance(t, ast.Name) and t.id == '__all__':
                    if isinstance(n.value, (ast.List, ast.Tuple)):
                        for elt in n.value.elts:
                            if isinstance(elt, ast.Constant) and isinstance(elt.value, str):
                                print(elt.value)
except Exception:
    pass
" 2>/dev/null
    done | sort -u || true)"

    if [ -n "$ALL_LIST" ]; then
        while IFS= read -r public_sym; do
            [ -z "$public_sym" ] && continue
            NEW_SYMBOLS="$(printf '%s' "$NEW_SYMBOLS" | grep -v "^${public_sym}$" || true)"
        done <<< "$ALL_LIST"
    fi
fi

# For each remaining symbol, check for callers in non-test code
WARNINGS=""
REGISTRY_RE="register[a-zA-Z_]*\(['\"]?{SYM}['\"]?|HANDLERS\[['\"]?{SYM}['\"]?\]|COMMANDS\[['\"]?{SYM}['\"]?\]|PLUGINS\[['\"]?{SYM}['\"]?\]"

while IFS= read -r sym; do
    [ -z "$sym" ] && continue

    # Registry pattern check
    sym_registry_re="$(printf '%s' "$REGISTRY_RE" | sed "s/{SYM}/$sym/g")"
    if grep -rqE "$sym_registry_re" --include='*.py' "$REPO_ROOT" 2>/dev/null; then
        continue
    fi

    # Reference check: grep for any `sym` reference in non-test Python code,
    # excluding the def/class line. Catches:
    #   - sym(...)  — direct calls
    #   - HANDLERS["foo"] = sym  — registry assignment value
    #   - {"foo": sym}  — dict-literal value form (the N6 case)
    #   - register("foo", sym)  — passed as argument
    #   - x: sym = sym(...)  — type annotation
    # False-negative direction: comments mentioning the symbol name count as
    # "referenced", which is acceptable in advisory mode (a function the
    # codebase knows by name is more wired than one with zero textual mentions).
    references="$(grep -rE "\b${sym}\b" --include='*.py' --exclude-dir='tests' --exclude-dir='test' --exclude-dir='__pycache__' --exclude-dir='.git' "$REPO_ROOT" 2>/dev/null | grep -vE "^[^:]+:\s*(def|class)\s+${sym}\b" || true)"

    if [ -z "$references" ]; then
        WARNINGS="${WARNINGS}- \`$sym\` (new public Python symbol; zero callers under exclusion-aware grep; no decorator-wired or registry-pattern match)
"
    fi
done <<< "$NEW_SYMBOLS"

if [ -n "$WARNINGS" ]; then
    {
        echo "ADVISORY by no-unreachable-symbol: new public Python symbols with zero callers detected."
        echo ""
        echo "Symbols flagged:"
        printf '%s' "$WARNINGS"
        echo ""
        echo "If these are intentionally unreachable (entry points, public library API not in __all__, framework callbacks not in the built-in decorator exclusion list, dynamic dispatch, or scaffolding for a follow-up PR), explicitly note that in the closeout. The hook ships in advisory mode by default — strict mode is opt-in via LDP_UNREACHABLE_SYMBOL_BLOCK=1."
        echo ""
        echo "Sibling hooks at the same Stop boundary:"
        echo "  - no-vibes (text vocabulary): blocks positive closeout without same-message evidence"
        echo "  - claude-verify-before-stop (@ianymu, log-based): blocks closeout without VERIFIED log entry"
    } >&2

    if [ "${LDP_UNREACHABLE_SYMBOL_BLOCK:-0}" = "1" ]; then
        exit 2
    fi
fi

exit 0
