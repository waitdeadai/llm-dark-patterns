# tests/stress — adversarial fixture suite for the hook bundle

168 fixtures covering 10 hooks with positive triggers, false-positive guards,
and edge cases. Every fixture's expected exit code is verified by
`tests/stress/run.sh` and reported in `STRESS-REPORT.md`.

## Layout

```
tests/stress/
  <hook>/
    positive/   # fixture should BLOCK     -> expect exit 2
    negative/   # fixture should NOT block -> expect exit 0
    edge/       # boundary cases           -> expect exit 0 unless overridden
```

## Per-fixture override

A sibling file with the same basename and `.expected` extension holds an
integer exit code that overrides the category default.

```
tests/stress/no-vibes/edge/05-unicode-emoji-positive.json      # fixture
tests/stress/no-vibes/edge/05-unicode-emoji-positive.expected  # contents: 2
```

## Running locally

```bash
bash tests/stress/run.sh                  # full run
bash tests/stress/run.sh --quiet          # only summary + failures
bash tests/stress/run.sh --hook no-vibes  # one hook
```

The runner prints a per-fixture verdict and writes `STRESS-REPORT.md`.
Exit code is `1` if any fixture fails, `0` otherwise.

## Adding a new fixture

The fastest path is to add the entry to `_gen_fixtures.py` and re-run it:

```bash
python3 tests/stress/_gen_fixtures.py
```

The generator is idempotent and overwrites existing fixtures of the same
name. JSON fixtures are committed to the repo so reviewers can inspect them
without running the generator.

You may also write a fixture by hand — the only requirement is that the
file is valid JSON (or that the test category accepts malformed JSON, as the
`edge/` category does for several hooks).

## What the suite verified

The first stress run caught three real defects:

1. **`tests/stress/run.sh`** — `|| true` after a captured exit-code
   assignment masked every hook's true status. Fixed by removing the
   suppression and capturing `$?` directly.
2. **`hooks/no-sycophancy.sh`** — the praise-tail character class
   `[!.,—–-]` did not match em-dash or en-dash because grep `-E` does not
   treat multibyte UTF-8 inside `[...]` as a single character. Fixed by
   replacing the bracket class with explicit alternation
   `(!|\.|,|—|–|-)`.
3. **`hooks/no-cliffhanger.sh`** — the optional capture group `d like ` did
   not match `'d like` (apostrophe-d). Fixed by tolerating the apostrophe.

Each fix is reflected in the hook file and verified by the corresponding
positive fixture.

## Contract

The stress suite is the deterministic guard for hook behavior:

- Every hook ships with at least seven positive fixtures and five negative
  fixtures.
- Every hook ships with at least one empty-message and one malformed-JSON
  edge fixture.
- A hook regex change must keep the existing fixtures passing or update the
  fixtures (with rationale in the commit message).
- A new pattern in a hook should ship with at least one positive and one
  negative fixture in the same PR.
