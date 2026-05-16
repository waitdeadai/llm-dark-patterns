# Draft comment for anthropics/claude-plugins-official#1272

Status: DRAFT — for operator review before posting.

Target: https://github.com/anthropics/claude-plugins-official/issues/1272

Rationale: comment adds (1) one more concrete repro, (2) a "for the next person hitting this" pointer to the self-hosted-marketplace workaround, (3) a polite question whether there is a triage channel beyond the closed thread.

The closed-after-one-user-fix pattern (mercadopago, per terryroach's 2026-05-12 comment) is the political context — keep the comment factual and non-accusatory.

---

## Comment body (paste this)

```
Same pattern here, filed as follow-up at #1887 with the live-marketplace-json grep evidence.

Submission timeline:
- 2026-05-11: submitted `llm-dark-patterns` via `claude.ai/settings/plugins/submit`
- Dashboard status: **Published** since 2026-05-11
- Live `claude-plugins-community/.claude-plugin/marketplace.json` (verified 2026-05-16): 1715 plugins, zero matches for `waitdeadai` source URLs

```bash
curl -fsSL https://raw.githubusercontent.com/anthropics/claude-plugins-community/main/.claude-plugin/marketplace.json \
  | jq '[.plugins[] | select(.source | tostring | test("waitdead"))] | length'
# 0
```

For anyone else reading this with the same Published-but-not-listed state and wanting their plugin installable today: I set up a self-hosted marketplace as a workaround so users can `claude plugin marketplace add waitdeadai/claude-plugins && claude plugin install llm-dark-patterns@waitdeadai-plugins`. The pattern works for any publisher — a single repo with `.claude-plugin/marketplace.json` at root.

Polite ask: if the right channel for triaging stuck submissions is somewhere other than this issue tracker (a support email, a separate form), it would help if Anthropic could point publishers there. The pattern in #1272 / #984 / #1292 / #1597 suggests the issue tracker isn't a reliable triage channel.

Not asking for SLA, just for the address of the right room.
```

---

## Don't post unless you want to

Two reasons to skip posting:

1. Adds another voice to a closed thread, which can read as noise. The fresh issue #1887 already carries our evidence.
2. The political tone of the thread post-closure (terryroach asking Bryan-Anthropic for communication) is mildly fraught. Adding to it could read as piling on.

Two reasons to post:

1. Concrete repro + a working workaround is genuinely useful to other publishers reading the closed thread.
2. The "right channel" question is unanswered and worth surfacing publicly.

Your call. If you want a more concise version, tell me and I'll trim.
