# tests/no-unreachable-symbol — bespoke smoke-test harness

## Why a separate test harness

The default stress runner at [`tests/stress/run.sh`](../stress/run.sh) feeds JSON Stop-event fixtures to each hook via stdin and asserts on the hook's exit code. That contract works for hooks whose signal source is the closing message text (`no-vibes`, `no-sycophancy`, `honest-eta`, etc.).

`no-unreachable-symbol` reads from **git state** — `git diff HEAD --unified=2 -- '*.py'` and `grep -r` over the codebase. The signal is the codebase, not the Stop payload. A JSON fixture cannot represent the git state the hook needs to inspect.

Per [`docs/methodology/fixture-driven-iteration.md`](../../docs/methodology/fixture-driven-iteration.md) (section "Hash-cache state and the infinite-loop case"), state-dependent hooks need a bespoke runner. This directory holds that runner.

## What the harness does

Each scenario in [`smoke.sh`](smoke.sh):

1. Creates a temp directory via `mktemp -d`
2. Runs `git init`, configures a test author identity, commits a baseline
3. Applies the scenario's setup function: writes Python files representing the target codebase + diff state, stages them so `git diff HEAD` picks them up
4. Runs the hook from the temp directory with `</dev/null` for stdin
5. Asserts on the hook's exit code AND on stderr matching/non-matching the expected advisory text
6. Cleans up the temp directory

## Coverage

12 scenarios across positive / negative / edge:

**Positive (hook should fire advisory):**
- P1: bare function with no callers
- P2: class with no instantiation
- P3: function only referenced from `tests/` directory

**Negative (hook should NOT fire):**
- N1: function with caller in `src/`
- N2: `@app.route` decorator (Flask-style)
- N3: `@router.get` decorator (FastAPI-style)
- N4: `@pytest.fixture` decorator
- N5: function listed in `__all__` (public API marker)
- N6: registry value form `HANDLERS = {"foo": foo_handler}`
- N7: private prefix `_internal_helper` (always ignored)

**Edge:**
- E1: no Python files in diff
- E2: dunder methods `__init__` / `__str__` (always ignored)

## Running the suite

```bash
bash tests/no-unreachable-symbol/smoke.sh           # full run
bash tests/no-unreachable-symbol/smoke.sh --quiet   # only summary + failures
```

Exit code `1` if any scenario fails; `0` otherwise.

## Known limitations (Slice 0)

- **Python only**. TypeScript/JS, Rust, Go are future slices.
- **Advisory mode by default**. Strict mode (exit 2) is opt-in via `LDP_UNREACHABLE_SYMBOL_BLOCK=1` and the operator must opt in deliberately.
- **No empirical baseline**. MAD is text-only; no public dataset of dead-code-vs-properly-wired diffs. Smoke suite is the contract instead.
- **Reference-permissive caller check**. Any text occurrence of the symbol name in non-test code counts as a reference (including comments). False-negative direction is intentional in advisory mode — a function the codebase knows by name is more likely wired than one with zero textual mentions.
- **No AST-level reachability**. v1 stays grep-based; AST-level pass is a future slice (Python `ast.parse`, TS via `ts-morph` or similar).

## Adding a new scenario

Edit `smoke.sh`:

1. Add a `setup_<name>()` function that, when called with `$PWD` set to a fresh temp git repo, writes Python files representing the desired codebase + diff state
2. Add a `run_scenario "name" <expected_exit> "<stderr_match_regex>" "<stderr_nomatch_regex>" setup_<name>` line in the scenarios section
3. Re-run `bash smoke.sh` and confirm the new scenario passes

The harness uses the hook's regular production path; no test-double env vars are required for the standard cases. The hook does expose `LDP_UNREACHABLE_SYMBOL_TEST_DIFF` and `LDP_UNREACHABLE_SYMBOL_TEST_REPO` for scenarios that want to inject a synthetic diff without going through git, but every Slice 0 scenario uses real git state.

## Attribution

Hook prompted by [@ianymu's sketch](https://github.com/anthropics/claude-code/issues/60451#issuecomment-4495901564) on `anthropics/claude-code#60451`. Design issue: [llm-dark-patterns#23](https://github.com/waitdeadai/llm-dark-patterns/issues/23). Companion runtime gate at the same Stop boundary with a different signal source: [@ianymu's `verify-before-stop`](https://github.com/ianymu/claude-verify-before-stop) (log-based).
