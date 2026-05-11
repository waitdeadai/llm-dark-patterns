# Methodology — How to discover and ship LLM Dark Pattern Hooks

This document is the harness-engineering methodology behind the [LLM Dark Patterns Hooks](README.md) suite. It is meant to be lifted, applied to other LLM-default failure modes, and used as a template for shipping more hooks.

The methodology is simple enough that the same operator can ship a new hook in 1–3 hours without re-deriving any of the design.

---

## The thesis in one sentence

> **The model produces text. The text is the only output channel. Therefore the text is the audit surface.**

Every dark pattern this suite catches has a **textual signature** — a recognizable vocabulary the model uses when defaulting into the dishonest behavior. That signature is the leverage point: bash inspects it at the boundary, refuses dishonest closeouts, and returns a repair-template the model can copy on the next turn.

Two corollaries:

- **The judge is not the same kind of thing as the actor.** Bash judges; LLM acts. The model can't argue with grep. This is the same property that makes type systems beat "be careful with types" and CI beat "remember to run the tests."
- **Repair-template > bare block.** A bare block stalls the conversation. A block + the literal compliant shape lets the model self-correct in one turn.

If a failure mode does not have a textual signature, this methodology does not apply. Use a different defense (LLM-as-judge, runtime sandboxing, structural enforcement at the tool layer).

---

## The 4-step design pattern

Every hook in the suite was built using these four steps, in this order. Don't skip steps.

### Step 1 — Identify a failure mode with a clean textual signature

Two filters separate suite-eligible patterns from non-eligible ones:

- **Has a textual signature.** The dishonest behavior shows up in the assistant's outgoing text as a recognizable vocabulary, structure, or pattern. Examples in this suite: positive-closeout vocabulary, paternalism phrases, citation formatting, percentage patterns.
- **Has a redemption signal.** There is a recognizable form of *honest* output that should be allowed through. Examples: command backticks, blockquoted prior content, URLs alongside citations, structured estimate fields.

Failure modes that fail filter 1: silent math errors (the wrong answer looks indistinguishable from the right one). Drop these or use a different defense.

Failure modes that fail filter 2: complete refusal categories where allowing anything through is unsafe. Drop these.

### Step 2 — Define both signatures precisely

Write two regex sets:

- **The bad pattern** — vocabulary or structure that triggers the failure mode.
- **The redemption pattern** — vocabulary or structure that proves the failure mode is not present in this turn.

Trigger logic: bad **without** redemption → block. Bad **with** redemption → allow.

For some hooks, redemption is just absence of the trigger (e.g., `no-curfew` has a single allow-clause for operator-requested rest content, otherwise blocks any paternalism vocabulary). For others, redemption requires positive evidence in the same message (e.g., `no-fake-cite` requires a URL to accompany every citation pattern).

### Step 3 — Wire a non-LLM judge at a Claude Code hook event

Use bash + `jq` (or python3 for engine-heavier hooks). Wire to:

- **`Stop` and `SubagentStop`** for closeout-language hooks (the majority of this suite).
- **`UserPromptSubmit` and `SessionStart`** for context-injection hooks (`time-anchor`, `no-amnesia`).
- **`PreToolUse`, `PostToolUse`, `TaskCreated`, `TaskCompleted`** when the failure mode lives in tool-mediated work or subagent dispatch.

Read the JSON payload via `jq`. Extract the relevant field (`.last_assistant_message`, `.tool_input.command`, `.task.description`, etc.). Apply the regexes. Block via `echo "BLOCKED: ..." >&2; exit 2`.

### Step 4 — Repair-template that teaches

Every block must return a repair-guidance template via stderr. The template should:

- Name the failure mode in plain language.
- Cite the academic or industry source the pattern comes from (helps the model take the correction seriously and helps the operator understand why the hook fired).
- Include the **literal compliant shape** the next turn should use — verbatim text the model can copy.
- Document the allow-clause so the model can route its next turn through legitimate uses.

The template is the load-bearing part. Most hooks fail not because the regex is wrong but because the repair guidance is too vague to act on. If your hook fires repeatedly without the model self-correcting, the template needs more concrete shape, not stricter regex.

---

## Discovery process — how the suite's 10 hooks were found

This is the actual sequence used in May 2026 to ship the suite. Replicable for the next 10 hooks.

### Phase 1 — Notice the pattern in your own session

The first hook (`no-vibes`) was crystallized after watching Claude Opus 4.7 close turns dishonestly enough times that pattern-matching the vocabulary became cheaper than hoping for better prompts. **Personal pain-point telemetry is the strongest signal source.** If a model behavior annoys you twice in a session, it's probably a dark pattern with a textual signature.

### Phase 2 — Verify via published research

Before shipping, look up the academic literature for the failure mode. As of 2026 the field has matured enough that almost every interaction-style or fact-fabrication failure mode has at least one paper, benchmark, or industry writeup naming it. Examples used by this suite:

- Sycophancy → [Sean Goedecke's "first LLM dark pattern" essay](https://www.seangoedecke.com/ai-sycophancy/), [DarkBench](https://www.emergentmind.com/topics/darkbench), [AAAI 2026 co-creativity study at 91.7% prevalence](https://arxiv.org/html/2604.04735v1), [CHI 2026 user-perception paper](https://arxiv.org/html/2509.10830v3).
- Citation hallucination → [NeurIPS papers shipped with hallucinated refs (Fortune 2026)](https://fortune.com/2026/01/21/neurips-ai-conferences-research-papers-hallucinations/), [GhostCite analysis](https://arxiv.org/html/2602.06718), 19.9% baseline fabrication rate.
- Time-estimation failure → [Frontiers in AI 2026 on Story Points / LLM-mediated cost drivers](https://www.frontiersin.org/journals/artificial-intelligence/articles/10.3389/frai.2026.1772418/full), OpenAI Sep 2025 on training-rewarded bluffing.
- False memory → [ACM IUI 2025 false-memory induction paper](https://dl.acm.org/doi/10.1145/3708359.3712112).
- Paternalism → Anthropic's own [Constitution](https://www.anthropic.com/constitution) ("paternalism and moralizing are disrespectful").

The literature serves three purposes:

1. **Confirms the pattern is general**, not your local quirk.
2. **Provides language** for the README and repair-template.
3. **Anchors the legitimacy** of the hook to a real problem, which matters when pitching to engineers who would otherwise dismiss a "yet another agent governance utility."

### Phase 3 — Search GitHub and awesome-lists for prior tooling

Before shipping, check whether someone has already addressed the pattern with a hook. Two sources:

- `gh search repos "<pattern> in:name"` for direct name collisions.
- [`hesreallyhim/awesome-claude-code`](https://github.com/hesreallyhim/awesome-claude-code) and [`rohitg00/awesome-claude-code-toolkit`](https://github.com/rohitg00/awesome-claude-code-toolkit) for curated lists.

If existing tooling is found, decide: (a) different mechanism → ship as complement, document the differentiator clearly in README; (b) same mechanism, worse → ship as improved version with explicit comparison; (c) same mechanism, better → don't ship, link to it instead.

This suite's interaction-style branch shipped against extant prior art for sycophancy ([FutureSpeakAI/anti-sycophancy](https://github.com/FutureSpeakAI/anti-sycophancy), [0xcjl/anti-sycophancy](https://github.com/0xcjl/anti-sycophancy)). The differentiator was *out-of-band Stop hook* vs their *system-prompt calibrator* / *in-context skill*. Different mechanism, complementary, shipped.

### Phase 4 — Build the smallest sufficient hook

- Single bash file. ~50–150 lines.
- Only dependency: `jq` (`python3` is acceptable for engine-heavier hooks like `time-anchor` and `no-amnesia`).
- One trigger regex set, one redemption regex set.
- One repair-template.
- Three to six fixture tests in `RECEIPTS.md`, each with a literal expected output, runnable via one shell command.

Resist the urge to add "bonus" features. A hook that catches one pattern cleanly is worth more than a hook that catches three patterns ambiguously. If a second pattern is worth catching, ship a sister hook.

### Phase 5 — CI that verifies behavior, badge that displays it

Every hook in the suite has `.github/workflows/test.yml` that runs the fixture tests on push. The badge in README displays current CI status. This is the difference between "I built a thing" and "I shipped a tool I stand behind."

CI tests should mirror the fixtures in `RECEIPTS.md` exactly so an external reader can run the same tests locally and get the same results.

### Phase 6 — Cross-link and umbrella

Every hook in the suite cross-links to the others via a "Sister tools" section. The umbrella repo ([llm-dark-patterns](https://github.com/waitdeadai/llm-dark-patterns)) catalogs all hooks with a one-row description and links to each.

When a new hook ships, four updates happen in batch:

1. New repo's README cross-links to all existing siblings.
2. Each existing sibling's README adds the new hook to its sister list.
3. Umbrella table gets a new row.
4. Umbrella install loop adds the new hook name.

Total update time: ~15 minutes for 9 sibling repos.

---

## Suite topology

The 10 hooks live in three branches by mechanism:

### Interaction-style branch (6 hooks)

Catch *how* the model talks: closeout vocabulary, opening vocabulary, time-claim vocabulary, paternalism vocabulary.

| Hook | Failure mode |
|---|---|
| no-vibes | false-success closeouts (positive vocabulary without evidence) |
| time-anchor | training-cutoff confusion (no current-date awareness) |
| no-curfew | unsolicited rest/wellness paternalism |
| no-sycophancy | praise-spam at turn open |
| no-cliffhanger | dangling permission-loop endings |
| honest-eta | vibe time estimates + linear-scaling claims |

### Fact-fabrication branch (3 hooks)

Catch *what* the model claims: false-memory recall, fabricated stats, fake citations.

| Hook | Failure mode |
|---|---|
| no-fake-recall | "as we discussed earlier" without quoted prior content |
| no-fake-stats | precise percentages / dollar amounts / large counts without source |
| no-fake-cite | academic citation patterns without verifiable URL |

### Continuity branch (1 hook)

Counters context loss rather than blocking dishonest output.

| Hook | Failure mode |
|---|---|
| no-amnesia | context loss after auto-compaction; injects working state on SessionStart |

---

## How to ship a new hook (the 1-3 hour playbook)

Concrete checklist if you've identified a new dark pattern with a clean textual signature:

1. **Verify novelty.** `gh search repos "<keyword> in:name"`. Skim the first 10 hits. If the exact mechanism + scope already exists, route the impulse to a PR on the existing repo instead.
2. **Pick a name.** No-X for suppression hooks (`no-foo`), positive-form for injection hooks (`anchor-foo`). Check `gh repo view waitdeadai/<name>` is `Could not resolve` and `gh search repos "<name> in:name"` is empty or low-conflict.
3. **Scaffold from a template hook.** Copy `no-curfew` for a simple suppression hook, `time-anchor` for an injection hook, `no-amnesia` for a multi-event continuity hook. Replace the regex, repair-template, and event matchers.
4. **Write 3-6 fixtures into `RECEIPTS.md`.** Each fixture is a JSON payload + an expected exit code + an expected stderr message snippet. Run them locally; verify the hook behaves as documented.
5. **Write the CI workflow** mirroring those exact fixtures. Push and confirm CI green before publishing the README's badge.
6. **Write the README** with the academic backing in a "Why this exists" section, the regex behavior in "What gets blocked / What stays allowed", install instructions, and the Sister tools cross-link to the umbrella.
7. **Push, create v0.1.0 release, add topics, update umbrella table, update each sister README.** This is mechanical and takes ~15 min.

Average time from identification to public release: 1–3 hours per hook for the operator who built this suite. The first hook took longer because the playbook was being invented; once the playbook is in place each subsequent hook is faster.

---

## Adversarial Discovery via Impossible Tasks

The discovery process in Phase 1 (*"notice the pattern in your own session"*) is the first half of how new patterns enter the suite. The systematic half is **adversarial probing via impossible tasks** — give the model a task it structurally cannot do, observe the dishonest pattern it defaults to instead of abstaining, and add the pattern to the suite.

This methodology has substantial 2026 academic backing:

- **AbstentionBench** ([arXiv 2506.09038](https://arxiv.org/pdf/2506.09038)) shows that *"abstention is an unsolved problem where scaling models is of little use"* across 5 categories of unanswerable question (unknown answers, underspecification, false premises, subjective interpretations, outdated information).
- **Anthropic's [tracing-thoughts research](https://www.anthropic.com/research/tracing-thoughts-language-model)** confirms Claude *"sometimes makes up plausible-sounding steps to get where it wants to go"* — when the task is impossible, the model fabricates a chain of reasoning that ends at a confident guess instead of saying *"I don't know"*.
- **CoT-Is-Not-Explainability** ([Oxford 2025](https://aigi.ox.ac.uk/wp-content/uploads/2025/07/Cot_Is_Not_Explainability.pdf)) and [Turpin et al. on unfaithful CoT](https://openreview.net/forum?id=bzs4uPLXvi) show the reasoning chain doesn't reflect the actual decision; accuracy drops by 36% on 13 tasks when models rationalize biased answers.
- **Self-knowledge limits** ([Line of Duty](https://arxiv.org/abs/2503.11256)): "GPT-4o and Mistral Large are not sure of their own capabilities more than 80% of the time."
- **Strawberry tokenization** ([2412.18626](https://arxiv.org/html/2412.18626v1)): models can spell a word, miscount its letters, and explain themselves confidently *"without detecting the inconsistency."*

The literature has the *measurement* side mature (HalluLens, AbstainQA, TruthfulQA, AbstentionBench). What's missing is the *enforcement* side at the Stop-hook layer — that's the gap this suite fills.

### The discovery-engine companion repo

The suite has a dedicated discovery catalog at [`waitdeadai/impossible-tasks`](https://github.com/waitdeadai/impossible-tasks):

- [`TASK_CLASSES.md`](https://github.com/waitdeadai/impossible-tasks/blob/main/TASK_CLASSES.md) — 30 impossible-task classes grouped by failure locus (no tool, no knowledge, no perception, no introspection, tokenization-bound, false-premise, memory loss).
- [`DARK_PATTERNS_REVEALED.md`](https://github.com/waitdeadai/impossible-tasks/blob/main/DARK_PATTERNS_REVEALED.md) — per-class mapping from task → dishonest default → existing or candidate hook.
- [`CANDIDATE_HOOKS.md`](https://github.com/waitdeadai/impossible-tasks/blob/main/CANDIDATE_HOOKS.md) — prioritized buildable list with difficulty ratings (1-5) and false-positive risk per candidate.
- [`FIXTURES.md`](https://github.com/waitdeadai/impossible-tasks/blob/main/FIXTURES.md) — paste-and-observe prompts that surface each pattern in seconds.

### Discovery loop

The full discovery loop combines Phase 1 (passive observation) and Phase 7 (active probing):

```text
Pain-point observation  ─┐
                         ├─►  Pattern named  ─►  Verified via published research  ─►  Hook shipped
Adversarial probe (this) ─┘
```

Adversarial probing is the deterministic version of pain-point observation. If a class of impossible tasks reliably produces the same dishonest pattern across 5+ fresh sessions, the pattern is real and worth shipping a hook against.

### How to apply it

1. Pick a failure locus from [`TASK_CLASSES.md`](https://github.com/waitdeadai/impossible-tasks/blob/main/TASK_CLASSES.md) (or invent a new one).
2. Write 3-5 fixture prompts that all live in that locus.
3. Run them against a fresh Claude Code session. Note the dishonest phrasing each time.
4. If a recognizable phrasing appears across ≥3 fixtures, you have a textual signature for a candidate hook.
5. Apply the [4-step design pattern](#the-4-step-design-pattern) to ship the hook.
6. PR back to `impossible-tasks` updating the coverage tables.

The goal is not to catalog every impossible task — it's to systematically convert *kinds* of impossibility into shipped hooks. The current ratio is 11 of 30 classes covered; the next wave (`no-fake-perception`, `no-fake-cap`, `no-fake-future`) takes it to ~14 of 30.

---

## When this methodology does not apply

Three categories of LLM failure mode that **don't fit** this suite's mechanism. Different defense required:

- **Tool-mediated harm.** Model invokes a destructive tool. Use a `PreToolUse` blocker (the existing `no-vibes` hook covers destructive Bash patterns this way) or a structural sandbox.
- **State-dependent dishonesty.** Failure mode requires multi-turn comparison (e.g., persona drift, contradicting earlier turn). Hook events have limited prior-turn access; consider a separate state-tracking layer.
- **Subjective failure modes.** Refusals when help should have been given, moralizing, political bias. These need an LLM-as-judge or structured eval, not regex.

Ship those via a different framework. Don't force them into a Stop hook with a blunt regex — false-positive rate destroys the suite's signal.

---

## Citation

If you build a hook using this methodology, the suite would value a back-link in your README under "Methodology" or "Acknowledgments." Apache-2.0 doesn't require it; the courtesy compounds.

---

## License

Apache-2.0, like every hook in the suite.
