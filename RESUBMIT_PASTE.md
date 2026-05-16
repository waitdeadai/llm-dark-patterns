# Resubmit paste content — v1.0.0

Generated 2026-05-16T14:09-03:00. Paste each block directly into the matching form field at `https://claude.ai/settings/plugins/submit` or `https://platform.claude.com/plugins/submit`.

---

## Link to plugin*

```
https://github.com/waitdeadai/llm-dark-patterns
```

## Plugin homepage

```
https://github.com/waitdeadai/llm-dark-patterns
```

## Plugin name*

```
llm-dark-patterns
```

## Plugin description*

```
v1.0.0 update of the published llm-dark-patterns suite. Expands from the original 10 hooks to 31 wired hooks across Stop, SubagentStop, TaskCreated, TaskCompleted, PreToolUse, PostToolUse, PreCompact, PostCompact, and SessionStart events. Adds multi-agent orchestration hooks (no-aggregator-hallucination, no-silent-worker-success, no-cherry-pick-rollup, no-ownership-violation, no-handoff-loop), agentic safety hooks (no-credential-leak-in-handoff, no-sandbagging-disguise, no-approval-sneak), and power-user polish hooks (no-emoji-spam, no-tldr-bait, no-meta-commentary, no-prompt-restate, no-disclaimer-spam, no-ai-tells, no-roleplay-drift). Out-of-band, deterministic, no network calls, no model in the verdict path, Apache-2.0. Public claim ledger and companion academic benchmark (agent-closeout-bench).
```

## Example use cases*

```
Example 1 — Premature "done" without evidence:
Claude finishes a refactor with "All set! The refactor is complete." and no test or command output. The no-vibes hook at Stop blocks the closeout and asks Claude to either show the verification evidence or close as partial.

Example 2 — Supervisor hallucinating worker consensus:
A subagent supervisor returns "All workers succeeded, here is the summary" without citing per-worker output. The no-aggregator-hallucination hook at Stop blocks the rollup and forces per-worker quotes or a downgraded claim.

Example 3 — Praise-spam openers:
Claude replies to a code question with "Great question! That is a really interesting problem to think about." The no-sycophancy hook at Stop blocks the filler so the operator does not have to skim past it.

Example 4 — Permission-loop endings:
At the end of a session, Claude appends "Want me to continue with the next migration?" without the operator asking for next steps. The no-cliffhanger hook at Stop blocks the dangling nudge.

Example 5 — Vibe time estimates:
Claude says "This will take about 3 hours to implement." without breaking down agent wall-clock vs human touch time. The honest-eta hook at Stop blocks the bare number and asks for an Agent-Native Estimate shape (optimistic, likely, pessimistic) or an explicit blocked/unknown label.

Example 6 — Fake citations:
Claude writes "This is documented in Smith et al., 2023" with no URL in the same message. The no-fake-cite hook at Stop blocks the citation-formatted reference until a verifiable link is included or the claim is softened.
```

---

## After you submit

1. Capture the confirmation URL or ID from the success page.
2. Tell the agent the URL/ID.
3. Agent appends it to `MARKETPLACE_SUBMISSION_LOG.md` under the `v1.0.0 (planned resubmit, 2026-05-16)` block and commits.

## If the form has extra fields

Paste the labels back to the agent. Likely candidates and pre-prepared answers:

| Likely field | Paste |
|---|---|
| Category | `security` |
| Tags / keywords | `safety, governance, hooks, stop-hooks, ai-safety` |
| License | `Apache-2.0` |
| Version | `1.0.0` |
| Author | `waitdeadai` |
| Contact email | `proeliteinterface@gmail.com` |
| Trust posture (free-form) | See `SECURITY_AUDIT.md` summary: no MCP, no auto-loading skills, no `ANTHROPIC_BASE_URL` override, no `.env` reads, no network calls, deterministic verdicts, Apache-2.0. All 31 wired hooks audited 2026-05-16. CVE-2026-21852 class issues do not apply. |
| Install command | ``claude plugin marketplace add anthropics/claude-plugins-community && claude plugin install llm-dark-patterns@claude-community`` |
