# Fixture-driven iteration for deterministic LLM dark-pattern hooks

A reusable methodology pattern, drawn from `llm-dark-patterns` development experience and intentionally scoped to be portable to other deterministic LLM-text-classification hooks (closeout boundary, tool-call boundary, prompt boundary).

## When this matters

Deterministic hooks that gate LLM output have a specific failure mode: the regex catches the cases the author thought of, ships, and then false-positives or false-negatives on cases the author didn't think of. The default iteration loop is *operator-narrowed*: a user reports the hook misfired or missed, the author patches that case, ships the patch, and waits for the next report.

The operator-narrowed loop is weak by construction. The operator's narrowings are post-hoc (only the cases that surfaced and were noticed) and incomplete (only the cases the operator considered consequential). Per `@beq00000`'s clean-state evidence in [`anthropics/claude-code#60226`](https://github.com/anthropics/claude-code/issues/60226#issuecomment-4491987732), the underlying failure mode the hooks are catching surfaces approximately seven times per session at baseline — and the operator catches the consequential ones, not all of them. A hook iterated only against operator reports is implicitly tuned for the salience filter of the operator, not the failure-mode distribution.

Fixture-driven iteration is the inverse: a hand-curated corpus of positive triggers, false-positive guards, and edge cases that runs as a regression gate. The regex must keep the existing fixtures passing or update them with rationale in the commit message. New regex patches ship with new fixtures in the same PR. The corpus is the contract the regex is responsible to, not the operator's incident stream.

## The pattern

Three structural commitments make the iteration loop work:

1. **Three-category fixture layout per hook**: positive (should block, exit 2), negative (should pass, exit 0), edge (boundary cases — empty input, malformed JSON, unicode, very long strings, multilingual variants). The negative category is the false-positive corpus and is the load-bearing piece — most operator-narrowed iteration neglects it.
2. **Per-fixture expected exit code, with override**. Default per category; a sibling `.expected` file overrides per fixture. The override exists for the "this looks like a negative but actually we want it to block" case (or vice versa).
3. **Commit-level provenance**. Every regex change either keeps the existing fixtures green or ships new fixtures in the same commit/PR. The git log becomes the audit trail for *what bug surfaced what fixture*. Searchable with `git log -S '<vocabulary that triggered the patch>'`.

## Layout (concrete)

```
tests/stress/
  <hook>/
    positive/    # fixture should BLOCK     -> expect exit 2
    negative/    # fixture should NOT block -> expect exit 0
    edge/        # boundary cases           -> expect exit 0 unless overridden
```

A per-fixture override is a sibling file with the same basename and `.expected` extension whose contents are the override exit code as an integer:

```
tests/stress/no-vibes/edge/05-unicode-emoji-positive.json      # fixture
tests/stress/no-vibes/edge/05-unicode-emoji-positive.expected  # contents: 2
```

## Runner contract

A single bash script verifies every fixture's expected exit code against the hook's actual exit code:

```bash
bash tests/stress/run.sh                  # full run
bash tests/stress/run.sh --quiet          # only summary + failures
bash tests/stress/run.sh --hook no-vibes  # one hook
```

The runner exits 1 if any fixture fails and 0 otherwise. CI gates on this exit code. The runner also writes a per-fixture verdict to `STRESS-REPORT.md` so reviewers can diff fixture outcomes across commits.

## Idempotent generator + committed JSON

For hooks with many fixtures, hand-authoring each JSON file is tedious. An idempotent Python generator (`_gen_fixtures.py`) overwrites existing fixtures of the same name and emits new ones from a single source-of-truth Python file. Reviewers can read the generator to understand the fixture distribution; they can read the JSON files to see exactly what the hook receives.

JSON files are committed even though the generator can recreate them. Two reasons: (a) reviewers should not have to run code to inspect a fixture; (b) the JSON files are what the runner actually feeds to the hook, so they are the authoritative payload shape.

## CI gate

Add the runner to the workflow that runs on every push and PR:

```yaml
# .github/workflows/test.yml (excerpt)
- name: Stress fixtures
  run: bash tests/stress/run.sh
- name: Upload stress report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: stress-report
    path: tests/stress/STRESS-REPORT.md
```

The artifact upload means a PR reviewer can pull the report from the workflow run and diff it against the report from `main` without re-running locally.

## Evidence trail: what the suite has caught

The methodology is described above. The auditable evidence that it works is in the commit history of `llm-dark-patterns`:

- **Commit [`6ead87c`](https://github.com/waitdeadai/llm-dark-patterns/commit/6ead87c)** — initial introduction (168 fixtures across 10 hooks). The first run caught three real defects: (1) the runner itself masked every hook's true status because `|| true` followed the captured exit-code assignment; (2) `no-sycophancy.sh` praise-tail bracket class `[!.,—–-]` did not match em-dash or en-dash because grep `-E` does not treat multibyte UTF-8 inside `[...]` as a single character; (3) `no-cliffhanger.sh` capture group `d like` did not match `'d like` (apostrophe-d). Each fix shipped with its corresponding positive fixture.
- **Commit [`641be4d`](https://github.com/waitdeadai/llm-dark-patterns/commit/641be4d)** — follow-on bypass closures (`fix(no-vibes): close evidence-proximity and negation-clause bypasses (#4, #5)`). Two distinct bypass families surfaced by the fixture corpus, both false-positive cases the original operator-narrowed corpus had not contained.
- Stress suite has grown from 168 fixtures at introduction to **337 fixtures currently** (live count in [`tests/stress/`](https://github.com/waitdeadai/llm-dark-patterns/tree/main/tests/stress)). Expansion has caught additional regressions on subsequent PRs; the regression-catch property is the load-bearing payoff.

The cost is real (roughly five to fifteen minutes of agent-native wall-clock per fixture once the layout exists, plus the false-positive corpus has to be hand-curated against the hook's verbose mode). The payoff is the regression-catch property: a regex change that breaks any of the 337 fixtures fails CI, and the commit-level provenance makes it auditable what the suite caught and when.

## Adapting to PreToolUse-style hooks

The pattern above is described for `Stop` / `SubagentStop` hooks where the payload is a single closing-message blob and the verdict is BLOCK or pass. PreToolUse-style hooks (gating before tool invocation) have a different payload shape and a richer verdict space; the methodology adapts with three changes.

### Different payload shape

The fixture is a JSON event from Claude Code's `PreToolUse` schema, carrying at minimum `tool_name`, `tool_input`, `cwd`, and `session_id`. The same three-category layout applies, but each fixture must be valid against the PreToolUse schema rather than the Stop schema. Negative fixtures are now wider in scope because `tool_input` is a per-tool union type (a `gh pr create` `tool_input` shape differs from a `Write` `tool_input` shape), so the false-positive corpus must cover at least the tool types the hook gates against.

### Richer verdict space

A PreToolUse hook can return:
- exit 2 (BLOCK)
- exit 0 silently (pass)
- exit 0 with stdout payload (pass with feedback or with a Socratic-narrowing reminder injected back to the agent)

The `.expected` override is no longer enough on its own to encode the verdict. Either widen the override format to encode both an exit code and an expected stdout substring, or add a second sibling file (e.g. `<basename>.expected-stdout`) that the runner asserts via grep on the captured stdout. For Socratic-narrowing hooks specifically, the *substance* of the injected message matters — a hook that injects the wrong reminder still exits 0 but fails the contract.

### Hash-cache state and the infinite-loop case

A Socratic-narrowing hook that injects the same reminder every turn will loop indefinitely if the agent re-emits the same artefact unchanged. The mitigation is a hash-cache keyed on `(tool_name, normalised(tool_input))` that suppresses re-injection within a window. The fixture corpus must cover the hash-cache contract:
- **first-call positive**: hook injects the reminder
- **same-call repeat**: hook does NOT re-inject (cache hit)
- **same-call after cache eviction**: hook re-injects (cache miss after TTL)
- **distinct-but-similar call**: hook injects (normalisation does not collapse genuinely-different inputs)

These cases require state across fixture invocations. The runner needs an explicit hash-cache-reset between fixtures and a separate hash-cache-stress fixture set that runs as a sequence with shared state. The runner contract above remains intact (exit 1 on any fail, exit 0 otherwise); the per-fixture verdict becomes a per-sequence verdict for the stateful cases.

## Honest cost-benefit

Fixture-driven iteration is worth the cost when:
- The hook is run frequently enough that false positives have meaningful operator cost (lost trust, ignored blocks, hook disabled).
- The hook covers a failure mode with enough surface variation that operator reports under-sample the distribution (per `@beq00000` clean-state evidence: the failure surface is wider than the consequential subset operators report).
- The regex is non-trivial (multi-clause, negation-aware, vocabulary-extensible) and prone to regressions when patched.
- The hook will be maintained by more than one person (the fixture corpus is the contract that survives author turnover).

It is over-engineering when:
- The hook is a one-off gate for a specific incident with no expected reuse.
- The regex is simple enough that the per-line patch and the test fit in one commit message.
- The hook is run only locally by the author and has no operator-side cost.

## Reuse and attribution

This methodology document is part of the `llm-dark-patterns` repository (Apache-2.0). The pattern is generic and freely reusable in any deterministic LLM-text-classification hook project. The repository hosts the canonical version; downstream adopters should link back rather than fork-and-drift, but forking and adapting under Apache-2.0 is also fine.

Prompt for writing this document came from the operator-to-operator discussion at [`anthropics/claude-code#60451`](https://github.com/anthropics/claude-code/issues/60451) and [yurukusa's recognition-without-arrest gist](https://gist.github.com/yurukusa/93123855318c022f21df92a7ac33c87b), specifically the observation that fixture-driven iteration with commit-level provenance is the methodological piece underrepresented in the operator-side dark-pattern-hook community work to date.
