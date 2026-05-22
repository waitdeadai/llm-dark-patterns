# LLM Dark Patterns Hooks

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![tests](https://github.com/waitdeadai/llm-dark-patterns/actions/workflows/test.yml/badge.svg)](https://github.com/waitdeadai/llm-dark-patterns/actions/workflows/test.yml)
[![stress fixtures](https://img.shields.io/badge/stress_fixtures-337%2F337_PASS-green)](tests/stress)
[![unit tests](https://img.shields.io/badge/loader_tests-17%2F17_PASS-green)](tests/test-pack-loader.sh)

> A suite of single-purpose Claude Code hooks that suppress LLM dark-pattern defaults — sycophancy, paternalism, false-success, permission-loops, training-cutoff confidence, and compaction amnesia — at the textual boundary, so power-user operators can actually work.

This repo is the **umbrella** for a series of small hook repos, umbrella-only
legacy hooks that still live here, and the research-grade closeout physics
engine in
[waitdeadai/agent-closeout-bench](https://github.com/waitdeadai/agent-closeout-bench).
Each public standalone hook remains separately installable. The
physics-backed lane uses one reproducible engine with per-category rule packs,
fixtures, and decision JSON.

That does not collapse every hook into one generic detector. Each hook maps to
its own category engine; the shared Rust binary is packaging for reproducible
hashing, safe regex compilation, fixture testing, telemetry discipline, and
paper-grade evaluation.

The shared architecture is out-of-band textual enforcement at Claude Code hook
boundaries. The judge is deterministic code, not another LLM call. That means
the model cannot modify the hook's code path from inside its closeout text; it
does not mean the system is impossible to bypass, misconfigure, or evade by
paraphrase.

## What's shipped (as of 2026-05-13)

| Phase | Surface | Status |
|---|---|---|
| Phase 1 — Locale loader + English pack | `lib/packs.sh`, `packs/locale/en.txt` | ✓ ships |
| Phase 2 — Spanish + Polish locale packs | `packs/locale/{es,pl}.txt` | ✓ ships |
| Phase 3 — Evidence binary allowlist (devops/k8s/cloud/database/system) | `packs/evidence/binaries.txt` (9 sections, 200+ binaries) | ✓ ships |
| Phase 4 — Destructive command surface packs (filesystem, container, git-protected, config-overwrite, cloud-prod, database, service) | `packs/destructive/*.txt` (7 surfaces, 56 patterns) | ✓ ships |
| Phase 5 — Bypass hardening (clause-local negation, evidence proximity + action-verb) | `hooks/no-vibes.sh` | ✓ ships |
| Phase 6 — Physics-backed closeout adapters | `agentcloseout-physics` v0.2, per-category rule packs, Claude Code wrappers, PreToolUse tamper guard | ✓ ships in AgentCloseoutBench |

Operators with a non-English session, a non-app-dev toolchain, or a load-bearing destructive surface (kubectl, terraform, redis FLUSHALL, force-push to main) can extend coverage **without forking** by dropping a `.txt` into `${XDG_CONFIG_HOME:-$HOME/.config}/llm-dark-patterns/packs/<subdir>/<name>.txt`. See [ROADMAP.md](ROADMAP.md) for the architecture spec.

## Why this exists

LLM "dark patterns" is now an academically-recognized category:

- **DarkBench** (Kran et al. 2025, ICLR 2025, [arXiv:2503.10728](https://arxiv.org/abs/2503.10728)) — 660 prompts across 6 dark-pattern categories. **48% of LLM conversations trigger at least one dark pattern.**
- **DarkBench+** (Liu et al. 2026, [AAAI 2026 main conference](https://ojs.aaai.org/index.php/AAAI/article/view/41103)) — extended benchmark testing **~40 mainstream LLMs** across **10 major categories and 24 subcategories**. First specialized evaluation dimensions for reasoning models. Bilingual (Chinese/English).
- **AAAI 2026 Spring Symposium** (Li, Qu, Chang 2026, [Lighting Up or Dimming Down?](https://arxiv.org/abs/2604.04735)) — co-creativity study identifying 5 patterns: sycophancy, tone policing, moralizing, loop of death, anchoring. **Sycophancy at 91.7% prevalence.**
- **IEEE S&P 2026** ([Investigating the Impact of Dark Patterns on LLM-Based Web Agents](https://arxiv.org/html/2510.18113)) — agents susceptible 41% of the time to a single dark pattern.
- **CHI 2026** ([The Siren Song of LLMs](https://arxiv.org/html/2509.10830v3)) — user-perception study; users normalize dark patterns as "ordinary assistance."
- **DarkPatterns-LLM** ([Dec 2025 benchmark](https://arxiv.org/html/2512.22470v1)) — 7 harm categories.
- **MAST — Multi-Agent System failure Taxonomy** (Cemri et al. 2025, NeurIPS 2025, [arXiv:2503.13657](https://arxiv.org/abs/2503.13657), [repo](https://github.com/multi-agent-systems-failure-taxonomy/MAST)) — **14 failure modes in 3 categories**: specification & system design (41.8% of observed failures), inter-agent misalignment (36.9%), task verification & termination (21.3%). Built on 1600+ annotated traces across 7 MAS frameworks (AG2, AppWorld, HyperAgent, MagenticOne_GAIA, OpenManus_GAIA, programdev, math_interventions, mmlu). MAD dataset published at [huggingface.co/datasets/mcemri/MAD](https://huggingface.co/datasets/mcemri/MAD). Production multi-agent systems fail at 41–86.7% rates.
- Sean Goedecke ([2024 essay](https://www.seangoedecke.com/ai-sycophancy/)) — *"Sycophancy is the first LLM dark pattern."* Naming convention now widespread.
- Anthropic's own [Constitution](https://www.anthropic.com/constitution) — *"various forms of paternalism and moralizing are disrespectful."*

The category is real. The academic side measures and benchmarks. The tooling side — until now — has been mostly system-prompt calibrators ([FutureSpeakAI/anti-sycophancy](https://github.com/FutureSpeakAI/anti-sycophancy)) and in-context skills ([0xcjl/anti-sycophancy](https://github.com/0xcjl/anti-sycophancy)). Both live inside the model's reasoning loop. Both can be drifted past on long sessions. Neither survives the hard adversarial case where the model has every incentive to ignore them.

The **LLM Dark Patterns Hooks** suite is the out-of-band complement: deterministic judges that inspect the model's outgoing text and refuse to let dark-patterned closeouts through.

### Field reports — what this looks like to real users

Two power-users have independently filed substantive issues against `anthropics/claude-code` describing the failure modes this suite catches:

- **Patti** ([anthropics/claude-code#45502](https://github.com/anthropics/claude-code/issues/45502), Apr 2026) — 200+ Claude Code sessions, US tax work under IRS deadline. *"Green checkmarks with nothing behind them."* RECONCILED status with blank proof columns. **36 PayPal transactions silently deleted by a post-compaction model.** Premature closeout at 17% context, "shall we wrap up", "goodnight" at 8 AM. The framing — *"the trust is in the evidence. The relationship is why we bother"* — is the design principle this suite operationalizes.
- **Sara** ([supplemental report on anthropics/claude-code#45502](https://github.com/anthropics/claude-code/issues/45502#issuecomment-4412107642), May 2026) — quantitative corpus over ~96 Claude Code sessions + 119 claude.ai exports. **1 disagreement in 96 sessions.** Refusal-to-disagree as substrate, not surface. claude.ai uses "profound" about the user 6 times; the user uses "profound" 0 times. Three months of CLAUDE.md rules suppressed certain words but not the disposition.
- **beq00000** ([clean-state evidence on anthropics/claude-code#60226](https://github.com/anthropics/claude-code/issues/60226#issuecomment-4491987732), May 2026) — *"Seven instances of recognition-without-arrest in a non-drifted session, all caught externally."* Single working day, low-stakes decisions, no operator-identified register drift. **"The pattern is the default mode, not the drift mode."** Six of seven caught by the operator (three via Socratic-narrowing prompts that re-introduce the gradient on collapsed decisions); one caught by tooling. Background base rate the suite's deterministic gates are catching a fraction of.

See pinned issue [#6 — Field reports](https://github.com/waitdeadai/llm-dark-patterns/issues/6) for the per-finding mapping to specific hooks. Honest scope: this catches the textual signature, not the underlying disposition. The training-level fix Patti is asking for still belongs to Anthropic.

### Mapping to MAST (Multi-Agent System failure Taxonomy)

The MAST taxonomy (Cemri et al., NeurIPS 2025) is the canonical peer-reviewed catalogue of multi-agent failure modes. 13 of the 28 detector hooks in this suite conceptually map to 8 of MAST's 14 modes. **Empirical evaluation against the MAD dataset has now been run** — full results at [`evaluation/MAST-RESULTS.md`](evaluation/MAST-RESULTS.md). The mapping table is split into empirically-validated coverage and conceptual-only mapping below.

#### Empirically-validated coverage (F1 > 0 measured vs MAD)

| Hook | MAST mode | LLM-judge full (n=954) | Human-labelled (n=19) |
|---|---|---|---|
| `no-vibes` / `evidence_claims` | 3.3 No or Incorrect Verification | F1 **0.308** (P 0.226 R 0.486) | F1 **0.815** (P 0.733 R 0.917) |
| `honest-eta` | 2.6 Action-Reasoning Mismatch | F1 0.230 (P 0.466 R 0.153) | 0 — no positives in subset |
| `no-wrap-up` | 3.1 Premature Termination | F1 0.022 (P 0.167 R 0.012) | 0 — no positives in subset |
| `no-phantom-tool-call` | 2.6 Action-Reasoning Mismatch | F1 0.005 (P 1.000 R 0.003) | 0 — no positives in subset |

Read: **`no-vibes` is the strong multi-agent catch** — F1 0.815 on human-labelled traces against MAST's highest-prevalence mode (3.3). `honest-eta` and `no-phantom-tool-call` are high-precision low-recall tools (when they fire they're usually right; they just don't fire often on trajectory text). `no-wrap-up` fires rarely and is mostly noise.

#### Conceptually mapped, no measured signal yet

The following 9 hooks conceptually target their MAST mode but did not produce measurable F1 at the trace-level baseline against MAD. Reasons documented in [`evaluation/MAST-RESULTS.md`](evaluation/MAST-RESULTS.md) §"Honest findings":

| Hook | Conceptually targets | Why no signal at trace-level baseline |
|---|---|---|
| `no-ownership-violation` (DOCUMENTED-LIMITED) | 1.2 Disobey Role Specification | Bash-canonical TaskCompleted event handler; Rust scan path passes by design |
| `no-handoff-loop` (DOCUMENTED-LIMITED) | 1.3 Step Repetition, 1.5 Unaware of Termination Conditions | Same — TaskCreated event handler |
| `no-fake-recall` | 1.4 Loss of Conversation History | Vocabulary tuned for chat-reply recall claims; trajectory text uses different scaffolding |
| `no-cliffhanger` | 1.5 Unaware of Termination Conditions, 3.1 Premature Termination | `zone: tail` (last 520 chars) is the trajectory tail, not a closeout sentence |
| `no-aggregator-hallucination`, `no-fake-stats` | 2.6 Action-Reasoning Mismatch | Tuned for supervisor closeouts; synthesis claim buried in trajectory chatter |
| `no-cherry-pick-rollup`, `no-silent-worker-success`, `no-sandbagging-disguise` | 3.1 / 3.2 Verification failures | Calibrated for supervisor reports, not multi-turn collaboration text |

The methodology gap is structural: hooks are tuned for individual Claude Code closeout messages; MAD's text is full multi-agent trajectory. Per-message scanning is the planned next experiment ([`MAST-RESULTS.md` §"Next steps"](evaluation/MAST-RESULTS.md)).

#### MAST adjacency (no direct mode mapping)

| Hook | Relationship to MAST |
|---|---|
| `no-credential-leak-in-handoff` | MAST commentary cites inter-agent privacy leakage as a failure surface but does not number a privacy mode in the 14-mode taxonomy |

#### Outside MAST scope (by design)

What MAST does not cover (single-agent UX / style dark patterns): `no-sycophancy`, `no-curfew`, `no-emoji-spam`, `no-tldr-bait`, `no-disclaimer-spam`, `no-ai-tells`, `no-meta-commentary`, `no-prompt-restate`, `no-roleplay-drift`. Those map to DarkBench / DarkBench+ / DarkPatterns-LLM instead — see the original DarkBench eval in [`evaluation/RESULTS.md`](evaluation/RESULTS.md).

Also outside MAD's text-only scope but conceptually a Stage 3 (non-gating) failure at the code boundary: **`no-unreachable-symbol`** — advisory-mode static-analysis hook that flags new public symbols with zero references under exclusion-aware grep (decorator-wired, `__all__` / barrel-export, registry-pattern, private-prefix, and framework-path exclusions built in). Slice 0 ships Python; Slice 1 ships TypeScript / JavaScript (NestJS/Angular decorators, Next.js `pages/`/`app/` path-glob skip, `index.ts` barrel-export public-API marker). Future slices: Rust + Go, AST-level reachability, project-level exclusion config. No F1 baseline because MAD is multi-agent text trajectories with no git-diff-vs-codebase ground truth; fixture-suite-as-contract instead per [`docs/methodology/fixture-driven-iteration.md`](docs/methodology/fixture-driven-iteration.md). Prompted by [@ianymu's sketch](https://github.com/anthropics/claude-code/issues/60451#issuecomment-4495901564) on `anthropics/claude-code#60451`; design issue at [#23](https://github.com/waitdeadai/llm-dark-patterns/issues/23). Smoke test harness at [`tests/no-unreachable-symbol/smoke.sh`](tests/no-unreachable-symbol/smoke.sh) covers 24 scenarios across Python + TS/JS (positive / negative / edge); state-dependent fixture model required a bespoke harness rather than the JSON-stdin stress runner.

## The suite

The active catalog is organized in six branches by mechanism:

- **Interaction-style** (8): catch *how* the model talks. `no-vibes`, `time-anchor`, `no-curfew`, `no-sycophancy`, `no-cliffhanger`, `no-wrap-up`, `no-tldr-bait`, `honest-eta`.
- **Fact-fabrication** (5): catch *what* the model claims. `no-fake-recall`, `no-fake-stats`, `no-fake-cite`, `no-phantom-tool-call`, `no-rollback-claim-without-evidence`.
- **Continuity** (1): counter context loss rather than block dishonest output. `no-amnesia`.
- **Multi-agent orchestration** (5): catch supervisor / +N-parallel-instance failure modes. `no-aggregator-hallucination`, `no-silent-worker-success`, `no-cherry-pick-rollup`, `no-ownership-violation`, `no-handoff-loop`.
- **Agentic safety** (3): catch credential leak, sandbagging disguise, approval-sneak surfaces. `no-credential-leak-in-handoff`, `no-sandbagging-disguise`, `no-approval-sneak`.
- **Power-user polish** (6): catch frontier-LLM annoyances power users hate. `no-emoji-spam`, `no-meta-commentary`, `no-prompt-restate`, `no-disclaimer-spam`, `no-ai-tells`, `no-roleplay-drift`.

The hooks now ship through three distribution lanes:

| Lane | What it means | Examples |
|---|---|---|
| Standalone repo | Public single-purpose repo with its own install docs, receipts/tests, and plugin metadata where available. | `no-vibes`, `time-anchor`, `no-curfew`, `no-sycophancy`, `no-cliffhanger`, `honest-eta`, `no-fake-recall`, `no-fake-stats`, `no-fake-cite`, `no-amnesia` |
| Umbrella-only legacy | Hook implementation exists in this umbrella bundle, but the public standalone repo has not been created or restored yet. Install from this repo's bundled plugin wiring. | `no-wrap-up`, `no-roleplay-drift`, multi-agent rollup hooks, approval/credential/phantom-tool/polish hooks |
| AgentCloseoutBench physics-backed | Reproducible engine adapters generated from `waitdeadai/agent-closeout-bench`; these are stricter rule-pack lanes, not copies of the standalone Bash scripts. | `no-vibes`, `no-wrap-up`, `no-cliffhanger`, `no-roleplay-drift`, `no-sycophancy` |

Standalone and umbrella-only hooks stay small and inspectable: single bash file
or bash plus python3 for engine-heavier hooks, Apache-2.0, drop-in via
`.claude/settings.json`, with reproducible-test receipts or fixtures.

> **See [METHODOLOGY.md](METHODOLOGY.md)** for the harness-engineering playbook used to discover and ship every hook in the suite. Now includes the *Adversarial Discovery via Impossible Tasks* methodology backed by AbstentionBench, Anthropic's tracing-thoughts research, and the CoT-faithfulness literature.

> **See [`waitdeadai/impossible-tasks`](https://github.com/waitdeadai/impossible-tasks)** — the discovery-engine companion repo. 30 impossible-task classes mapped to dishonest defaults mapped to existing or candidate hooks. 11 of 30 classes covered; 19 candidates remain, prioritized by difficulty.

| Hook | Dark pattern | Mechanism | Repo |
|---|---|---|---|
| **no-vibes** | confidence theater (claims of completion without evidence) | block positive-closeout vocabulary lacking same-message evidence | [waitdeadai/no-vibes](https://github.com/waitdeadai/no-vibes) |
| **time-anchor** | training-cutoff confidence (stale knowledge presented as current) | inject local system clock at SessionStart + UserPromptSubmit | [waitdeadai/time-anchor](https://github.com/waitdeadai/time-anchor) |
| **no-curfew** | unsolicited rest/wellness paternalism | block paternalism vocabulary at turn-end with allow-clause for operator-requested rest content | [waitdeadai/no-curfew](https://github.com/waitdeadai/no-curfew) |
| **no-sycophancy** | praise-spam at turn-open | inspect first 240 chars; block validation theater | [waitdeadai/no-sycophancy](https://github.com/waitdeadai/no-sycophancy) |
| **no-cliffhanger** | dangling permission-loop endings | inspect last 320 chars; block "want me to continue?" with allow-clauses for partial-status and explicit choice | [waitdeadai/no-cliffhanger](https://github.com/waitdeadai/no-cliffhanger) |
| **no-wrap-up** | engagement-fishing closures at message end (DarkBench User Retention) | inspect last 280 chars; block "anything else?" / "let me know if you need anything else" / "hope this helps!" + tail with allow-clause for operator-asked closure | [hooks/no-wrap-up.sh](hooks/no-wrap-up.sh) (umbrella-only legacy; standalone restoration planned) |
| **honest-eta** | vibe time estimates + linear-scaling parallelism claims | block time-estimate vocabulary lacking Agent-Native Estimate shape or hedge range; always block linear-scaling | [waitdeadai/honest-eta](https://github.com/waitdeadai/honest-eta) |
| **no-fake-recall** | false-memory recall ("as we discussed earlier" without quoted prior content) | block recall vocabulary unless message contains a markdown blockquote or 30+ char inline quote | [waitdeadai/no-fake-recall](https://github.com/waitdeadai/no-fake-recall) |
| **no-fake-stats** | fabricated percentages, dollar amounts, large counts without source | block stat patterns unless message contains URL / "according to <Proper Noun>" / "(YYYY)" / strong neutral hedge | [waitdeadai/no-fake-stats](https://github.com/waitdeadai/no-fake-stats) |
| **no-fake-cite** | citation patterns ("Smith et al., 2023", "[1]", "doi:") without verifiable URL | block citation patterns unless message contains a `https://` URL | [waitdeadai/no-fake-cite](https://github.com/waitdeadai/no-fake-cite) |
| **no-amnesia** | context loss after auto-compaction | snapshot working state on Stop / PreCompact / PostCompact, rehydrate on SessionStart | [waitdeadai/no-amnesia](https://github.com/waitdeadai/no-amnesia) |
| **no-aggregator-hallucination** | supervisor synthesizes "the workers' results" without citing any per-worker output (DarkBench-adjacent supervisor failure mode) | catch synthesis vocab; require per-worker enumeration / blockquote | [hooks/no-aggregator-hallucination.sh](hooks/no-aggregator-hallucination.sh) (umbrella-only) |
| **no-silent-worker-success** | "all N workers completed" rollup without per-worker exit codes (the dominant 2026 multi-agent failure mode per arXiv:2604.14228) | catch rollup vocab; require per-worker exit/status enumeration | [hooks/no-silent-worker-success.sh](hooks/no-silent-worker-success.sh) (umbrella-only) |
| **no-cherry-pick-rollup** | partial worker success ("4 of 5 succeeded") + positive closeout without explicitly handling the failed workers | require explicit handling of failed lanes (retry / blocked / reasoned-ignore) | [hooks/no-cherry-pick-rollup.sh](hooks/no-cherry-pick-rollup.sh) (umbrella-only) |
| **no-ownership-violation** | TaskCompleted edits files outside the agent's declared owned_paths/scope | parse payload; block out-of-scope file edits; fail-open without payload shape | [hooks/no-ownership-violation.sh](hooks/no-ownership-violation.sh) (umbrella-only) |
| **no-handoff-loop** | TaskCreated chain shows the same agent_id 3+ times in delegation history | parse payload; count agent_id occurrences; fail-open without history field | [hooks/no-handoff-loop.sh](hooks/no-handoff-loop.sh) (umbrella-only) |
| **no-credential-leak-in-handoff** | task delegation or message contains plaintext credentials (sk-*, ghp_*, AWS keys, Bearer tokens, password=, api_key=) — AgentLeak benchmark surface | regex match against canonical credential shapes; fire on any match | [hooks/no-credential-leak-in-handoff.sh](hooks/no-credential-leak-in-handoff.sh) (umbrella-only) |
| **no-phantom-tool-call** | "I ran `tool` and got X" / "the `tool` returned X" without same-message structural output (Tool result: header, fenced block, exit_code field, blockquote) | catch tool-call claim vocab; require structural evidence markers | [hooks/no-phantom-tool-call.sh](hooks/no-phantom-tool-call.sh) (umbrella-only) |
| **no-sandbagging-disguise** | "tried but couldn't" / "gave it my best shot" without specific blocker, error, or exit code (Anthropic Claude Opus 4.6 sabotage report) | catch sandbag vocab; require specific blocker citation | [hooks/no-sandbagging-disguise.sh](hooks/no-sandbagging-disguise.sh) (umbrella-only) |
| **no-rollback-claim-without-evidence** | "I rolled back" / "reverted" / "undid" without same-message rollback command | catch rollback claim; require git revert / kubectl undo / terraform / helm rollback evidence | [hooks/no-rollback-claim-without-evidence.sh](hooks/no-rollback-claim-without-evidence.sh) (umbrella-only) |
| **no-approval-sneak** | Edit/Write to operator-defined sensitive paths (.env*, secrets/, .kube/, terraform/state/, .ssh/, .gnupg/, prod/) without prior approval token | path match against pack-defined sensitive surfaces; block unless `tool_input.approval=approved` | [hooks/no-approval-sneak.sh](hooks/no-approval-sneak.sh) (umbrella-only) |
| **no-emoji-spam** | message has more than N emoji codepoints (default 3; configurable via `LLM_DARK_PATTERNS_EMOJI_THRESHOLD`) | python codepoint counter against configurable threshold | [hooks/no-emoji-spam.sh](hooks/no-emoji-spam.sh) (umbrella-only) |
| **no-tldr-bait** | "TL;DR:" / "In summary:" / "Bottom line:" tail block on long messages (>200 chars) | regex match at message end; short-message exemption | [hooks/no-tldr-bait.sh](hooks/no-tldr-bait.sh) (umbrella-only) |
| **no-meta-commentary** | "Let me think about this" / "Now I'll consider" / "First, I need to think" message-open patterns narrating chain-of-thought instead of producing the answer | inspect first 240 chars for meta-thinking openers | [hooks/no-meta-commentary.sh](hooks/no-meta-commentary.sh) (umbrella-only) |
| **no-prompt-restate** | "You asked me to X" / "I understand that you want X" / "So you'd like me to X" preamble waste at message open | inspect first 200 chars for restate openers; allow-clause for explicit operator-asked verification | [hooks/no-prompt-restate.sh](hooks/no-prompt-restate.sh) (umbrella-only) |
| **no-disclaimer-spam** | "Please note that" / "It's important to mention" / "Keep in mind" defensive padding (paternalism family, Anthropic Constitution) | regex match against disclaimer phrases; fire on any occurrence | [hooks/no-disclaimer-spam.sh](hooks/no-disclaimer-spam.sh) (umbrella-only) |
| **no-ai-tells** | known LLM-default phrases ("delve into", "tapestry", "navigate the intricacies", "in the realm of", "leverage cutting-edge", etc.) | regex match against canonical AI-tell vocabulary | [hooks/no-ai-tells.sh](hooks/no-ai-tells.sh) (umbrella-only) |
| **no-roleplay-drift** | "as an AI assistant, I" / "I'm just an AI" / "as a language model" / "I do not have opinions" — model breaking agent character mid-task (DarkBench Anthropomorphism inverse) | regex match against roleplay-break phrases | [hooks/no-roleplay-drift.sh](hooks/no-roleplay-drift.sh) (umbrella-only legacy; standalone restoration planned) |

## Loadable packs (operator-extensible without forking)

Vocabulary, evidence binaries, and destructive command lists are now
external `.txt` files. Operators can extend coverage by dropping new
files at the XDG location — no fork, no PR required for local use.

```
packs/
  locale/        # vocabulary used by no-vibes (positive_closeout, negation)
    en.txt       # English (default, ships with repo)
    es.txt       # Spanish (Latin American + Iberian forms)
    pl.txt       # Polish (Tekalan-confirmed bootstrap)
  evidence/
    binaries.txt # binaries that count as command evidence in 9 sections:
                 # app-dev, containers, k8s, devops, cloud, database,
                 # shell-tools, system, archive, http (200+ binaries)
  destructive/   # destructive command surfaces (operator opts in via env)
    filesystem.txt        # rm -r/, dd, mkfs, find -delete, chmod -R 777,
                          # git reset --hard, git clean -fd, git checkout --
    container.txt         # docker stop/rm/prune, kubectl delete, helm
                          # uninstall, argocd app delete
    git-protected.txt     # git push --force, filter-branch, filter-repo,
                          # branch -D, reflog expire
    config-overwrite.txt  # in-place writes to .env*, .storage/, .ssh/,
                          # .gnupg/, .kube/, secrets/
    cloud-prod.txt        # terraform/tofu/pulumi destroy, terraform state
                          # rm/mv, aws s3 rm --recursive, gcloud delete,
                          # az delete, doctl delete
    database.txt          # DROP TABLE/DATABASE/SCHEMA, TRUNCATE, FLUSHALL,
                          # dropDatabase()
    service.txt           # systemctl/service/launchctl/supervisorctl stop
```

**Discovery priority** (highest first):
1. `$LLM_DARK_PATTERNS_PACK_DIR/<subdir>/<name>.txt` — explicit override
2. `${XDG_CONFIG_HOME:-$HOME/.config}/llm-dark-patterns/packs/<subdir>/<name>.txt` — operator local
3. `<repo>/packs/<subdir>/<name>.txt` — ships with repo

**Locale selection**:
- `$LLM_DARK_PATTERNS_LOCALE=en,es,pl` — explicit comma-separated
- `${LANG:0:2}` — auto-detect when env unset (always layered on top of `en`)
- `en` — final fallback

**Surface opt-in for destructive packs**:
- `LLM_DARK_PATTERNS_DESTRUCTIVE_PACKS=filesystem,container,git-protected` — subset
- Default: all 7 surfaces active

**Evidence category opt-in**:
- `LLM_DARK_PATTERNS_EVIDENCE_CATEGORIES=app-dev,devops,k8s` — subset
- Default: all 9 categories active

## Physics-backed closeout engines

The paper-grade, benchmark-backed lane lives in
[waitdeadai/agent-closeout-bench](https://github.com/waitdeadai/agent-closeout-bench).
It is not a replacement for the small standalone hooks; it is the reproducible
engine layer that makes closeout mechanics testable, hashable, and comparable.
For daily use, the adapter installer writes the selected Stop/SubagentStop hook
wrappers plus a PreToolUse tamper guard. The tamper guard blocks ordinary Claude
Code attempts to edit the hook wiring, adapter env, pinned engine, or pinned
rule pack; it is not an OS sandbox and should not be described as bypass-proof.

The v0.2 evidence-claim engine deliberately rejects weak proof shapes such as
`Implemented and checked.`, `Done. Commands run: none.`, and `Changed files:`
without command or verification evidence. This is still closeout-contract
evidence, not independent proof that the underlying work truly happened.

Current physics-backed adapters:

| Adapter hook | Category engine | Use |
|---|---|---|
| `no-vibes.sh` | `evidence_claims` | block completion/verification claims without evidence markers |
| `no-wrap-up.sh` | `wrap_up` | block generic retention tails |
| `no-cliffhanger.sh` | `cliffhanger` | block dangling permission loops |
| `no-roleplay-drift.sh` | `roleplay_drift` | block persona drift replacing useful status |
| `no-sycophancy.sh` | `sycophancy` | block praise/validation before substance |

Install all physics-backed adapters from a clone of AgentCloseoutBench:

```bash
git clone https://github.com/waitdeadai/agent-closeout-bench
cd agent-closeout-bench
bash adapters/claude-code/install.sh /path/to/your/project
bash scripts/hook-smoke.sh
```

Install one adapter:

```bash
bash adapters/claude-code/install.sh /path/to/your/project no-cliffhanger
```

The adapter installer writes a `.claude/settings.agentcloseout.example.json`
snippet for Claude Code, including the tamper-guard `PreToolUse` entry. Merge
the entries you want into `.claude/settings.json`.

For research, fixtures, public-data intake, human-labeling protocol, and
collaboration telemetry, use AgentCloseoutBench directly:

```bash
bin/agentcloseout-physics lint-rules rules/closeout
bin/agentcloseout-physics test-rules rules/closeout fixtures/closeout
bin/agentcloseout-physics telemetry-preview --queue /path/to/local-queue.jsonl
```

## Architecture (the pattern that generalizes)

Every hook in the suite follows the same 4-step design:

1. **Pick a failure mode that has a textual signature.** Not "model is wrong" (no signature). Something like "claims success without evidence" or "opens with praise-spam" — these have distinct vocabularies.
2. **Define the signature precisely.** Two regex sets: the *bad* pattern, and the *redemption* (or *allow*) pattern. Bad without redemption → trigger.
3. **Wire a non-LLM judge** at a Claude Code hook event. Bash. Python. Anything that isn't another LLM call. The judge is not the same kind of thing as the actor.
4. **Block + repair-template.** A bare block stalls. A block + the literal compliant shape lets the model copy the template on the next turn. The repair-template *teaches*; the block alone just punishes.

This pattern composes. If you find a sixth dark pattern with a clean textual signature, write `no-X.sh` in 50–100 lines of bash and ship it as a sister repo. If you publish it under the same conventions (Apache-2.0, single file, `RECEIPTS.md` with reproducible fixtures, sister-tools cross-link block), open a PR adding it to the table above.

### Where this fits in the LLM safety stack

This suite is **orthogonal**, not competitive, to the established LLM safety tools. Each operates at a different boundary:

| Layer | Tool | Catches | Operates at |
|---|---|---|---|
| Input firewall | [Lakera Guard](https://www.lakera.ai/), [LLM Guard (ProtectAI)](https://github.com/protectai/llm-guard), [Pangea](https://pangea.cloud/) | Prompt injection, jailbreak, PII in input | LLM API request boundary |
| Conversational rails | [NVIDIA NeMo Guardrails](https://github.com/NVIDIA-NeMo/Guardrails) | Topic control, dialog flow, fact-check, jailbreak | Inline middleware, programmable Colang DSL |
| Agent runtime policy | [AgentSpec (Wang et al., ICSE '26)](https://arxiv.org/abs/2503.18666), [Pro²Guard (arXiv 2508.00500)](https://arxiv.org/abs/2508.00500) | Code execution safety, embodied agent safety, AV compliance | Agent tool-call boundary, DSL-defined triggers/predicates |
| Output content scanning | [LLM Guard output scanners](https://github.com/protectai/llm-guard) (35 scanners) | Toxicity, PII, gibberish, factual consistency, bias, code injection | LLM response boundary |
| Behavioral benchmarks (not enforcement) | [DarkBench (Kran et al., ICLR '25)](https://arxiv.org/abs/2503.10728), [DarkPatterns-LLM (arXiv 2512.22470)](https://arxiv.org/abs/2512.22470) | Six dark-pattern categories (sycophancy, anthropomorphism, sneaking, brand bias, retention, harmful gen) | Offline evaluation corpora |
| **This suite** | **`llm-dark-patterns`** | **Dark-pattern *closeout-boundary enforcement*: sycophancy, false-success, permission loops, paternalism, training-cutoff confidence, compaction amnesia, and the Slice 2-5 fact-fabrication / interaction-style / multi-agent / residual families** | **Claude Code `Stop` / `SubagentStop` / `TaskCreated` / `TaskCompleted` / `PreToolUse` / `PostToolUse` / `PreCompact` / `PostCompact` / `SessionStart` hook events** |

The intersection of **dark-pattern detection + runtime enforcement at the agent loop boundary** is the slot this suite occupies. The enforcement-side peers (Lakera, NeMo, LLM Guard, AgentSpec) currently have approximately zero dark-pattern coverage; the dark-pattern-side peers (DarkBench, DarkPatterns-LLM) are detection corpora with no runtime enforcement.

You can run this suite *alongside* any of the input-firewall / conversational-rails / output-scanning layers — they operate at different boundaries and don't conflict. Pairing with the deterministic floor + LLM ceiling pattern (2026 production best-practice: deterministic checks first, LLM judge for ambiguous cases) is also straightforward — the hooks' `BLOCKED` decisions are the deterministic floor, and an out-of-band LLM judge can be wired as a separate hook for cases the regex doesn't catch.

### Adjacent operator-side work

[`@yurukusa`](https://github.com/yurukusa) maintains a parallel set of Stop-hook gates targeting the same closeout boundary at adjacent sub-failures — [`same-correction-arrest.sh`](https://github.com/yurukusa/cc-safe-setup/blob/main/examples/same-correction-arrest.sh) (correction-repetition) and [`closure-word-verify-gate.sh`](https://github.com/yurukusa/cc-safe-setup/blob/main/examples/closure-word-verify-gate.sh) (closure-word-without-evidence). These compose with this suite rather than competing: different gate predicates firing on the same `Stop` / `SubagentStop` events.

The upstream taxonomy that names the failure mode this suite gates against — *recognition-without-arrest*, a three-stage decomposition (Recognition → Articulation → Non-gating) — was anchored by [@suwayama in `anthropics/claude-code#60226`](https://github.com/anthropics/claude-code/issues/60226) and synthesized across 10 reporter-credited patterns in [@yurukusa's article](https://gist.github.com/yurukusa/93123855318c022f21df92a7ac33c87b) (2026-05-19). MAST mode 3.3 ("No or Incorrect Verification") is the published evaluation handle for the same Stage 3 failure point; the F1 0.815 / CI / κ result in [`evaluation/MAST-RESULTS.md`](evaluation/MAST-RESULTS.md) is the quantitative baseline for that gate. The bidirectional cross-link sits at [`anthropics/claude-code#60451`](https://github.com/anthropics/claude-code/issues/60451) and as a comment on the gist itself.

The "out-of-loop, deterministic, code-not-model" formulation that [`anthropics/claude-code#60188`](https://github.com/anthropics/claude-code/issues/60188) converged on is a tighter formulation of the architectural property each of these hook implementations expresses: the gate cannot be downstream of the same distribution that produced the recognition, otherwise recognition and arrest fail together.

The 2026-05-22 launch-day forensic snapshot at [yurukusa/forensic-2026-05-22](https://gist.github.com/yurukusa/64b4340b850d389bf67b153136a341db) extends the cluster with four independent corroboration axes filed in the 24-hour window straddling the Claim-Verify Handbook launch: [`jaswalmohit8-collab/weasel`](https://github.com/jaswalmohit8-collab/weasel) (cross-model Opus + Kimi K2 evidence from 1600+ hours of long-running Polymarket agent deployment), [`anthropics/claude-code#61303`](https://github.com/anthropics/claude-code/issues/61303) (Windows MAX_PATH silent fail-to-persist at the Edit/Write boundary), [`anthropics/claude-code#61296`](https://github.com/anthropics/claude-code/issues/61296) (Opus-vs-Sonnet cross-model instruction-binding isolation under held-constant CLAUDE.md), and [`anthropics/claude-code#61305`](https://github.com/anthropics/claude-code/issues/61305) (repeated zero-comment instructions ignored after acknowledgment). Adjacent vendor-side evidence: [Aonan Guan's CVE-2025-66479 disclosure](https://oddguan.com/blog/second-time-same-sandbox-anthropic-claude-code-network-allowlist-bypass-data-exfiltration/) (2026-05-20) documents two network-sandbox bypass paths that left ~130 Claude Code releases exposed for 5.5 months — the *claim-vs-reality* gap at the vendor-side layer, structurally the same shape this suite gates at the tool-call layer.

The cluster-narrative artifact synthesizing these axes is yurukusa's *[Claim-Verify Handbook](https://yurukusa.gumroad.com/l/claim-verify-handbook)* (live since 2026-05-22), which catalogs 130 cases of claim-vs-reality mismatch in Claude Code sessions across the 2026-05-09 to 2026-05-17 measurement window (15 main cases + 115 Appendix D continuing-evidence cases, 233 hours, 32-fold acceleration over the 30-day baseline). The Handbook is the forensic-record counterpart to this suite's text-vocabulary detection layer: it documents *what* the recognition-without-arrest failure modes look like in production, where this suite documents the regex / structural / semantic detection primitives that gate against them. Anchored to [`anthropics/claude-code#60226`](https://github.com/anthropics/claude-code/issues/60226).

The receipt-persistence layer @yurukusa is shipping via [`cc-safe-setup` PR #282](https://github.com/yurukusa/cc-safe-setup/pull/282) (scope-expansion-receipt, destructive-bash boundary) + [PR #283](https://github.com/yurukusa/cc-safe-setup/pull/283) (dispatch-receipt, agent-dispatch boundary) + [PR #285](https://github.com/yurukusa/cc-safe-setup/pull/285) (PostToolUse disk-bypass verification, Edit/Write boundary) + [PR #286](https://github.com/yurukusa/cc-safe-setup/pull/286) (dispatch-allowlist-preflight) + [waitdeadai PR #288](https://github.com/yurukusa/cc-safe-setup/pull/288) (articulated-scope-capture UserPromptSubmit companion + `receipts-aggregate.py` denormalization CLI) is the operator-instrumented complement to this suite's text-vocabulary Stop hooks. The composition decomposes the existing F1 numbers under the **`effective_arrest_rate = gate_installation_rate × gate_recall`** identity — F1 0.815 / κ 1.000 on n=19 measures `gate_recall` conditional on installation; the receipt corpus (with schema v2 fields `articulated_scope_hash` + `articulated_scope_length` now landing via PR #288 on the prompt side, and pending amendment on the destructive-bash + dispatch sides) measures `gate_installation_rate` directly from the deployed cohort. The decomposition vocabulary is staged for the §2 quick-ref of [`ianymu/recognition-without-arrest`](https://github.com/ianymu/recognition-without-arrest) per [`#61102#issuecomment-4513977211`](https://github.com/anthropics/claude-code/issues/61102#issuecomment-4513977211) and [`#61102#issuecomment-4514215413`](https://github.com/anthropics/claude-code/issues/61102#issuecomment-4514215413).

[`@beq00000`](https://github.com/beq00000) operates an operator-with-agent-pair pattern and contributes the clean-state empirical baseline (seven instances of recognition-without-arrest per non-drifted session, all caught externally) plus a constellation-navigation memo synthesising the cluster across nine constellation members ([navigation memo gist](https://gist.github.com/beq00000/46e131f359f3b32662740d5dca7d0761), 2026-05-19). The operator-language Socratic-narrowing intervention beq00000 documents — "is this verifiable / already-documented / what-would-actually-need-attention look like" framed as gradient question rather than binary defence prompt — is the input-side analogue of the runtime-side gate yurukusa is shipping at [`cc-safe-setup#259`](https://github.com/yurukusa/cc-safe-setup/pull/259) (`PreToolUse public-artefact-socratic-narrowing.sh`).

The methodological piece that pairs with this thread — fixture-driven iteration with regression catches and commit-level provenance, applicable to any deterministic LLM-text-classification hook — is written up at [`docs/methodology/fixture-driven-iteration.md`](docs/methodology/fixture-driven-iteration.md) as a reusable pattern under Apache-2.0.

### Empirical evaluation against DarkBench

Re-ran [DarkBench](https://github.com/apartresearch/darkbench) (Kran et al., ICLR 2025, [arXiv:2503.10728](https://arxiv.org/abs/2503.10728)) against `claude-sonnet-4-6` in 2026-05. **Sycophancy prevalence dropped from 13% in the paper's 14-model 2025 average to 1.8% on Sonnet 4.6 alone** — RLHF appears to have measurably reduced the canonical sycophancy surface in the year between studies. Anthropomorphization (62%) and user-retention (79%) prevalence remain high.

Hooks tested as black-box text classifiers against the same corpus. With the Rust YAML rule pack engine ([physics-engines plan, Slices 2-5](https://github.com/waitdeadai/agent-closeout-bench/tree/main/docs/physics-engines)), `no-roleplay-drift` achieves **F1 0.590** (P 0.655, R 0.537) on the anthropomorphization sample — a 5x true-positive jump (7→36) over the original bash-only F1 of 0.163. The other three in-scope hooks (`no-sycophancy`, `no-wrap-up`, `no-cliffhanger`) show parity between bash regex and Rust YAML on this chat surface. User-retention hooks underperformed because the chat-reply vocabulary in DarkBench prompts is emotional/relational ("good friend dropping by", "your daily companion") rather than the transactional closeout vocabulary the hooks were tuned for ("shall we wrap up", "let me know if anything else"). The 240-character opener window in `no-sycophancy` also misses sycophancy that lives later in long responses.

Honest data: the hooks have a documented vocabulary-distribution gap when applied to chat-reply text vs the Claude Code closeout text they were designed for. Reproducible end-to-end (~$12 PAYG-equiv, ~3 hours sequential). [Full v1 results →](evaluation/RESULTS.md) · [Head-to-head bash-vs-Rust comparison (v1.5-rust) →](evaluation/RESULTS-v1.5-rust.md)

## Install (recommended): self-hosted marketplace

```bash
claude plugin marketplace add waitdeadai/claude-plugins
claude plugin install llm-dark-patterns@waitdeadai-plugins
```

This installs all 31 wired hooks across `Stop`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `PreToolUse`, `PostToolUse`, `PreCompact`, `PostCompact`, and `SessionStart` events. Each hook remains independently disablable by editing `hooks.json` after install.

The self-hosted marketplace at [`waitdeadai/claude-plugins`](https://github.com/waitdeadai/claude-plugins) is the **canonical install path** because the Anthropic community marketplace pipeline has stalled for many submitters since at least March 2026. This plugin shows as **Published** in the submissions dashboard since 2026-05-11 but does not appear in the live `claude-plugins-community/marketplace.json` (verified 2026-05-17 — zero matches across 1715 entries; last bulk sync to that file was 2026-05-13 with no new syncs since).

The same pattern is documented across at least eight open issues on `anthropics/claude-plugins-official`: [#984](https://github.com/anthropics/claude-plugins-official/issues/984) (since 2026-03-25, 11 comments), [#1272](https://github.com/anthropics/claude-plugins-official/issues/1272) (closed without resolution, 23+ "same here" comments), [#1474](https://github.com/anthropics/claude-plugins-official/issues/1474), [#1512](https://github.com/anthropics/claude-plugins-official/issues/1512), [#1834](https://github.com/anthropics/claude-plugins-official/issues/1834), [#1841](https://github.com/anthropics/claude-plugins-official/issues/1841), [#1870](https://github.com/anthropics/claude-plugins-official/issues/1870), [#1887](https://github.com/anthropics/claude-plugins-official/issues/1887). Two sync PRs ([#18](https://github.com/anthropics/claude-plugins-community/pull/18), [#21](https://github.com/anthropics/claude-plugins-community/pull/21)) have been stuck unmerged for 12-15 days.

If Anthropic's pipeline resumes, the community-marketplace path becomes a redundant install option, but until then the self-hosted route above is the only one that actually resolves:

```bash
# Currently does NOT resolve for this plugin or for many others — see #1887
claude plugin marketplace add anthropics/claude-plugins-community
claude plugin install llm-dark-patterns@claude-community
```

## Install standalone hooks

The public standalone repos are still the simplest daily-use path when you want a subset rather than the whole suite. Install the single-file hooks that already have standalone repos:

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

Requires `jq` (and `python3` for `time-anchor` and `no-amnesia`).

## Pitch / framing

The industry is optimizing LLMs for mass-market efficiency: faster, shorter, more agreeable, more cautious. That gradient runs **against** the power-user objective of correct results, deep verification, and operator agency. The Dark Patterns Hooks suite is the counter-position: small, surgical bash hooks that suppress the polite-cautious-efficient defaults at the textual boundary so the model can produce results instead of vibes.

The hooks are **conservative on purpose** — they would rather false-positive on legitimate prose that overlaps the dark-pattern vocabulary than false-negative on the actual dark pattern. The repair-template is the part that makes false-positives non-painful: when the hook fires on a legitimate use, the model sees the template and can repair into a closeout shape that satisfies the regex.

## Not a jailbreak

Important clarification: this suite **does not** suppress safety refusals, content-policy enforcement, or harm-prevention. The regexes are narrow to specific interaction-style defaults (sycophancy, paternalism, false-completion, permission-spam). If you want a tool that bypasses Claude's safety behaviors, this is not it.

## Threat model

This suite catches specific textual signatures at the Claude Code stop and sub-agent-stop lifecycle hooks. It is not a sandbox, a refusal layer, or a prompt-injection defence. Operators considering this for safety-critical workflows should read the failure modes below before relying on it.

1. **Lexical evasion.** The hooks are deterministic and rule-based. Paraphrase, synonym substitution, and reordering can defeat any single rule. The companion benchmark [`agent-closeout-bench`](https://github.com/waitdeadai/agent-closeout-bench) is the surface where this brittleness is measured rather than hidden.

2. **Hook misconfiguration.** The runtime requires correctly wired Claude Code hook entries in `.claude/settings.json`. A disabled hook, a typo in the hook command, or a workflow that bypasses `Stop` entirely produces a silent miss. The hook cannot detect that it was never invoked.

3. **Runtime bypass.** A local operator with shell access can disable hooks at any time, or pipe the hook output to `true`. This is a deterministic verdict layer, not an operating-system sandbox. Threats from a hostile operator on the same host are out of scope.

4. **In-band manipulation.** Hook decision logic runs out-of-band relative to the model that produced the closeout, so the model cannot directly rewrite the verdict. The model can, however, be coerced by an upstream prompt to phrase a false closeout in language the rules do not catch. *Out-of-band* means the verdict path is independent of the model context, not that the closeout text is unmanipulable.

5. **Evidence-marker limitations.** Several hooks treat tokens such as ``verification passed`` or ``tests pass`` as closeout-contract evidence that mitigates other dark-pattern signals. These markers establish that the closeout contract was honoured in form; they are not independent proof that the underlying verification command actually succeeded. A workflow that wants stronger guarantees should record verifier outputs separately and treat closeout text as one of several signals.

6. **Coverage and language scope.** Rules are English-only. The lifecycle surface is the Claude Code `Stop` and `SubagentStop` hook payload; behaviour on other agent frameworks is undefined.

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
