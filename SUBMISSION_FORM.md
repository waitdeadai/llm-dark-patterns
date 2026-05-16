# Submission Form Content — clau.de/plugin-directory-submission

Prepared for operator to paste into the Anthropic plugin marketplace submission form at https://clau.de/plugin-directory-submission.

Submission timestamp: TBD (filled by operator after submit).
Submission version: plugin.json `version` = `1.0.0` on branch `marketplace/submission-1` at commit TBD.

---

## Plugin name
`llm-dark-patterns`

## Short description (single sentence, ~140 chars)
Out-of-band Claude Code hook judges that block 28 LLM dark patterns at the Stop / SubagentStop closeout boundary. Deterministic, Apache-2.0.

## Long description (1-3 paragraphs)
LLM Dark Patterns Hooks is a suite of single-purpose Claude Code hooks that suppress LLM dark-pattern defaults at the textual boundary where the assistant claims it is done. The hooks fire at `Stop`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `PreToolUse`, `PostToolUse`, `PreCompact`, `PostCompact`, and `SessionStart` events.

The hooks catch failure modes that the academic dark-patterns literature has measured but that no in-context system prompt can reliably suppress: false-success closeouts without evidence, sycophancy, paternalism, permission-loops, vibe time estimates, fake recall, fake stats, fake citations, context loss after compaction, multi-agent rollup hallucinations, role-play drift, emoji spam, and power-user polish defaults. Each hook is deterministic regex over the closeout text; no model participates in the verdict path, so the same model that produced the dishonest closeout cannot override the verdict.

The suite is paper-grade in design: an Apache-2.0 reference engine (`agent-closeout-bench`), a public claim ledger that codifies which claims are forbidden, an explicit threat model in the README (lexical evasion, hook misconfiguration, runtime bypass, in-band manipulation, evidence-marker limitations, language scope), and a public companion benchmark currently in workshop-paper submission. This is not a jailbreak; it does not suppress safety refusals or content-policy enforcement. It suppresses interaction-style dishonesty defaults that are orthogonal to refusal robustness.

## Category
`security`

## Tags (suggested)
`safety`, `governance`, `hooks`, `stop-hooks`, `ai-safety`

## Author
- Name: `waitdeadai`
- URL: `https://github.com/waitdeadai`

## Homepage / repository
- Homepage: `https://github.com/waitdeadai/llm-dark-patterns`
- Repository: `https://github.com/waitdeadai/llm-dark-patterns`

## License
`Apache-2.0`

## Version at submission
`1.0.0`

## Install command (for marketplace listing)
```bash
claude plugin marketplace add anthropics/claude-plugins-community
claude plugin install llm-dark-patterns@claude-community
```

## Trust posture (paragraph for reviewer)
This plugin defines no MCP server, no auto-loading skill files (`find . -name SKILL.md` returns zero hits), no `ANTHROPIC_BASE_URL` override, no pre-trust network request, and no read of `.env`, `.claude/settings.local.json`, or `secrets/`. All 31 wired hooks have been audited per the `SECURITY_AUDIT.md` artifact in the repo. Every hook reads only its stdin JSON payload and (state machinery hooks only) writes to `.no-amnesia/state/CURRENT.md` within the workspace. The repo licence is Apache-2.0, with a paper-grade claim ledger codifying what the plugin does not and will not claim. CVE-2026-21852 class issues do not apply.

## Why this should be in the marketplace
The dark-patterns category has been formally measured by:
- DarkBench (Kran et al., ICLR 2025 Oral) — 48% of LLM conversations trigger at least one dark pattern.
- AAAI 2026 Spring Symposium — sycophancy at 91.7% prevalence.
- IEEE S&P 2026 — agents susceptible 41% of the time to a single dark pattern.
- Anthropic's own constitution — "various forms of paternalism and moralizing are disrespectful."

There is, to our knowledge, no other Claude Code plugin whose entire surface is a closeout-stage dark-patterns hook suite with a paper-grade claim ledger and a companion academic benchmark. The plugin makes Anthropic's stated design intent operationally enforceable at the Claude Code hook boundary.

## Contact email
TBD (filled by operator at submit time; suggest `proeliteinterface@gmail.com` per user-stored email).

## Screenshots (if required)
If the form requires screenshots, suggest:
1. A `BLOCKED: praise-spam` hook fire in a Claude Code terminal.
2. The Threat Model section of the README rendered on GitHub.
3. The `agent-closeout-bench` rule-pack listing showing per-category engine manifests.

(All three can be captured from a local smoke-test session; operator decides whether to include.)

## Known limitations (for the reviewer)
- Lexical regex; paraphrase can evade individual rules.
- Hook misconfiguration produces silent misses.
- Runtime bypass possible by a local operator with shell access — this is a verdict layer, not an OS sandbox.
- English-only.
- Lifecycle surface is Claude Code Stop / SubagentStop; behaviour on other agent frameworks is undefined.
- Documented in full in `README.md` §Threat model.

## Anthropic Verified badge follow-up
After standard listing lands, we plan to request the Anthropic Verified badge as a separate review. Detail to be recorded in `MARKETPLACE_SUBMISSION_LOG.md` when that path opens.

## external_plugins inclusion follow-up
After standard listing lands, we plan to request inclusion in `anthropics/claude-plugins-official/external_plugins/` directory as a separate process. Detail to be recorded in `MARKETPLACE_SUBMISSION_LOG.md`.

---

## Operator pre-flight checklist (before clicking Submit)

- [ ] Branch `marketplace/submission-1` is pushed and CI is green
- [ ] `SECURITY_AUDIT.md` reviewed and accepted
- [ ] `plugin.json` `version` is `1.0.0`
- [ ] `README.md` includes the marketplace install snippet
- [ ] Contact email confirmed
- [ ] Screenshots prepared (if form requires)
- [ ] Submission form fields above match what the live form actually asks for; revise this file if mismatch
- [ ] After submit, operator pastes confirmation URL/ID into `MARKETPLACE_SUBMISSION_LOG.md`
