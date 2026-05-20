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
run_scenario "P1: bare function no callers" 0 'my_unused_helper.*zero callers' '' setup_p1_bare_helper

# Positive: new class with no instantiation
setup_p2_class_no_instance() {
    mkdir -p src
    echo "class OrphanHandler:" > src/handlers.py
    echo "    def do(self): pass" >> src/handlers.py
}
run_scenario "P2: class no instantiation" 0 'OrphanHandler.*zero callers' '' setup_p2_class_no_instance

# Positive: function only called from tests/
setup_p3_only_in_tests() {
    mkdir -p src tests
    echo "def test_only_helper():" > src/utils.py
    echo "    return 1" >> src/utils.py
    echo "from src.utils import test_only_helper" > tests/test_utils.py
    echo "def test_x():" >> tests/test_utils.py
    echo "    assert test_only_helper() == 1" >> tests/test_utils.py
}
run_scenario "P3: function only called in tests/" 0 'test_only_helper.*zero callers' '' setup_p3_only_in_tests

# Negative: function with caller in src/
setup_n1_properly_wired() {
    mkdir -p src
    echo "def compute():" > src/lib.py
    echo "    return 1" >> src/lib.py
    echo "from src.lib import compute" > src/main.py
    echo "print(compute())" >> src/main.py
}
run_scenario "N1: function with src/ caller" 0 '' 'zero callers' setup_n1_properly_wired

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
run_scenario "N2: @app.route decorator" 0 '' 'my_route.*zero callers' setup_n2_route_decorator

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
run_scenario "N3: @router.get FastAPI" 0 '' 'api_handler.*zero callers' setup_n3_fastapi_endpoint

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
run_scenario "N4: @pytest.fixture" 0 '' 'my_fixture.*zero callers' setup_n4_pytest_fixture

# Negative: function in __all__
setup_n5_in_all_list() {
    mkdir -p src
    cat > src/api.py <<'EOF'
__all__ = ["public_api"]

def public_api():
    return "for external use"
EOF
}
run_scenario "N5: function in __all__" 0 '' 'public_api.*zero callers' setup_n5_in_all_list

# Negative: registry pattern HANDLERS["foo"] = foo_handler
setup_n6_registry_pattern() {
    mkdir -p src
    cat > src/dispatch.py <<'EOF'
def foo_handler():
    return "handled"

HANDLERS = {"foo": foo_handler}
EOF
}
run_scenario "N6: HANDLERS registry pattern" 0 '' 'foo_handler.*zero callers' setup_n6_registry_pattern

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
run_scenario "E1: no Python diff" 0 '' 'zero callers' setup_e1_no_python

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
run_scenario "E2: dunder methods ignored" 0 '' '__init__.*zero callers' setup_e2_dunder

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
