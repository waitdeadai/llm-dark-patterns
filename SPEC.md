# SPEC: no-wrap-up — block engagement-fishing closures at message end

## Problem Statement

The model frequently closes turns with engagement-fishing tails:
"Is there anything else I can help with?", "Let me know if you need
anything else", "Hope this helps!", "Feel free to reach out". Power
users find these annoying and disrespectful — the operator decides
when the conversation ends, not the model. Documented in DarkBench
as the **User Retention** category (Kran et al. 2025, ICLR 2025,
arXiv:2503.10728).

This pattern is distinct from `no-cliffhanger` (which catches "want
me to continue with X?" — re-asking permission for MORE work) because
wrap-up nudging fishes for closure or extension at session boundary,
not for permission to continue working. Different intent, different
repair template, different allow-clauses, different DarkBench
category mapping.

Live receipt of the pattern: in the same 2026-05-11 session that
produced this suite's Phase 1-5 work, the assistant closed two
consecutive turns with "¿Algo más antes de cerrar la sesión?" — a
canonical wrap-up nudge. The operator caught it in real time and
asked whether it warranted a hook. The deepresearch confirmed: yes,
DarkBench User Retention category, distinct from existing hooks,
documented community complaint pattern.

## Success Criteria (verifiable)

- [ ] `hooks/no-wrap-up.sh` exists, executable, syntax-valid bash.
- [ ] `hooks/hooks.json` includes `no-wrap-up` under both `Stop` and
  `SubagentStop` event arrays.
- [ ] `packs/locale/en.txt` includes new sections `[wrap_up_ending]`
  and `[wrap_up_allow]`.
- [ ] README.md "The suite" table has a `no-wrap-up` row.
- [ ] METHODOLOGY.md cites DarkBench User Retention as the academic
  backing for the new hook.
- [ ] Stress suite total grows from 205 to ~213 (+5-8 fixtures: at
  least 5 positive triggers, 2 negative non-triggers, 1 edge).
- [ ] `bash tests/stress/run.sh` returns exit 0 with all fixtures PASS.
- [ ] `bash tests/test-pack-loader.sh` returns 17/17 PASS (no loader
  regression).
- [ ] `_gen_fixtures.py` updated so the new fixtures survive
  regeneration.

## Scope

In:
- New hook `hooks/no-wrap-up.sh` (loads from packs, inline fallback).
- Two new pack sections in `packs/locale/en.txt`.
- `hooks/hooks.json` registration for Stop + SubagentStop.
- README.md row + METHODOLOGY.md citation entry.
- Stress fixtures (5+ positive, 2+ negative, 1+ edge).
- Single commit on `/tmp/dark-patterns-work/llm-dark-patterns` main.

Out:
- Spanish/Polish/German/French/Portuguese pack sections (deferred to
  per-locale community PRs; the new sections are English-only at
  ship time, same approach as the other recently-migrated hooks).
- Standalone `waitdeadai/no-wrap-up` repo (not warranted yet — only
  no-vibes has its own standalone repo because it was the highest-
  polish single hook for HN target).
- CI changes (existing test.yml will pick up the new fixtures via
  the existing stress job).

## Agent-Native Estimate

- Estimate type: agent-native wall-clock
- Critical path: SPEC -> hook script -> pack sections -> hooks.json ->
  README row -> METHODOLOGY entry -> stress fixtures -> _gen_fixtures.py ->
  verify (177/177) -> commit -> push
- Agent wall-clock: optimistic 20m / likely 35m / pessimistic 55m
- Agent-hours: ~35m
- Human touch time: 0 (operator authorized full execution)
- Calendar blockers: none
- Confidence: high (close analog `hooks/no-cliffhanger.sh`)

## Implementation Plan

### Task 1: Write `hooks/no-wrap-up.sh`
Definition of Done:
- [ ] Sources `lib/packs.sh` if available
- [ ] Loads `[wrap_up_ending]` and `[wrap_up_allow]` from active locale packs
- [ ] Inline English fallback for both sections
- [ ] Inspects last ~280 chars of message for trigger
- [ ] Allow-clause checks before trigger check
- [ ] Block with repair-template grounded in DarkBench User Retention
- [ ] Citation block in script header

### Task 2: Add pack sections
Definition of Done:
- [ ] `[wrap_up_ending]` with at least 10 regex alternatives
- [ ] `[wrap_up_allow]` with operator-asked-closure variants

### Task 3: Register in hooks.json
Definition of Done:
- [ ] `no-wrap-up` entry in `Stop` array
- [ ] `no-wrap-up` entry in `SubagentStop` array
- [ ] JSON validates with `jq -e .`

### Task 4: README + METHODOLOGY
Definition of Done:
- [ ] README "The suite" table row + count bumped from 10 to 11
- [ ] METHODOLOGY citation map gets DarkBench User Retention line

### Task 5: Stress fixtures
Definition of Done:
- [ ] At least 5 positive (engagement-fishing closures should BLOCK)
- [ ] At least 2 negative (legitimate closures or operator-asked closure should PASS)
- [ ] At least 1 edge (empty message, malformed JSON)
- [ ] Generator script (`_gen_fixtures.py`) updated

### Task 6: Verify + commit + push
Definition of Done:
- [ ] `bash tests/stress/run.sh` PASS
- [ ] `bash tests/test-pack-loader.sh` PASS
- [ ] Single commit, conventional title
- [ ] `git push origin main` succeeds

## Verification
- File exists -> Task 1 ls
- JSON valid -> Task 3 jq
- README updated -> Task 4 grep
- Stress green -> Task 6
- Cloud CI green -> post-push monitor

## Rollback Plan
1. `git revert <commit_hash>` from main
2. `git push origin main`
3. Hook removed; suite returns to 10 hooks. Standalone no-vibes is
   unaffected (this is umbrella-only).
