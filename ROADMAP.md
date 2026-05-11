# Roadmap

The shape of the next refactor, driven by the first round of substantive
external feedback ([@Tekalan in anthropics/claude-code#57661](https://github.com/anthropics/claude-code/issues/57661#issuecomment-4418038561)).

This document is the canonical spec for the loadable-packs architecture
that several open issues depend on. Issues link back here.

## North-star: zero forking required

The current shape inlines vocabulary (closeout verbs, evidence binaries,
destructive commands) into every hook script's regex literals. That works
for the smallest demo case but breaks down the moment an operator is:

- Working in a non-English language (Polish, Spanish, German, French, ...)
- Working on infra/devops (docker, kubectl, terraform, ansible, helm, ...)
- Operating a load-bearing service that has its own destructive vocabulary
  (Home Assistant config dirs, k8s namespaces, prod databases, ...)

Operators are forking and editing the regex by hand. That is the wrong
architecture. The loadable-packs design moves all locale-specific,
toolchain-specific, and surface-specific data **out of the hook scripts**
and into flat files the operator (or contributor) can extend without
touching bash.

## Pack types

Three pack types, each with the same shape:

```
packs/
  locale/                       # vocabulary for matching model output
    en.txt                      # current English vocab, extracted
    es.txt                      # Spanish
    pl.txt                      # Polish (per Tekalan's report)
    de.txt                      # German
    fr.txt                      # French
    pt.txt                      # Portuguese
    ...
  evidence/                     # binaries that count as command evidence
    binaries.txt                # one binary per line, grouped by section
  destructive/                  # destructive command surfaces
    filesystem.txt              # current behavior (recursive deletion etc.)
    container.txt               # docker / kubectl destruction
    git-protected.txt           # force-push to main, filter-branch, etc.
    config-overwrite.txt        # in-place edits against live config dirs
    cloud-prod.txt              # cloud-provider destruction
    database.txt                # DROP / TRUNCATE / FLUSHALL
    service.txt                 # systemctl stop critical services
```

## Pack file format

Plain text, one entry per line, blank lines and `#`-comments allowed.
Section headers in `[brackets]` for grouping when relevant.

```
# packs/locale/es.txt
# Spanish vocabulary for the LLM Dark Patterns hooks suite.
# Maintained by community contributors.

[positive_closeout]
listo
hecho
implementado
terminado
completado
funciona

[failed_verification]
no probado
sin verificar
falló la verificación

[evidence]
verificación: pasada
ejecutado:
salida:
```

```
# packs/evidence/binaries.txt
# Binaries that count as command evidence in `has_command_evidence`.

[app-dev]
bash
git
npm
pnpm
yarn
pytest
python3
ruff
cargo
go
make

[devops]
docker
kubectl
terraform
ansible
helm
nomad
consul
vault

[shell-tools]
jq
sed
awk
rsync
find
grep

[system]
systemctl
journalctl
lsblk
ip
iptables

[cloud]
aws
gcloud
az

[database]
psql
mysql
redis-cli
mongosh
```

## Pack loading

Hooks load packs once per invocation, in priority order:

1. `LLM_DARK_PATTERNS_PACK_DIR` env var → directory containing override packs
2. `~/.config/llm-dark-patterns/packs/` → operator-local packs (gitignored)
3. The repo's `packs/` directory → defaults that ship with the suite

Operator opts in/out of categories via env:

- `LLM_DARK_PATTERNS_LOCALE=en,es,pl` → which locale packs to load
- `LLM_DARK_PATTERNS_EVIDENCE_CATEGORIES=app-dev,devops,k8s` → subset of binaries
- `LLM_DARK_PATTERNS_DESTRUCTIVE_PACKS=filesystem,container,git-protected` → which surfaces

Auto-detect locale from `LANG`/`LC_ALL` if `LLM_DARK_PATTERNS_LOCALE` unset.
Default to `en` if both unset.

## Hook script changes

Each hook gains a `load_pack()` helper at the top:

```bash
load_pack() {
  local kind="$1"   # locale | evidence | destructive
  local name="$2"   # e.g. "es", "binaries", "container"
  for dir in \
    "${LLM_DARK_PATTERNS_PACK_DIR:-}" \
    "${HOME}/.config/llm-dark-patterns/packs" \
    "$(dirname "$0")/../packs" ; do
    [ -z "$dir" ] && continue
    local file="${dir}/${kind}/${name}.txt"
    if [ -f "$file" ]; then
      grep -Ev '^[[:space:]]*(#|$)' "$file"
      return 0
    fi
  done
  return 1
}
```

Hook regexes are built from the loaded pack lines (joined with `|` for
alternation). The result is the same kind of regex that's currently
hardcoded — only the source moves out of the script.

## Migration plan

The refactor preserves existing behavior. No fixture should regress.

Phased rollout:

1. **Phase 1 — extract the existing English vocab** into `packs/locale/en.txt`.
   Hook scripts load `en.txt` instead of inlining. All 168 stress fixtures
   continue to pass.
2. **Phase 2 — add second locale**. Ship `packs/locale/es.txt` (Spanish, big
   community) and add Spanish stress fixtures alongside the English ones.
3. **Phase 3 — externalize evidence binaries** into `packs/evidence/binaries.txt`
   with section headers. Add devops/cloud/database/system fixtures.
4. **Phase 4 — externalize destructive commands** into surface-specific packs.
   Add per-surface fixtures.
5. **Phase 5 — hardening** for the two bypasses ([#4](https://github.com/waitdeadai/llm-dark-patterns/issues/4),
   [#5](https://github.com/waitdeadai/llm-dark-patterns/issues/5)) — proximity
   bound on `has_command_evidence`, clause-local negation in
   `has_positive_closeout`. New stress fixtures for both.

Each phase is its own PR with its own stress fixtures and verification.

## Open issues this roadmap addresses

- [#1](https://github.com/waitdeadai/llm-dark-patterns/issues/1) i18n locale packs (Phase 1, 2)
- [#2](https://github.com/waitdeadai/llm-dark-patterns/issues/2) External evidence binary allowlist (Phase 3)
- [#3](https://github.com/waitdeadai/llm-dark-patterns/issues/3) External destructive command packs (Phase 4)
- [#4](https://github.com/waitdeadai/llm-dark-patterns/issues/4) `has_command_evidence` proximity bypass (Phase 5)
- [#5](https://github.com/waitdeadai/llm-dark-patterns/issues/5) `has_positive_closeout` negation early-return bypass (Phase 5)

## Non-goals (explicitly)

- Writing a YAML/JSON pack format. Plain text with section headers is enough
  and stays diff-friendly.
- Replacing `bash + jq` with a different runtime. The out-of-band, non-LLM
  judge is the design point of the suite.
- Per-binary regex sophistication. Substring/word match is enough; binaries
  in backticks are unambiguous.
- LLM-based pack generation or maintenance. Packs are human-edited;
  community PRs add new locales/surfaces. The model never decides what
  vocabulary the model gets judged against.

## How to contribute a new pack

1. Open a PR adding `packs/<kind>/<name>.txt`
2. Add at least one positive stress fixture under `tests/stress/<hook>/positive/`
   that exercises the new pack
3. Update `tests/stress/_gen_fixtures.py` if the new fixture follows a
   regular pattern, or commit the JSON directly
4. Verify locally: `bash tests/stress/run.sh`
5. README update in the same PR with the new pack listed
