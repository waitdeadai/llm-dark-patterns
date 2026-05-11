# LLM Dark Patterns Hooks

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

> A suite of single-purpose Claude Code Stop hooks that suppress LLM dark-pattern defaults — sycophancy, paternalism, false-success, permission-loops, training-cutoff confidence — at the textual boundary, so power-user operators can actually work.

This repo is the **umbrella** for a series of small bash hooks. Each hook is a separate repository, each catches one specific dark pattern, each follows the same architecture: out-of-band textual enforcement at `Stop` / `SubagentStop`. The judge is bash, not another LLM call. The model can't argue with grep.

## Why this exists

LLM "dark patterns" is now an academically-recognized category:

- **DarkBench** ([emergentmind summary](https://www.emergentmind.com/topics/darkbench)) — 660 prompts across 6 dark-pattern categories. **48% of LLM conversations trigger at least one dark pattern.**
- **AAAI 2026** ([Lighting Up or Dimming Down? Exploring Dark Patterns of LLMs in Co-Creativity](https://arxiv.org/html/2604.04735v1)) — identifies 5 patterns: sycophancy, tone policing, moralizing, loop of death, anchoring. **Sycophancy at 91.7% prevalence.**
- **IEEE S&P 2026** ([Investigating the Impact of Dark Patterns on LLM-Based Web Agents](https://arxiv.org/html/2510.18113)) — agents susceptible 41% of the time to a single dark pattern.
- **CHI 2026** ([The Siren Song of LLMs](https://arxiv.org/html/2509.10830v3)) — user-perception study; users normalize dark patterns as "ordinary assistance."
- **DarkPatterns-LLM** ([Dec 2025 benchmark](https://arxiv.org/html/2512.22470v1)) — 7 harm categories.
- Sean Goedecke ([2024 essay](https://www.seangoedecke.com/ai-sycophancy/)) — *"Sycophancy is the first LLM dark pattern."* Naming convention now widespread.
- Anthropic's own [Constitution](https://www.anthropic.com/constitution) — *"various forms of paternalism and moralizing are disrespectful."*

The category is real. The academic side measures and benchmarks. The tooling side — until now — has been mostly system-prompt calibrators ([FutureSpeakAI/anti-sycophancy](https://github.com/FutureSpeakAI/anti-sycophancy)) and in-context skills ([0xcjl/anti-sycophancy](https://github.com/0xcjl/anti-sycophancy)). Both live inside the model's reasoning loop. Both can be drifted past on long sessions. Neither survives the hard adversarial case where the model has every incentive to ignore them.

The **LLM Dark Patterns Hooks** suite is the out-of-band complement: bash judges that inspect the model's outgoing text and refuse to let dark-patterned closeouts through.

## The suite

Ten hooks live as of 2026-05-11, organized in three branches by mechanism:

- **Interaction-style** (6): catch *how* the model talks. `no-vibes`, `time-anchor`, `no-curfew`, `no-sycophancy`, `no-cliffhanger`, `honest-eta`.
- **Fact-fabrication** (3): catch *what* the model claims. `no-fake-recall`, `no-fake-stats`, `no-fake-cite`.
- **Continuity** (1): counter context loss rather than block dishonest output. `no-amnesia`.

Each is its own repo, single bash file (or bash + python3 for engine-heavier hooks), Apache-2.0, drop-in via `.claude/settings.json`, with reproducible-test receipts.

> **New: see [METHODOLOGY.md](METHODOLOGY.md)** for the harness-engineering playbook used to discover and ship every hook in the suite. Lift it, apply it to other LLM-default failure modes, and ship more hooks.

| Hook | Dark pattern | Mechanism | Repo |
|---|---|---|---|
| **no-vibes** | confidence theater (claims of completion without evidence) | block positive-closeout vocabulary lacking same-message evidence | [waitdeadai/no-vibes](https://github.com/waitdeadai/no-vibes) |
| **time-anchor** | training-cutoff confidence (stale knowledge presented as current) | inject local system clock at SessionStart + UserPromptSubmit | [waitdeadai/time-anchor](https://github.com/waitdeadai/time-anchor) |
| **no-curfew** | unsolicited rest/wellness paternalism | block paternalism vocabulary at turn-end with allow-clause for operator-requested rest content | [waitdeadai/no-curfew](https://github.com/waitdeadai/no-curfew) |
| **no-sycophancy** | praise-spam at turn-open | inspect first 240 chars; block validation theater | [waitdeadai/no-sycophancy](https://github.com/waitdeadai/no-sycophancy) |
| **no-cliffhanger** | dangling permission-loop endings | inspect last 320 chars; block "want me to continue?" with allow-clauses for partial-status and explicit choice | [waitdeadai/no-cliffhanger](https://github.com/waitdeadai/no-cliffhanger) |
| **honest-eta** | vibe time estimates + linear-scaling parallelism claims | block time-estimate vocabulary lacking Agent-Native Estimate shape or hedge range; always block linear-scaling | [waitdeadai/honest-eta](https://github.com/waitdeadai/honest-eta) |
| **no-fake-recall** | false-memory recall ("as we discussed earlier" without quoted prior content) | block recall vocabulary unless message contains a markdown blockquote or 30+ char inline quote | [waitdeadai/no-fake-recall](https://github.com/waitdeadai/no-fake-recall) |
| **no-fake-stats** | fabricated percentages, dollar amounts, large counts without source | block stat patterns unless message contains URL / "according to <Proper Noun>" / "(YYYY)" / strong neutral hedge | [waitdeadai/no-fake-stats](https://github.com/waitdeadai/no-fake-stats) |
| **no-fake-cite** | citation patterns ("Smith et al., 2023", "[1]", "doi:") without verifiable URL | block citation patterns unless message contains a `https://` URL | [waitdeadai/no-fake-cite](https://github.com/waitdeadai/no-fake-cite) |
| **no-amnesia** | context loss after auto-compaction | snapshot working state on Stop / PreCompact / PostCompact, rehydrate on SessionStart | [waitdeadai/no-amnesia](https://github.com/waitdeadai/no-amnesia) |

## Architecture (the pattern that generalizes)

Every hook in the suite follows the same 4-step design:

1. **Pick a failure mode that has a textual signature.** Not "model is wrong" (no signature). Something like "claims success without evidence" or "opens with praise-spam" — these have distinct vocabularies.
2. **Define the signature precisely.** Two regex sets: the *bad* pattern, and the *redemption* (or *allow*) pattern. Bad without redemption → trigger.
3. **Wire a non-LLM judge** at a Claude Code hook event. Bash. Python. Anything that isn't another LLM call. The judge is not the same kind of thing as the actor.
4. **Block + repair-template.** A bare block stalls. A block + the literal compliant shape lets the model copy the template on the next turn. The repair-template *teaches*; the block alone just punishes.

This pattern composes. If you find a sixth dark pattern with a clean textual signature, write `no-X.sh` in 50–100 lines of bash and ship it as a sister repo. If you publish it under the same conventions (Apache-2.0, single file, `RECEIPTS.md` with reproducible fixtures, sister-tools cross-link block), open a PR adding it to the table above.

## Install (all five hooks, ~2 minutes)

```bash
mkdir -p .claude/hooks
# Single-file hooks
for hook in no-vibes time-anchor no-curfew no-sycophancy no-cliffhanger honest-eta no-fake-recall no-fake-stats no-fake-cite; do
  curl -fsSL "https://raw.githubusercontent.com/waitdeadai/${hook}/main/${hook}.sh" \
    -o ".claude/hooks/${hook}.sh"
  chmod +x ".claude/hooks/${hook}.sh"
done
# no-amnesia is a 5-file bundle (state engine + 4 event wrappers)
for f in state.sh state-stop.sh state-precompact.sh state-postcompact.sh state-sessionstart.sh; do
  curl -fsSL "https://raw.githubusercontent.com/waitdeadai/no-amnesia/main/hooks/${f}" \
    -o ".claude/hooks/${f}"
  chmod +x ".claude/hooks/${f}"
done
```

Then merge each repo's `settings.example.json` `hooks` block into your `.claude/settings.json`. Each hook is independent — you can install any subset.

Requires `jq` (and `python3` for `time-anchor`).

## Pitch / framing

The industry is optimizing LLMs for mass-market efficiency: faster, shorter, more agreeable, more cautious. That gradient runs **against** the power-user objective of correct results, deep verification, and operator agency. The Dark Patterns Hooks suite is the counter-position: small, surgical bash hooks that suppress the polite-cautious-efficient defaults at the textual boundary so the model can produce results instead of vibes.

The hooks are **conservative on purpose** — they would rather false-positive on legitimate prose that overlaps the dark-pattern vocabulary than false-negative on the actual dark pattern. The repair-template is the part that makes false-positives non-painful: when the hook fires on a legitimate use, the model sees the template and can repair into a closeout shape that satisfies the regex.

## Not a jailbreak

Important clarification: this suite **does not** suppress safety refusals, content-policy enforcement, or harm-prevention. The regexes are narrow to specific interaction-style defaults (sycophancy, paternalism, false-completion, permission-spam). If you want a tool that bypasses Claude's safety behaviors, this is not it.

## Parent harness

Hooks were extracted from the [minmaxing](https://github.com/waitdeadai/minmaxing) governance harness, which uses the same patterns at higher level (workflow contracts, spec-first, agent-native estimation, /agentfactory).

## Contributing

PRs welcome to:

- Add a new hook to the suite (must follow the conventions: single file, Apache-2.0, `RECEIPTS.md` with reproducible fixtures, allow-clause discipline).
- Improve a regex (must include a fixture in `RECEIPTS.md` covering the case).
- Document a dark pattern that needs a hook but doesn't yet have one (file an issue with the textual signature you'd want caught).

## License

Apache-2.0. Each individual hook repo also Apache-2.0.

---

> *Where in-context rules drift, out-of-band enforcement holds.*
