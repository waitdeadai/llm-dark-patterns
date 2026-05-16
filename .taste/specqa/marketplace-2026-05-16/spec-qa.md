# Spec QA: Marketplace Submission

Run ID: `marketplace-2026-05-16`
Access date: 2026-05-16
SPEC reviewed: `SPEC-marketplace-submission.md`

## Reviewer Identity Status

- requested_reviewer: `claude-opus-4-7` (per `/opussonnet` contract)
- proven_reviewer: `insufficient_data` (no `/status` run, no sentinel)
- reviewer_action: inline review with downgraded confidence; do not claim Opus 4.7 reviewed.

## Critical Findings

**Status**: 0 critical findings.

## Major Findings

### M1. Submission form fields are an unknown unknown
The SPEC §6 Task 5 drafts submission content but the exact field list of `clau.de/plugin-directory-submission` is not documented in the public Anthropic plugin docs. The form likely requires fields we have not pre-drafted (categories, possibly a screenshot, possibly contact details).

**Action**: at start of Task 5, briefly view the live form (operator can navigate to it and screenshot the field list) before drafting content. If the form blocks unauthenticated viewing, draft a superset of plausible fields based on typical marketplace submission patterns and revise after operator opens the form.

### M2. "Anthropic Verified" badge path is opaque
`SPEC` §4 lists Verified badge upgrade as out-of-scope, which is correct. But the badge process is undocumented externally. We may discover at submission time that there is a separate Verified-tier application form, in which case we should record that detail in `MARKETPLACE_SUBMISSION_LOG.md` for the next slice.

### M3. Plugin install command in §3 C3 may be incorrect
The SPEC says `claude plugin marketplace add waitdeadai/llm-dark-patterns` for end-to-end install verification. The community marketplace install pattern from the `claude-plugins-community` README is `claude plugin marketplace add anthropics/claude-plugins-community` followed by `claude plugin install <plugin-name>@claude-community`. Direct-from-org install may not be the current canonical pattern.

**Action**: Task 1 verifies the correct local-development install command (likely `claude plugin install /path/to/llm-dark-patterns` or similar) and updates §3 C3.

## Minor Findings

### m1. Version bump to 1.0.0 is operator-confirmed but not yet decided
Listed as operator decision in Task 3. Should be confirmed in the plan-mode checkpoint, not at execution time, to avoid a packaging revision in the middle of the slice.

### m2. The SPEC mentions 28 wired hooks, repo has 34 hook files
The discrepancy is benign — 28 are wired into `hooks.json`, 34 exist on disk (6 are legacy / not bundled / state machinery). Security audit Task 2 should cover only the 28 wired ones, since unbundled hooks are not part of the marketplace surface. Clarify wording in §6 Task 2.

### m3. The `MARKETPLACE_SUBMISSION_LOG.md` file is referenced repeatedly but never templated
A template stub in `MARKETPLACE_SUBMISSION_LOG.md` is a small added scope, useful for keeping submission state durable.

### m4. README Install snippet (§6 Task 3) may already exist
The existing README has install instructions for standalone hooks. The marketplace install snippet is a different surface. Task 3 should add the marketplace command without removing the standalone-hooks instructions.

### m5. The SPEC does not mention testing the `.claude-plugin/plugin.json` `commands` or `agents` fields
If marketplace listings expect declarative commands/agents/skills entries beyond hooks, plugin.json may need additional fields. Task 1 should check this when it reads the current schema.

## Improvement Suggestions

1. Add a §11 "Pre-flight checklist" mirroring the agent-closeout-bench `SUBMISSION_LOG.md` pattern. Reduces miss risk when operator clicks Submit.
2. Add a "First-week checkpoint" inside §6: end of Day 1, confirm Task 2 surfaced no security audit blockers before scheduling operator's Submit click.
3. Consider committing `SUBMISSION_FORM.md` (Task 5 output) before operator opens the form, so the diff history captures the exact submitted content for reproducibility.
4. The strategic pivot artifact mentions Z4 (Verified badge) as the immediate next slice after Z1. The submission log should explicitly record the planned Verified follow-up — already in §6 Task 7.

## Currentness Source Ledger

- `clau.de/plugin-directory-submission` — verified as canonical submission portal via README of `claude-plugins-community` (live 2026-05-16)
- `claude.com/plugins/security-guidance` — page is the *Security Guidance* plugin product page, NOT the submission requirements doc; deep read at Task 2 will surface gaps
- `plugin.json` schema fields — not directly documented at a single URL; will pull from current `claude-plugins-official` examples at Task 1 via GitHub
- Plugin version conventions — no public guidance; operator picks
- Anthropic Verified badge criteria — undocumented externally as of access date

## Execution Decision

**ALLOWED**: execution may proceed past the plan-mode checkpoint after explicit operator approval of (i) the slice scope, (ii) the version bump target, (iii) the branch name (`marketplace/submission-1`).

**Confidence**: medium. Downgrade reasons: M1 (submission form is unknown), M2 (Verified badge path opaque), M3 (install command pattern uncertain — Task 1 verifies).

**Block conditions** (would flip ALLOWED → BLOCKED during Task 1/2):
- Security audit (Task 2) surfaces a hook that reads `.env` or `.claude/settings.local.json` or makes a network call — must remove from bundle or fix before submission.
- Live marketplace schema requires a field we cannot supply without operator (e.g., a screenshot of the plugin in action).
- `tests` CI on `marketplace/submission-1` branch goes red on the bumped plugin.json or any audit-driven change.

## Outcome

ALLOWED pending operator confirmation of version target (suggest `1.0.0`) and branch name (`marketplace/submission-1`).
