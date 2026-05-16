# Submission Form Content — Anthropic plugin marketplace

Prepared for operator to paste into one of the in-app submission forms (verified live in Claude Code v2.1.143 docs at https://code.claude.com/docs/en/plugins, 2026-05-16):

- **Claude.ai**: https://claude.ai/settings/plugins/submit
- **Console**: https://platform.claude.com/plugins/submit

Both forms route into the same Anthropic internal review pipeline. Pick whichever account you are already logged in to.

Submission timestamp: TBD (filled by operator after submit).
Submission version: plugin.json `version` = `1.0.0` on branch `marketplace/submission-1`.

Local plugin-load evidence (run 2026-05-16, Claude Code v2.1.143):

```
mkdir -p /tmp/plugin-test-$$ && cd /tmp/plugin-test-$$ && \
  claude --plugin-dir /home/fer/Documents/llm-dark-patterns \
         -p 'Reply exactly: PLUGIN_LOAD_OK'
# stdout: PLUGIN_LOAD_OK
# exit 0
```

The plugin loads cleanly in a fresh workspace via the documented `--plugin-dir` flag.

---

## Resubmission context (2026-05-16)

This is a **v1.0.0 update resubmission** of a plugin that shows status `Published` in the submissions dashboard as of 2026-05-11, but is not present in the live `anthropics/claude-plugins-community/.claude-plugin/marketplace.json` (1715 entries scanned 2026-05-16; zero matches for `waitdeadai` source URLs). Tracking issue: `anthropics/claude-plugins-official#1887`. The v1.0.0 expands from 10 wired hooks to 31 wired hooks across 9 lifecycle events. If the form has an "update existing listing" mode that recognises the prior submission, use it; otherwise resubmit as a fresh entry and the dashboard will surface the relationship.

## Plugin name
`llm-dark-patterns`

## Short description (single sentence, ~140 chars)
v1.0.0 update — 31-hook out-of-band suite that blocks LLM dark-pattern closeouts at Claude Code Stop / SubagentStop. Deterministic, Apache-2.0.

## Long description (1-3 paragraphs)
LLM Dark Patterns Hooks is a suite of single-purpose Claude Code hooks that suppress LLM dark-pattern defaults at the textual boundary where the assistant claims it is done. v1.0.0 expands the previously listed 10-hook surface to 31 wired hooks across nine lifecycle events: `Stop`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `PreToolUse`, `PostToolUse`, `PreCompact`, `PostCompact`, and `SessionStart`.

The hooks catch failure modes that the academic dark-patterns literature has measured but that no in-context system prompt can reliably suppress: false-success closeouts without evidence, sycophancy, paternalism, permission-loops, vibe time estimates, fake recall, fake stats, fake citations, context loss after compaction, multi-agent rollup hallucinations, role-play drift, emoji spam, and power-user polish defaults. Each hook is a deterministic regex pass over the closeout text; no model participates in the verdict path, so the same model that produced the dishonest closeout cannot override the verdict.

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
