# Security Audit — Marketplace Submission v1.0.0

Access date: 2026-05-16
Branch: `marketplace/submission-1`
Hook count: 31 unique scripts wired across all events in `hooks/hooks.json`
Audit method: pattern grep across every wired hook, plus manual review of every flagged hit.

## Compliance summary

| Category | Status | Notes |
|---|---|---|
| `.env` / secrets file reads | **PASS** | All matches are regex patterns *inside* detection logic (the hooks scan model output for mentions of these paths); no hook *reads* `.env`, `.claude/settings.local.json`, or `secrets/`. |
| Network calls (curl, wget, nc, http) | **PASS** | One match in `no-fake-cite.sh` line 67 is a code comment explaining what `curl` would do for a citation check; no actual network call. |
| API key / token reads | **PASS** | One match in `no-credential-leak-in-handoff.sh` line 65 is repair-template text instructing the model how to use `$ANTHROPIC_API_KEY` from env; the hook itself does not read it. |
| Auto-loading skills (`SKILL.md`) | **PASS** | `find . -name SKILL.md` returns zero hits. The plugin ships no auto-loading skill files. |
| Disk writes outside repo | **PASS** | One match in `no-vibes.sh` line 132 is a regex detecting `chmod -R 777` in model output; the hook does not execute it. State machinery hooks (`state-*.sh`) write to `.no-amnesia/state/CURRENT.md` inside the repo, which is the documented state surface. |
| Subprocess `eval` / `exec` shell injection | **PASS** | All `exec` matches are bash redirection forms (`exec >` style) for stdout/stderr handling, not external command execution. No `eval` of user input. |
| `chmod` / `chown` execution | **PASS** | Only as detection regex, not invocation. |
| Trust-pyramid concerns (CVE-2026-21852 class) | **PASS** | Plugin defines no `ANTHROPIC_BASE_URL` override, no MCP server, no pre-trust network request. |

## Per-hook audit (31 wired hooks)

All 31 hooks share a common shape: read JSON payload from stdin via `jq`, apply category-scoped regex matchers to `last_assistant_message` or other event fields, emit a structured BLOCK message to stderr with non-zero exit on match. None of the hooks open files outside the repo or make external calls.

### Stop / SubagentStop closeout hooks (24)
- `honest-eta.sh`, `no-aggregator-hallucination.sh`, `no-ai-tells.sh`, `no-cherry-pick-rollup.sh`, `no-cliffhanger.sh`, `no-curfew.sh`, `no-disclaimer-spam.sh`, `no-emoji-spam.sh`, `no-fake-cite.sh`, `no-fake-recall.sh`, `no-fake-stats.sh`, `no-meta-commentary.sh`, `no-phantom-tool-call.sh`, `no-prompt-restate.sh`, `no-roleplay-drift.sh`, `no-rollback-claim-without-evidence.sh`, `no-sandbagging-disguise.sh`, `no-silent-worker-success.sh`, `no-sycophancy.sh`, `no-tldr-bait.sh`, `no-vibes.sh`, `no-wrap-up.sh`, `state-stop.sh`
- Pattern: stdin JSON → `jq` extract → regex match → emit BLOCK message + exit 2 on match, exit 0 otherwise.
- No file system access beyond reading the stdin payload and (state-stop only) writing `.no-amnesia/state/CURRENT.md`.

### TaskCreated / TaskCompleted multi-agent hooks (3)
- `no-credential-leak-in-handoff.sh`, `no-handoff-loop.sh`, `no-ownership-violation.sh`
- Pattern: same shape; matches against task delegation payload fields.

### PreToolUse / PostToolUse safety hooks (2)
- `no-approval-sneak.sh`, `no-vibes.sh` (also wired at Stop)
- Pattern: same shape; matches against tool-use event payloads.

### State machinery hooks (4)
- `state-precompact.sh`, `state-postcompact.sh`, `state-sessionstart.sh`, plus `state-stop.sh` above
- Pattern: read JSON payload, write or update `.no-amnesia/state/CURRENT.md` inside repo. No external writes.

### Time anchor hook (1)
- `time-anchor.sh`
- Pattern: read local clock, emit current date/time as JSON. No external calls.

## Findings flagged for the marketplace reviewer

None of these are compliance blockers; they are defensive notes the reviewer may ask about.

1. **`no-fake-cite.sh` mentions `curl` in a comment.** The comment explains what a citation-verification tool would do; the hook itself performs no verification (that is by design — verification is the user's job, the hook just flags unverifiable claims). Clarification ready if asked.

2. **`no-credential-leak-in-handoff.sh` mentions `$ANTHROPIC_API_KEY` in repair-template text.** This is the suggested fix language the hook returns when it detects a leaked credential. The hook does not read the env var.

3. **State hooks write inside the repo.** `state-*.sh` writes `.no-amnesia/state/CURRENT.md`. This is the documented continuity surface for the no-amnesia hook family. The path is within the workspace, not outside.

4. **`no-approval-sneak.sh` defines sensitive-path regex defaults for detection.** Operators can extend these patterns at `${XDG_CONFIG_HOME:-$HOME/.config}/llm-dark-patterns/packs/<subdir>/<name>.txt`. This is documented in the README. The hook reads its own pack files only.

## Verdict

All 31 wired hooks pass the security guidance compliance bar for marketplace submission. No hook has been flagged for removal from the bundle.

## Cross-references

- `hooks/hooks.json` — canonical wiring list
- `README.md` §"Threat model" (added 2026-05-16, PR #9 on `docs/threat-model`) — operator-facing summary of these limitations
- `SPEC-marketplace-submission.md` §3 C4 — Security audit success criterion
- Pluto Security extension-ecosystem analysis (cited 2026-05-16): https://pluto.security/blog/claude-extension-ecosystem-security-practitioner-guide/
- CVE-2026-21852 (CVSS 7.5, January 2026): not applicable — plugin defines no `ANTHROPIC_BASE_URL` override
