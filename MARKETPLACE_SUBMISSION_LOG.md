# Marketplace Submission Log

Target marketplace: `anthropics/claude-plugins-community` (and follow-up to `claude-plugins-official/external_plugins/`).

Submission portals (verified 2026-05-16 in Claude Code v2.1.143 plugin docs):
- Claude.ai: https://claude.ai/settings/plugins/submit
- Console: https://platform.claude.com/plugins/submit

Either form routes to the same Anthropic review pipeline. Pick the account you are logged in to.

Plugin version at submission: `1.0.0`
Submission branch: `marketplace/submission-1`

Local plugin-load test (2026-05-16, Claude Code v2.1.143):
- Command: `claude --plugin-dir /home/fer/Documents/llm-dark-patterns -p 'Reply exactly: PLUGIN_LOAD_OK'`
- Result: `PLUGIN_LOAD_OK`, exit 0. Plugin loads cleanly in a fresh workspace.

## Submission record

### v0.1.0 (original, 2026-05-11)
- **Status (dashboard)**: Published as of 2026-05-11
- **Status (live marketplace.json)**: NOT LISTED — verified 2026-05-16 against `https://raw.githubusercontent.com/anthropics/claude-plugins-community/main/.claude-plugin/marketplace.json` (1715 plugins; zero `waitdeadai` source matches; zero `llm-dark-patterns` name matches).
- **Anthropic-side tracking issue**: `anthropics/claude-plugins-official#1887` (opened 2026-05-16, follow-up to closed #1272).
- **End-user effect**: `claude plugin install llm-dark-patterns@claude-community` does not resolve.

### v1.0.0 resubmit (2026-05-16T14:14-03:00 / 17:14 UTC)
- **Status**: SUBMITTED, awaiting Anthropic-side processing
- **Submission timestamp (UTC)**: 2026-05-16T17:14:42Z
- **Form**: in-app via `claude.ai/settings/plugins/submit` or `platform.claude.com/plugins/submit`
- **Confirmation URL or ID**: TBD (operator to paste)
- **Reviewer notes (if any)**: TBD
- **plugin.json commit at submit time**: `77401e2` on `waitdeadai/llm-dark-patterns:main` (v1.0.0, post PR #10 merge)
- **Privacy policy URL given**: `https://github.com/waitdeadai/llm-dark-patterns/blob/main/PRIVACY.md`
- **Platforms claimed**: Claude Code (verified via local `claude --plugin-dir` install + `claude plugin marketplace add waitdeadai/claude-plugins` install)

## Pre-flight (operator runs before submit)

See `SUBMISSION_FORM.md` §Operator pre-flight checklist.

## Post-submission follow-up plan

1. **Standard listing**: monitor for automated-review result. If rejected with notes, fix on `marketplace/submission-1`, push, and resubmit through the same form.
2. **Anthropic Verified badge**: after standard listing lands, request the Verified review. Capture the form/process here.
3. **external_plugins inclusion**: after standard listing lands, request inclusion in `anthropics/claude-plugins-official/external_plugins/` directory. Capture process here.

## Cross-references

- `SPEC-marketplace-submission.md` — slice contract
- `.taste/specqa/marketplace-2026-05-16/spec-qa.md` — Spec QA review
- `SECURITY_AUDIT.md` — per-hook compliance audit
- `SUBMISSION_FORM.md` — content prepared for the live form
- `agent-closeout-bench/.taste/strategic-pivot/2026-05-16/STRATEGIC-PIVOT.md` — strategic context (Z1 → Z4 → Z2 → Z6 sequencing)

## Withdrawal plan

If a critical issue is discovered post-submission:
1. Open an issue in `anthropics/claude-plugins-community` requesting withdrawal.
2. Fix on `marketplace/submission-1`, push.
3. Resubmit via `clau.de/plugin-directory-submission` with the fix.

The repo source remains under `waitdeadai` control regardless of marketplace state.
