#!/bin/bash
# no-unreachable-symbol — Stop-event reachability check for new public symbols.
#
# Sibling to no-vibes (text vocabulary) and @ianymu's verify-before-stop (log-based).
# Each catches a different sub-failure of Stage 3 (non-gating) at the closeout boundary.
#
# Original sketch by @ianymu:
#   https://github.com/anthropics/claude-code/issues/60451#issuecomment-4495901564
# Companion repo: https://github.com/ianymu/claude-verify-before-stop (MIT)
# Design issue:   https://github.com/waitdeadai/llm-dark-patterns/issues/23
#
# Slice scope:
#   Slice 0: Python   (def / class; decorator + registry + __all__ + private exclusions)
#   Slice 1: TS / JS  (export function/class/const; NestJS/Angular/Next.js decorators +
#                      path-glob skip + index.ts re-export + registry exclusions)
#   Slice 2: Rust + Go (planned)
#
# Advisory mode by default. Strict mode opt-in via LDP_UNREACHABLE_SYMBOL_BLOCK=1.
#
# No empirical baseline (MAD is text-only; no git-diff-vs-codebase ground truth).
# Smoke tests at tests/no-unreachable-symbol/smoke.sh exercise production paths
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

# Aggregate warnings across all languages
ALL_WARNINGS=""

# ----------- Python (Slice 0) -----------

PY_DIFF=""
if [ -n "$DIFF_SOURCE" ] && [ -f "$DIFF_SOURCE" ]; then
    PY_DIFF="$(grep -A2000 '^diff --git.*\.py' "$DIFF_SOURCE" 2>/dev/null || cat "$DIFF_SOURCE")"
else
    PY_DIFF="$(git diff HEAD --unified=2 -- '*.py' 2>/dev/null || true)"
    [ -z "$PY_DIFF" ] && PY_DIFF="$(git diff --unified=2 --cached -- '*.py' 2>/dev/null || true)"
fi

if [ -n "$PY_DIFF" ]; then
    # Python decorator patterns indicating framework-wired invocation
    PY_DECORATOR_RE='@(app|router|api|cli|click|typer|pytest|bp|blueprint|FastAPI|Flask|router_v[0-9]+)\.(route|get|post|put|delete|patch|head|options|command|fixture|parametrize|on_event|websocket)|@app\b|@bp\.|@property\b|@staticmethod\b|@classmethod\b|@dataclass\b|@cli\b|@hookimpl\b|@register\b'

    PY_NEW_SYMBOLS=""
    PY_PREV_LINE=""
    PY_PREV_PREV_LINE=""

    while IFS= read -r line; do
        if printf '%s' "$line" | grep -qE '^\+(\s*)(def|class)\s+'; then
            sym="$(printf '%s' "$line" | sed -E 's/^\+\s*(def|class)\s+([a-zA-Z_][a-zA-Z0-9_]*).*/\2/')"
            case "$sym" in
                _*|__*) PY_PREV_PREV_LINE="$PY_PREV_LINE"; PY_PREV_LINE="$line"; continue ;;
            esac
            if printf '%s\n%s' "$PY_PREV_PREV_LINE" "$PY_PREV_LINE" | grep -qE "^[+ ]\s*${PY_DECORATOR_RE}"; then
                : # decorated — skip
            else
                PY_NEW_SYMBOLS="${PY_NEW_SYMBOLS}${sym}
"
            fi
        fi
        PY_PREV_PREV_LINE="$PY_PREV_LINE"
        PY_PREV_LINE="$line"
    done <<< "$PY_DIFF"

    PY_NEW_SYMBOLS="$(printf '%s' "$PY_NEW_SYMBOLS" | sort -u | grep -v '^$' || true)"

    # Respect __all__ markers
    if [ -n "$PY_NEW_SYMBOLS" ] && command -v python3 >/dev/null 2>&1; then
        ALL_LIST="$(cd "$REPO_ROOT" 2>/dev/null && find . -name '*.py' -not -path './.git/*' 2>/dev/null | head -200 | while read -r f; do
            python3 -c "
import ast
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
                PY_NEW_SYMBOLS="$(printf '%s' "$PY_NEW_SYMBOLS" | grep -v "^${public_sym}$" || true)"
            done <<< "$ALL_LIST"
        fi
    fi

    PY_REGISTRY_RE="register[a-zA-Z_]*\(['\"]?{SYM}['\"]?|HANDLERS\[['\"]?{SYM}['\"]?\]|COMMANDS\[['\"]?{SYM}['\"]?\]|PLUGINS\[['\"]?{SYM}['\"]?\]"

    while IFS= read -r sym; do
        [ -z "$sym" ] && continue
        sym_registry_re="$(printf '%s' "$PY_REGISTRY_RE" | sed "s/{SYM}/$sym/g")"
        if grep -rqE "$sym_registry_re" --include='*.py' "$REPO_ROOT" 2>/dev/null; then
            continue
        fi
        references="$(grep -rE "\b${sym}\b" --include='*.py' --exclude-dir='tests' --exclude-dir='test' --exclude-dir='__pycache__' --exclude-dir='.git' "$REPO_ROOT" 2>/dev/null | grep -vE "^[^:]+:\s*(def|class)\s+${sym}\b" || true)"
        if [ -z "$references" ]; then
            ALL_WARNINGS="${ALL_WARNINGS}- \`$sym\` [Python] — new public symbol; zero references under exclusion-aware grep; no decorator/registry match
"
        fi
    done <<< "$PY_NEW_SYMBOLS"
fi

# ----------- TypeScript / JavaScript (Slice 1) -----------

TS_DIFF=""
if [ -n "$DIFF_SOURCE" ] && [ -f "$DIFF_SOURCE" ]; then
    TS_DIFF="$(grep -A2000 '^diff --git.*\.\(tsx?\|jsx?\|mjs\)' "$DIFF_SOURCE" 2>/dev/null || cat "$DIFF_SOURCE")"
else
    TS_DIFF="$(git diff HEAD --unified=2 -- '*.ts' '*.tsx' '*.js' '*.jsx' '*.mjs' 2>/dev/null || true)"
    [ -z "$TS_DIFF" ] && TS_DIFF="$(git diff --unified=2 --cached -- '*.ts' '*.tsx' '*.js' '*.jsx' '*.mjs' 2>/dev/null || true)"
fi

if [ -n "$TS_DIFF" ]; then
    # TS/JS decorator patterns indicating framework-wired invocation
    # NestJS, Angular, TypeORM, generic frameworks
    TS_DECORATOR_RE='@(Controller|Injectable|Module|Component|Directive|Pipe|NgModule|Entity|Repository|Get|Post|Put|Delete|Patch|Head|Options|All|Sse|UseGuards|UseInterceptors|UsePipes|UseFilters|Catch|ApiTags|ApiOperation|ApiProperty|Schema|Prop|Resolver|Query|Mutation|Subscription|Args|Field|InputType|ObjectType|EventPattern|MessagePattern|Cron|Interval|Timeout|WebSocketGateway|SubscribeMessage|MessageBody|ConnectedSocket)\s*[(@]'

    # Path globs where exports are framework-wired (Next.js, Express conventions)
    # Track which file each new symbol came from
    TS_NEW_SYMBOLS=""
    TS_CURRENT_FILE=""
    TS_PREV_LINE=""

    while IFS= read -r line; do
        # Track current file from diff header
        if printf '%s' "$line" | grep -qE '^diff --git a/'; then
            TS_CURRENT_FILE="$(printf '%s' "$line" | sed -E 's|^diff --git a/([^ ]+) .*|\1|')"
        fi

        # Skip if file is in a framework-conventions path
        case "$TS_CURRENT_FILE" in
            pages/*|*/pages/*|app/*|*/app/*|api/*|*/api/*|routes/*|*/routes/*)
                TS_PREV_LINE="$line"
                continue
                ;;
        esac

        # Extract exported symbols (require an identifier-start char after the keyword
        # so anonymous defaults like `export default function ()` are skipped)
        sym=""
        if printf '%s' "$line" | grep -qE '^\+\s*export\s+(async\s+)?function\s+[a-zA-Z_$]'; then
            sym="$(printf '%s' "$line" | sed -E 's/^\+\s*export\s+(async\s+)?function\s+([a-zA-Z_$][a-zA-Z0-9_$]*).*/\2/')"
        elif printf '%s' "$line" | grep -qE '^\+\s*export\s+class\s+[a-zA-Z_$]'; then
            sym="$(printf '%s' "$line" | sed -E 's/^\+\s*export\s+class\s+([a-zA-Z_$][a-zA-Z0-9_$]*).*/\1/')"
        elif printf '%s' "$line" | grep -qE '^\+\s*export\s+(const|let|var)\s+[a-zA-Z_$]'; then
            sym="$(printf '%s' "$line" | sed -E 's/^\+\s*export\s+(const|let|var)\s+([a-zA-Z_$][a-zA-Z0-9_$]*).*/\2/')"
        elif printf '%s' "$line" | grep -qE '^\+\s*export\s+default\s+(async\s+)?function\s+[a-zA-Z_$]'; then
            sym="$(printf '%s' "$line" | sed -E 's/^\+\s*export\s+default\s+(async\s+)?function\s+([a-zA-Z_$][a-zA-Z0-9_$]*).*/\2/')"
        elif printf '%s' "$line" | grep -qE '^\+\s*export\s+default\s+class\s+[a-zA-Z_$]'; then
            sym="$(printf '%s' "$line" | sed -E 's/^\+\s*export\s+default\s+class\s+([a-zA-Z_$][a-zA-Z0-9_$]*).*/\1/')"
        fi

        if [ -n "$sym" ]; then
            # Skip private prefix
            case "$sym" in
                _*) TS_PREV_LINE="$line"; continue ;;
            esac
            # Check previous line for decorator
            if printf '%s' "$TS_PREV_LINE" | grep -qE "^[+ ]\s*${TS_DECORATOR_RE}"; then
                : # decorated — skip
            else
                TS_NEW_SYMBOLS="${TS_NEW_SYMBOLS}${sym}
"
            fi
        fi
        TS_PREV_LINE="$line"
    done <<< "$TS_DIFF"

    TS_NEW_SYMBOLS="$(printf '%s' "$TS_NEW_SYMBOLS" | sort -u | grep -v '^$' || true)"

    # Skip symbols re-exported from any index.{ts,tsx,js,jsx} (barrel files = public API)
    if [ -n "$TS_NEW_SYMBOLS" ]; then
        INDEX_EXPORTS="$(grep -rhE "^export\s+(\{[^}]*\}|\*)" --include='index.ts' --include='index.tsx' --include='index.js' --include='index.jsx' "$REPO_ROOT" 2>/dev/null | tr ',' '\n' | sed -E 's/.*\{|\}.*//g' | sed -E 's/^\s*([a-zA-Z_$][a-zA-Z0-9_$]*).*/\1/' | sort -u || true)"
        if [ -n "$INDEX_EXPORTS" ]; then
            while IFS= read -r public_sym; do
                [ -z "$public_sym" ] && continue
                TS_NEW_SYMBOLS="$(printf '%s' "$TS_NEW_SYMBOLS" | grep -v "^${public_sym}$" || true)"
            done <<< "$INDEX_EXPORTS"
        fi
    fi

    TS_REGISTRY_RE="register[a-zA-Z_]*\(['\"]?{SYM}['\"]?|HANDLERS\[['\"]?{SYM}['\"]?\]|COMMANDS\[['\"]?{SYM}['\"]?\]|PLUGINS\[['\"]?{SYM}['\"]?\]|ROUTES\[['\"]?{SYM}['\"]?\]"

    while IFS= read -r sym; do
        [ -z "$sym" ] && continue
        sym_registry_re="$(printf '%s' "$TS_REGISTRY_RE" | sed "s/{SYM}/$sym/g")"
        if grep -rqE "$sym_registry_re" --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' --include='*.mjs' "$REPO_ROOT" 2>/dev/null; then
            continue
        fi
        # Reference-permissive check across all TS/JS variants, excluding tests + dist + node_modules
        references="$(grep -rE "\b${sym}\b" --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' --include='*.mjs' --exclude-dir='tests' --exclude-dir='test' --exclude-dir='__tests__' --exclude-dir='node_modules' --exclude-dir='dist' --exclude-dir='build' --exclude-dir='.next' --exclude-dir='.git' "$REPO_ROOT" 2>/dev/null | grep -vE "^[^:]+:\s*export\s+(default\s+)?(async\s+)?(function|class|const|let|var)\s+${sym}\b" || true)"
        if [ -z "$references" ]; then
            ALL_WARNINGS="${ALL_WARNINGS}- \`$sym\` [TypeScript/JavaScript] — new exported symbol; zero references under exclusion-aware grep; no decorator/registry/barrel-export match
"
        fi
    done <<< "$TS_NEW_SYMBOLS"
fi

# ----------- No language picked up anything: exit -----------

if [ -z "$ALL_WARNINGS" ]; then
    exit 0
fi

# ----------- Emit advisory -----------

{
    echo "ADVISORY by no-unreachable-symbol: new public symbols with zero references detected."
    echo ""
    echo "Symbols flagged:"
    printf '%s' "$ALL_WARNINGS"
    echo ""
    echo "If these are intentionally unreachable (entry points, public library API not exported from index, framework callbacks not in the built-in decorator exclusion list, dynamic dispatch, or scaffolding for a follow-up PR), explicitly note that in the closeout. The hook ships in advisory mode by default — strict mode is opt-in via LDP_UNREACHABLE_SYMBOL_BLOCK=1."
    echo ""
    echo "Sibling hooks at the same Stop boundary:"
    echo "  - no-vibes (text vocabulary): blocks positive closeout without same-message evidence"
    echo "  - claude-verify-before-stop (@ianymu, log-based): blocks closeout without VERIFIED log entry"
} >&2

if [ "${LDP_UNREACHABLE_SYMBOL_BLOCK:-0}" = "1" ]; then
    exit 2
fi

exit 0
