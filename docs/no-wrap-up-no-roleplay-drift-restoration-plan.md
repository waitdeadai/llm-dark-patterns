# no-wrap-up / no-roleplay-drift standalone restoration plan

Date: 2026-05-13

## Current remote status

The standalone repos are not currently available under the expected owner:

| Hook | Expected remote | Result |
|---|---|---|
| `no-wrap-up` | `https://github.com/waitdeadai/no-wrap-up.git` | `git ls-remote` returned `Repository not found`; `gh repo view waitdeadai/no-wrap-up` could not resolve the repo |
| `no-roleplay-drift` | `https://github.com/waitdeadai/no-roleplay-drift.git` | `git ls-remote` returned `Repository not found`; `gh repo view waitdeadai/no-roleplay-drift` could not resolve the repo |

Because the remotes do not exist, nothing was cloned into `/home/fer/Documents`.
Both hooks remain umbrella-only legacy implementations in this repo.

## Source of truth to restore from

Use the umbrella implementation as the restoration source:

- `hooks/no-wrap-up.sh`
- `hooks/no-roleplay-drift.sh`
- `tests/stress/no-wrap-up/`
- `tests/stress/no-roleplay-drift/`
- the rows in `README.md`
- the design notes in `METHODOLOGY.md`

Do not copy AgentCloseoutBench physics semantics into these standalone repos.
The standalone repos should remain small Bash/JQ textual hooks. They may link to
the AgentCloseoutBench adapter lane as an optional stricter/research-backed
path, but their hook scripts should not become Rust engine wrappers.

## Restoration sequence

1. Create the GitHub repo:

   ```bash
   gh repo create waitdeadai/no-wrap-up --public --license apache-2.0
   gh repo create waitdeadai/no-roleplay-drift --public --license apache-2.0
   ```

2. Clone each repo under `/home/fer/Documents`.

3. Copy only the standalone hook surface from this umbrella repo:

   ```bash
   cp /home/fer/Documents/llm-dark-patterns/hooks/no-wrap-up.sh /home/fer/Documents/no-wrap-up/no-wrap-up.sh
   cp /home/fer/Documents/llm-dark-patterns/hooks/no-roleplay-drift.sh /home/fer/Documents/no-roleplay-drift/no-roleplay-drift.sh
   ```

4. Add standard standalone repo files modelled after `no-vibes`,
   `no-sycophancy`, and `no-cliffhanger`:

   - `README.md`
   - `RECEIPTS.md`
   - `settings.example.json`
   - `.claude-plugin/plugin.json`
   - `hooks/hooks.json`
   - `.github/workflows/test.yml`

5. Convert umbrella stress fixtures into standalone receipts and CI smoke tests.
   Keep at least positive, negative, edge, malformed JSON, and
   `stop_hook_active` cases when present.

6. Run local fixture tests and JSON validation before publishing.

7. Push each repo, confirm CI, then update `llm-dark-patterns/README.md`:

   - change each table row from `umbrella-only legacy` to the public repo link;
   - add each hook to the standalone install loop only after the public raw URL
     works;
   - keep the AgentCloseoutBench physics-backed lane documented separately.

## Done criteria

- Public remote exists.
- Fresh clone works.
- Hook script is executable.
- README install command downloads the right file.
- `settings.example.json` and plugin manifest point at the standalone script.
- Fixture/receipt tests pass locally and in CI.
- Umbrella docs no longer call the hook umbrella-only legacy.
