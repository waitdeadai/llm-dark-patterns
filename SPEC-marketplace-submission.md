# SPEC: Anthropic Plugin Marketplace Submission

Time anchor: 2026-05-16
Outer route: `/opussonnet`
Inner contract: workflow
Submission portal: `https://clau.de/plugin-directory-submission` (verified 2026-05-16)
Both targets resolve to one submission; Anthropic routes internally.

## 1. Problem Statement

The `llm-dark-patterns` repo ships 28 wired hooks and a `plugin.json`, but the plugin has never been submitted to the Anthropic Claude Code marketplace. Every Claude Code user discovers plugins through that marketplace, and the suite's distribution is currently bottlenecked on GitHub Awesome-list PRs (open at `webfuse-com/awesome-claude#224` and `jmanhype/awesome-claude-code#43`). One marketplace submission opens up first-party distribution.

## 2. Research Claims

Primary claim:

> `llm-dark-patterns` is, to our knowledge, the first Claude Code plugin whose entire surface is a Stop / SubagentStop suite for closeout-stage LLM dark patterns, with a paper-grade claim ledger, an Apache-2.0 reference engine, and a public companion benchmark (`agent-closeout-bench`).

Non-claims:
- We do not claim Anthropic Verified badge until Anthropic awards it.
- We do not claim inclusion in `claude-plugins-official/external_plugins/` until Anthropic adds the entry.
- We do not claim universal-agent coverage.
- We do not claim prompt-injection immunity.
- We do not claim this is the only dark-patterns hook plugin in the marketplace; we make no comparative-quality claim against other listings.

## 3. Success Criteria

Each criterion is verifiable by a file, command, or external artifact.

1. **`plugin.json` validates against the current marketplace schema.**
   - Verify: `jq -e . .claude-plugin/plugin.json > /dev/null` and a one-shot schema check (see Task 1).
2. **All 28 wired hooks are executable on a clean checkout and pass syntax check.**
   - Verify: existing CI `test.yml` job `Bundled-plugin smoke tests` passes on this branch.
3. **Plugin installs end-to-end on a fresh Claude Code workspace.**
   - Verify: `claude plugin marketplace add waitdeadai/llm-dark-patterns` (or local path equivalent) then `claude plugin install llm-dark-patterns` succeeds, and a sample dark-pattern fixture triggers a BLOCKED verdict from `no-vibes.sh`.
4. **Security-guidance compliance audited.**
   - Verify: a `SECURITY_AUDIT.md` artifact records that every hook reads only its own stdin payload + repo files, makes no network calls, reads no `.env`/secrets, and has no auto-loading skill.
5. **Submission record exists with confirmation ID.**
   - Verify: `MARKETPLACE_SUBMISSION_LOG.md` contains submission timestamp, form URL, confirmation message or ID, and the plugin slug Anthropic assigned (if any).
6. **No regression on existing CI.**
   - Verify: `tests` workflow on this branch is green; stress fixtures still pass.
7. **Version bumped to a marketplace-appropriate level.**
   - Verify: `plugin.json` `version` is `1.0.0` (operator-confirmed before submission) or another deliberately chosen value, not `0.1.0`.

## 4. Scope

### In scope
- Validate and (if needed) update `plugin.json` against current marketplace requirements.
- Read end-to-end the Anthropic plugin security guidance and produce a `SECURITY_AUDIT.md` mapping each hook to "complies / non-compliance / clarification needed".
- Bump plugin `version`.
- Add a marketplace-facing `README.md` excerpt or top-of-README hook (likely the existing README already qualifies; verify).
- Run the existing `tests` CI on the submission branch to confirm green.
- Operator submits via the form at `clau.de/plugin-directory-submission`; agent prepares the form-fill content (description, categories, screenshots if available, contact email).
- Log submission in `MARKETPLACE_SUBMISSION_LOG.md`.

### Out of scope
- AgentCloseoutBench marketplace submission. ACB is a benchmark repo, not a plugin.
- Anthropic Verified badge upgrade. This is a follow-up after standard listing lands.
- Inclusion in `claude-plugins-official/external_plugins/`. Same — follow-up.
- New hook development. The 28 currently wired hooks are the submission surface.
- Windsurf / Cursor / Aider ports.
- Resuming the UAI paper sprint. Paused by separate decision; resumes when operator provisions keys.
- Anthropic Fellows application work. Separate slice (Z2).
- Outreach (Simon Willison, SMU group). Post-UAI-submission anyway.

## 5. Agent-Native Estimate

- estimate type: agent-native
- execution topology: local, single lane
- agent_wall_clock: optimistic 3 hr / likely 6 hr / pessimistic 10 hr
- agent_hours: ~5 hr (security audit is the long pole)
- human_touch_time: 30 min (operator reviews `SECURITY_AUDIT.md`, fills the submission form, captures the confirmation URL)
- calendar_blockers: Anthropic review queue (unknown ETA — could be hours, could be weeks; recorded as out-of-band)
- critical_path: read security guidance → security audit → plugin.json validation → CI green → operator submits → log result
- confidence: medium (downgrade: I have not seen the exact submission form fields; we will discover them at submit time and may need a packaging revision before resubmitting)
- human-equivalent baseline: ~1-2 days for a developer reading the docs end-to-end

## 6. Implementation Plan

### Task 1: Plugin.json schema validation
Definition of Done:
- [ ] Fetch current marketplace plugin schema from Anthropic docs (live).
- [ ] Run `jq -e . .claude-plugin/plugin.json` for JSON validity.
- [ ] Cross-check fields against the marketplace requirement list.
- [ ] Open a single commit on `marketplace/submission-1` branch with any schema fixes.

### Task 2: Security audit
Definition of Done:
- [ ] For each of the 28 wired hooks, record: file read pattern, network calls, env var reads, side effects on disk, secret-access risk.
- [ ] Cross-check against `claude.com/plugins/security-guidance` rules.
- [ ] Write `SECURITY_AUDIT.md` with per-hook verdict.
- [ ] Flag any non-compliant hook for either fix or removal from the bundle.

### Task 3: Version bump and metadata polish
Definition of Done:
- [ ] Operator confirms target version (likely `1.0.0` — first marketplace release).
- [ ] Bump in `plugin.json`.
- [ ] Verify `keywords`, `description`, `homepage`, `repository`, `license` are all marketplace-appropriate.
- [ ] Add a top-of-README "Install" snippet using the marketplace command syntax.

### Task 4: CI verification
Definition of Done:
- [ ] Push `marketplace/submission-1` branch.
- [ ] `tests` workflow green.
- [ ] Stress fixtures (337/337) still pass.
- [ ] No new warnings.

### Task 5: Submission form content prep
Definition of Done:
- [ ] Draft `SUBMISSION_FORM.md` with the exact text to paste into each field at `clau.de/plugin-directory-submission`.
- [ ] Include a short and long description, categories, keywords, install command, repo URL, contact email.
- [ ] Include a "Trust posture" paragraph (no MCP, no auto-loading skills, no network, Apache-2.0, deterministic verdicts).

### Task 6: Operator submission
Definition of Done:
- [ ] Operator opens `clau.de/plugin-directory-submission` and pastes the prepared content.
- [ ] Captures the confirmation URL and any reviewer notes.
- [ ] Pastes them into `MARKETPLACE_SUBMISSION_LOG.md` for the agent to commit.

### Task 7: Follow-up tracking
Definition of Done:
- [ ] `MARKETPLACE_SUBMISSION_LOG.md` includes the planned follow-ups: Anthropic Verified badge request, `external_plugins/` inclusion request.
- [ ] Cross-link in `agent-closeout-bench/.taste/strategic-pivot/2026-05-16/STRATEGIC-PIVOT.md`.

## 7. Verification

| Criterion | Verification Method |
|---|---|
| C1: plugin.json schema | `jq` + schema-doc cross-check |
| C2: hook syntax + executable | existing CI `test.yml` |
| C3: end-to-end install | local clean Claude Code workspace install + fixture trigger |
| C4: security audit | manual review of `SECURITY_AUDIT.md` against `security-guidance` |
| C5: submission record | inspection of `MARKETPLACE_SUBMISSION_LOG.md` |
| C6: no CI regression | `tests` workflow status on push |
| C7: version bump | `jq -r '.version' .claude-plugin/plugin.json` |

`/verify` runs at end of Tasks 1, 4, and 6. `/introspect` runs before Task 5 (submission form content prep) and before Task 6 (operator submission).

## 8. Rollback Plan

All work pre-submission is local and reversible:
1. `git checkout main && git branch -D marketplace/submission-1` undoes all packaging changes.
2. Plugin.json reverts to its previous form via `git checkout main -- .claude-plugin/plugin.json`.

Post-submission:
1. If Anthropic flags an issue during automated review, fix on `marketplace/submission-1` and resubmit via the same form.
2. If Anthropic approves and lists the plugin, withdrawal is possible — contact via the submission portal or filing an issue in `anthropics/claude-plugins-community`. The repo's own source remains under our control.
3. If a critical security issue surfaces post-listing, version-bump with the fix, push, and update the marketplace listing through the same form.

## 9. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Security guidance violation found in audit | Medium | Task 2 surfaces it before submission. Fix or remove the offending hook from the bundle (each is independent per `hooks.json`). |
| Plugin.json schema has changed since 2026-05-13 | Low | Task 1 fetches current schema live. |
| Marketplace rejects on a non-technical ground (e.g., "claim discipline" wording) | Low | Claim ledger codifies language; submission form copy will mirror that. |
| Anthropic review queue is multi-week | Medium | Recorded as out-of-band; not on critical path. Slice can close as "submitted, awaiting review" before approval lands. |
| Submission form requires fields not in plugin.json (categories, screenshots) | Medium | Task 5 drafts content for unknown fields; if a screenshot is required, capture one from a smoke-test session. |
| Anthropic asks for changes pre-listing | Medium | Resubmit via same form; tracked in `MARKETPLACE_SUBMISSION_LOG.md`. |

## 10. References (sprint source ledger, access 2026-05-16)

- [Anthropic plugin marketplace docs](https://claude.com/plugins)
- [Submission portal (canonical short link)](https://clau.de/plugin-directory-submission)
- [`anthropics/claude-plugins-official` repo](https://github.com/anthropics/claude-plugins-official)
- [`anthropics/claude-plugins-community` repo](https://github.com/anthropics/claude-plugins-community)
- [Anthropic plugin security guidance](https://claude.com/plugins/security-guidance) — content thin on submission specifics; deep read required at Task 2
- [Pluto Security extension-ecosystem analysis](https://pluto.security/blog/claude-extension-ecosystem-security-practitioner-guide/) — trust pyramid analysis, CVE-2026-21852
- Strategic pivot artifact: `agent-closeout-bench/.taste/strategic-pivot/2026-05-16/STRATEGIC-PIVOT.md` (commit `2ff47e5`)
- Existing LDP SPEC: `SPEC.md` (hook development; reused, not archived — different scope from this slice)
