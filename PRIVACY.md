# Privacy Policy

**Effective date:** 2026-05-11
**Last updated:** 2026-05-11
**Maintainer:** waitdeadai (proeliteinterface@gmail.com)
**Canonical URL:** https://restlessmachine.com/privacy
**Mirror:** https://github.com/waitdeadai/no-vibes/blob/main/PRIVACY.md

---

## Scope

This Privacy Policy covers the open-source software projects published under the [waitdeadai](https://github.com/waitdeadai) GitHub account, including but not limited to:

- The **LLM Dark Patterns Hooks** suite — [no-vibes](https://github.com/waitdeadai/no-vibes), [time-anchor](https://github.com/waitdeadai/time-anchor), [no-curfew](https://github.com/waitdeadai/no-curfew), [no-sycophancy](https://github.com/waitdeadai/no-sycophancy), [no-cliffhanger](https://github.com/waitdeadai/no-cliffhanger), [honest-eta](https://github.com/waitdeadai/honest-eta), [no-fake-recall](https://github.com/waitdeadai/no-fake-recall), [no-fake-stats](https://github.com/waitdeadai/no-fake-stats), [no-fake-cite](https://github.com/waitdeadai/no-fake-cite), [no-amnesia](https://github.com/waitdeadai/no-amnesia), and the [llm-dark-patterns](https://github.com/waitdeadai/llm-dark-patterns) umbrella.
- The companion repos [impossible-tasks](https://github.com/waitdeadai/impossible-tasks) and [walkclaude](https://github.com/waitdeadai/walkclaude).
- The [minmaxing](https://github.com/waitdeadai/minmaxing) governance harness.

It applies to people who **install, run, or contribute to** these projects. It does NOT cover:

- Anthropic's Claude Code itself (governed by [Anthropic's Privacy Policy](https://www.anthropic.com/legal/privacy)).
- GitHub itself when you visit the project repositories (governed by [GitHub's Privacy Policy](https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement)).
- Third-party services the operator may integrate (e.g., OpenAI, Deepgram, Cartesia, Ollama in the case of `walkclaude`) — those are governed by their respective providers' policies.

---

## Data the projects collect

**None.**

Every project listed above runs entirely on the operator's local machine. Specifically:

- **The LLM Dark Patterns Hooks** are bash (and one bash + python3) scripts wired into Claude Code's hook events. They read the hook event payload Claude Code passes them via standard input, return a decision via standard error and exit code, and exit. They do not send data anywhere, do not call any external API, do not write telemetry, and do not persist anything beyond what the operator configures (`no-amnesia` writes a local `.no-amnesia/state/CURRENT.md` file as a continuity hint; everything else is stateless).
- **`walkclaude`** runs a local WebRTC voice gateway, a local comms server, and a local parallel-runner CLI. It can optionally use cloud STT/TTS providers (Deepgram, Cartesia, OpenAI Realtime), but only if the operator supplies their own API keys and only by calling those providers directly from the operator's own machine. The maintainer does not receive, see, store, or proxy any of that traffic.
- **`minmaxing`** runs a local governance harness. It writes state to local directories (`.taste/`, `.minimaxing/`) on the operator's machine. No data leaves the operator's machine through this software.
- **`impossible-tasks`** is a static documentation/research catalog (Markdown). It does not execute code.

The maintainer therefore collects **no personal data**, **no telemetry**, **no usage statistics**, **no error reports**, **no crash dumps**, and **no installation pings** through the use of this software.

---

## Data shared with third parties

**None.**

Because the projects collect nothing, there is nothing to share. No data brokers, advertisers, analytics providers, or other third parties receive any data from the maintainer through the use of these projects.

If the operator chooses to integrate optional third-party services (notably the cloud STT/TTS providers in `walkclaude`), data flows directly from the operator's machine to the chosen provider under that provider's privacy policy, with no intermediation by the maintainer.

---

## Data the operator stores locally

Some projects write local files on the operator's machine. These files stay on the operator's machine and are never transmitted to the maintainer:

- **`no-amnesia`** writes `.no-amnesia/state/CURRENT.md` and per-session snapshots under `.no-amnesia/state/snapshots/`, plus a per-day event log under `.no-amnesia/state/events/`. The state engine includes coarse-grained redaction of common secret patterns (`sk-*`, `api_key=`, `bearer`, etc.) before writing, but operators handling especially sensitive sessions should review `.no-amnesia/state/` before sharing the workspace.
- **`walkclaude`** writes per-cycle state under `.walkclaude/hermes-comms/` and `.walkclaude/hermes-parallel/` when the operator runs the comms server or parallel runner.
- **`minmaxing`** writes governance artifacts under `.taste/` and `.minimaxing/`.

All of these directories are gitignored by default and stay on the operator's machine.

---

## Communications

If the operator opens a GitHub issue, pull request, discussion, or sends an email to `proeliteinterface@gmail.com` regarding any of the projects above, the contents of that communication and any associated metadata (GitHub username, email address, IP address as recorded by GitHub or the email provider) are processed by GitHub or the email provider per their respective privacy policies, and retained by the maintainer for the purpose of responding to the communication and maintaining a public record of project contributions.

This processing is done on the legal basis of:

- **Consent** when the operator voluntarily contacts the maintainer.
- **Legitimate interest** in operating an open-source project (per GDPR Art. 6(1)(f) for operators in the European Economic Area or United Kingdom).

The maintainer does not use this contact information for marketing, does not share it with third parties, and does not aggregate it for any purpose other than responding to the communication itself.

---

## Cookies and tracking

The projects above are command-line / library software. They do not use cookies, browser fingerprinting, or any client-side tracking technology.

The maintainer's website at `restlessmachine.com` may set a single first-party preference cookie for theme selection if the visitor changes the default theme. No analytics, advertising, or third-party trackers are used on `restlessmachine.com`.

---

## Children's privacy

The projects above are developer tools intended for technical professional use. They are not directed at children under 16. The maintainer does not knowingly collect personal data from children under 16.

---

## Data subject rights (GDPR / UK GDPR / equivalent regimes)

For operators in the European Economic Area, United Kingdom, California, or other jurisdictions with data-subject-rights regimes, the maintainer recognizes the rights to:

- **Access** any personal data the maintainer holds about you.
- **Rectify** inaccurate personal data.
- **Erase** ("right to be forgotten") personal data.
- **Restrict** or **object to** processing.
- **Portability** of personal data in a structured machine-readable format.
- **Withdraw consent** at any time where processing relies on consent.
- **Lodge a complaint** with a supervisory authority.

Because the only personal data the maintainer holds is communications the operator has voluntarily initiated (GitHub interactions or emails), exercising these rights is straightforward: open a GitHub issue against the relevant repository or email `proeliteinterface@gmail.com`. Requests will be addressed within 30 days.

---

## Security

The projects above run with the privileges of the operator's account on the operator's machine. The maintainer takes the following measures:

- Source code is published in full and version-controlled via GitHub. Every change is publicly auditable.
- Each repository ships a permissive open-source license (Apache-2.0) with no telemetry-permission clauses.
- Dependencies are minimized: most hooks depend only on `bash` and `jq` (or `python3`) — there is no transitive dependency tree to audit.
- The hook scripts do not require elevated privileges and do not modify the operator's system outside the scope the operator explicitly grants via Claude Code's hook configuration.
- CI workflows (where present) run only published-source tests with no secrets; no credentials are stored in any repository.

The maintainer cannot guarantee that operating-system-level vulnerabilities, network-level interception of operator-initiated cloud API calls, or compromises of the operator's own machine are prevented by these projects. Operators should follow normal software-security hygiene.

---

## Changes to this Privacy Policy

This policy may be updated. The "Last updated" date at the top of this document reflects the most recent change. For material changes, the maintainer will publish a notice on the relevant repository's release notes.

Past versions of this policy are tracked in the Git history of `https://github.com/waitdeadai/no-vibes/commits/main/PRIVACY.md` (mirror) and `https://restlessmachine.com/privacy/changelog` (canonical).

---

## Contact

For privacy questions or to exercise data-subject rights:

- **Email:** proeliteinterface@gmail.com
- **GitHub:** open an issue at the relevant repository under https://github.com/waitdeadai
- **Mail:** (omitted by maintainer preference; available on request)

---

*This Privacy Policy is published in plain English to be easily understood by the operators who actually use the software, in accordance with the readability principle in GDPR Art. 12.*
