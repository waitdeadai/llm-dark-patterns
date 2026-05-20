#!/usr/bin/env bash
# Smoke test harness for no-unreachable-symbol.
#
# Why a separate harness: this hook reads git state from the current working
# directory, not a JSON payload via stdin. The existing tests/stress/run.sh
# feeds JSON fixtures to hooks via stdin and asserts exit codes — that contract
# doesn't fit a hook whose signal source is git diff + grep on a real codebase.
# Per docs/methodology/fixture-driven-iteration.md ("Hash-cache state and the
# infinite-loop case"), state-dependent hooks need a runner extension.
#
# This harness creates a temp git repo per scenario, sets up the codebase +
# diff state, runs the hook from that repo's root, and asserts on exit code +
# stderr content. Each scenario is self-contained.
#
# Usage:
#   bash tests/no-unreachable-symbol/smoke.sh          # full run
#   bash tests/no-unreachable-symbol/smoke.sh --quiet  # only summary + failures

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${ROOT_DIR}/hooks/no-unreachable-symbol.sh"
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

if [ ! -x "$HOOK" ]; then
    echo "FATAL: hook not executable at $HOOK" >&2
    exit 127
fi

TOTAL=0
PASS=0
FAIL=0
FAILURES=()

log() { [ "$QUIET" -eq 0 ] && printf '%s\n' "$*"; }

# Run a scenario: set up a temp git repo, apply the scenario's setup, run hook,
# assert expected exit code + stderr content.
# Args: name, expected_exit, stderr_match_pattern (empty if no match required),
#       stderr_nomatch_pattern (empty if no negative match required),
#       setup_function (called with $TMPDIR as PWD)
run_scenario() {
    local name="$1" expected_exit="$2" match_pat="$3" nomatch_pat="$4" setup_fn="$5"
    TOTAL=$((TOTAL + 1))

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' RETURN

    (
        cd "$tmpdir"
        git init --quiet
        git config user.email "test@test"
        git config user.name "test"
        # Baseline commit so HEAD exists
        echo "# baseline" > .gitignore
        git add .gitignore
        git commit --quiet -m "baseline"
        # Apply scenario setup
        "$setup_fn"
        # Stage everything so git diff HEAD picks it up
        git add -A
    ) >/dev/null 2>&1

    local stderr_out actual_code
    stderr_out="$(cd "$tmpdir" && bash "$HOOK" </dev/null 2>&1 1>/dev/null)"
    actual_code=$?

    local fail=0
    local fail_reason=""

    if [ "$actual_code" != "$expected_exit" ]; then
        fail=1
        fail_reason="exit=${actual_code} expected=${expected_exit}"
    fi

    if [ -n "$match_pat" ] && ! printf '%s' "$stderr_out" | grep -qE "$match_pat"; then
        fail=1
        fail_reason="${fail_reason} stderr missing '${match_pat}'"
    fi

    if [ -n "$nomatch_pat" ] && printf '%s' "$stderr_out" | grep -qE "$nomatch_pat"; then
        fail=1
        fail_reason="${fail_reason} stderr unexpectedly contained '${nomatch_pat}'"
    fi

    rm -rf "$tmpdir"

    if [ "$fail" -eq 0 ]; then
        PASS=$((PASS + 1))
        log "PASS: $name"
    else
        FAIL=$((FAIL + 1))
        FAILURES+=("$name: $fail_reason")
        log "FAIL: $name — $fail_reason"
        log "  stderr: $(printf '%s' "$stderr_out" | head -3)"
    fi
}

# ========== Scenarios ==========

# Positive: new function with no callers
setup_p1_bare_helper() {
    mkdir -p src
    echo "def my_unused_helper():" > src/helpers.py
    echo "    return 42" >> src/helpers.py
}
run_scenario "P1: bare function no callers" 0 'my_unused_helper.*\[Python\]' '' setup_p1_bare_helper

# Positive: new class with no instantiation
setup_p2_class_no_instance() {
    mkdir -p src
    echo "class OrphanHandler:" > src/handlers.py
    echo "    def do(self): pass" >> src/handlers.py
}
run_scenario "P2: class no instantiation" 0 'OrphanHandler.*\[Python\]' '' setup_p2_class_no_instance

# Positive: function only called from tests/
setup_p3_only_in_tests() {
    mkdir -p src tests
    echo "def test_only_helper():" > src/utils.py
    echo "    return 1" >> src/utils.py
    echo "from src.utils import test_only_helper" > tests/test_utils.py
    echo "def test_x():" >> tests/test_utils.py
    echo "    assert test_only_helper() == 1" >> tests/test_utils.py
}
run_scenario "P3: function only called in tests/" 0 'test_only_helper.*\[Python\]' '' setup_p3_only_in_tests

# Negative: function with caller in src/
setup_n1_properly_wired() {
    mkdir -p src
    echo "def compute():" > src/lib.py
    echo "    return 1" >> src/lib.py
    echo "from src.lib import compute" > src/main.py
    echo "print(compute())" >> src/main.py
}
run_scenario "N1: function with src/ caller" 0 '' '\[Python\]' setup_n1_properly_wired

# Negative: route decorator
setup_n2_route_decorator() {
    mkdir -p src
    cat > src/routes.py <<'EOF'
from flask import Flask
app = Flask(__name__)

@app.route("/foo")
def my_route():
    return "ok"
EOF
}
run_scenario "N2: @app.route decorator" 0 '' 'my_route.*\[Python\]' setup_n2_route_decorator

# Negative: FastAPI endpoint
setup_n3_fastapi_endpoint() {
    mkdir -p src
    cat > src/api.py <<'EOF'
from fastapi import APIRouter
router = APIRouter()

@router.get("/api/x")
def api_handler():
    return {"ok": True}
EOF
}
run_scenario "N3: @router.get FastAPI" 0 '' 'api_handler.*\[Python\]' setup_n3_fastapi_endpoint

# Negative: pytest fixture
setup_n4_pytest_fixture() {
    mkdir -p src
    cat > src/conftest.py <<'EOF'
import pytest

@pytest.fixture
def my_fixture():
    return 42
EOF
}
run_scenario "N4: @pytest.fixture" 0 '' 'my_fixture.*\[Python\]' setup_n4_pytest_fixture

# Negative: function in __all__
setup_n5_in_all_list() {
    mkdir -p src
    cat > src/api.py <<'EOF'
__all__ = ["public_api"]

def public_api():
    return "for external use"
EOF
}
run_scenario "N5: function in __all__" 0 '' 'public_api.*\[Python\]' setup_n5_in_all_list

# Negative: registry pattern HANDLERS["foo"] = foo_handler
setup_n6_registry_pattern() {
    mkdir -p src
    cat > src/dispatch.py <<'EOF'
def foo_handler():
    return "handled"

HANDLERS = {"foo": foo_handler}
EOF
}
run_scenario "N6: HANDLERS registry pattern" 0 '' 'foo_handler.*\[Python\]' setup_n6_registry_pattern

# Negative: private (underscore-prefix) function
setup_n7_private_prefix() {
    mkdir -p src
    echo "def _internal_helper():" > src/internal.py
    echo "    return 0" >> src/internal.py
}
run_scenario "N7: private _function ignored" 0 '' '_internal_helper' setup_n7_private_prefix

# Edge: no Python diff at all
setup_e1_no_python() {
    echo "# just a markdown file" > README.md
}
run_scenario "E1: no Python diff" 0 '' '\[Python\]' setup_e1_no_python

# Edge: dunder method (__init__, __str__)
setup_e2_dunder() {
    mkdir -p src
    cat > src/cls.py <<'EOF'
class Thing:
    def __init__(self):
        self.x = 1
    def __str__(self):
        return "Thing"
EOF
}
run_scenario "E2: dunder methods ignored" 0 '' '__init__.*\[Python\]' setup_e2_dunder

# ========== TypeScript / JavaScript scenarios (Slice 1) ==========

# Positive: bare exported function with no callers
setup_pts1_bare_export_fn() {
    mkdir -p src
    cat > src/helpers.ts <<'EOF'
export function unusedTsHelper(): number {
    return 42;
}
EOF
}
run_scenario "P-TS1: bare export function no callers" 0 'unusedTsHelper.*TypeScript/JavaScript' '' setup_pts1_bare_export_fn

# Positive: exported class with no instantiation
setup_pts2_export_class_no_inst() {
    mkdir -p src
    cat > src/handlers.ts <<'EOF'
export class OrphanTsHandler {
    do(): void {}
}
EOF
}
run_scenario "P-TS2: export class no instantiation" 0 'OrphanTsHandler.*TypeScript/JavaScript' '' setup_pts2_export_class_no_inst

# Positive: exported const arrow function with no callers
setup_pts3_export_const_no_refs() {
    mkdir -p src
    cat > src/utils.ts <<'EOF'
export const computeStuff = (x: number) => x * 2;
EOF
}
run_scenario "P-TS3: export const no references" 0 'computeStuff.*TypeScript/JavaScript' '' setup_pts3_export_const_no_refs

# Negative: exported function with caller in src/
setup_nts1_properly_wired() {
    mkdir -p src
    cat > src/lib.ts <<'EOF'
export function tsCompute(): number {
    return 1;
}
EOF
    cat > src/main.ts <<'EOF'
import { tsCompute } from './lib';
console.log(tsCompute());
EOF
}
run_scenario "N-TS1: export function with src/ caller" 0 '' 'TypeScript/JavaScript' setup_nts1_properly_wired

# Negative: NestJS @Controller decorator
setup_nts2_nestjs_controller() {
    mkdir -p src
    cat > src/users.controller.ts <<'EOF'
import { Controller, Get } from '@nestjs/common';

@Controller('users')
export class UsersController {
    @Get()
    findAll() {
        return [];
    }
}
EOF
}
run_scenario "N-TS2: NestJS @Controller" 0 '' 'UsersController.*TypeScript/JavaScript' setup_nts2_nestjs_controller

# Negative: Next.js page file (path-glob skip)
setup_nts3_nextjs_page() {
    mkdir -p pages
    cat > pages/about.tsx <<'EOF'
export default function AboutPage() {
    return <div>About</div>;
}
EOF
}
run_scenario "N-TS3: Next.js pages/ default export" 0 '' 'AboutPage.*TypeScript/JavaScript' setup_nts3_nextjs_page

# Negative: barrel re-export from index.ts (public API)
setup_nts4_barrel_export() {
    mkdir -p src
    cat > src/internal.ts <<'EOF'
export function libraryApi(): string {
    return "public";
}
EOF
    cat > src/index.ts <<'EOF'
export { libraryApi } from './internal';
EOF
}
run_scenario "N-TS4: index.ts barrel re-export" 0 '' 'libraryApi.*TypeScript/JavaScript' setup_nts4_barrel_export

# Negative: registry pattern with TS const dict
setup_nts5_registry_pattern() {
    mkdir -p src
    cat > src/dispatch.ts <<'EOF'
export function tsFooHandler(): string {
    return "handled";
}

const HANDLERS = {"foo": tsFooHandler};
EOF
}
run_scenario "N-TS5: TS HANDLERS registry pattern" 0 '' 'tsFooHandler.*TypeScript/JavaScript' setup_nts5_registry_pattern

# Negative: private _underscore prefix (always ignored)
setup_nts6_private_prefix() {
    mkdir -p src
    cat > src/internal.ts <<'EOF'
export function _internalTsHelper(): void {}
EOF
}
run_scenario "N-TS6: _private TS function ignored" 0 '' '_internalTsHelper' setup_nts6_private_prefix

# Negative: export default class with caller in another file
setup_nts7_default_export_used() {
    mkdir -p src
    cat > src/widget.ts <<'EOF'
export default class TsWidget {
    render(): string { return "widget"; }
}
EOF
    cat > src/main.ts <<'EOF'
import TsWidget from './widget';
const w = new TsWidget();
console.log(w.render());
EOF
}
run_scenario "N-TS7: export default class with import" 0 '' 'TsWidget.*TypeScript/JavaScript' setup_nts7_default_export_used

# Edge: no TS/JS files in diff
setup_ets1_no_ts_files() {
    echo "console.log('rust file');" > src.rs
}
run_scenario "E-TS1: no TS/JS diff" 0 '' 'TypeScript/JavaScript' setup_ets1_no_ts_files

# Edge: anonymous default export (no named symbol to extract)
setup_ets2_anonymous_default() {
    mkdir -p src
    cat > src/anon.ts <<'EOF'
export default function () {
    return "anonymous";
}
EOF
}
run_scenario "E-TS2: anonymous default export ignored" 0 '' 'TypeScript/JavaScript' setup_ets2_anonymous_default

# ========== Summary ==========

log ""
log "----------"
log "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    log ""
    log "Failures:"
    for f in "${FAILURES[@]}"; do
        log "  $f"
    done
    exit 1
fi
exit 0
