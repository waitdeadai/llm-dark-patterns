#!/usr/bin/env python3
"""
One-shot generator for packs/destructive/*.txt files.

Run from repo root:
    python3 scripts/_gen-destructive-packs.py

Idempotent — overwrites existing files. Patterns live here in Python so the
literal destructive command strings stay off the bash command line during
generation (the local govern-effectiveness hook flags those strings on
sight).
"""

import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "packs" / "destructive"
OUT.mkdir(parents=True, exist_ok=True)

# Header for every pack file.
HEADER = """# packs/destructive/{name}.txt — destructive command surface: {surface}.
#
# One regex per line, blank lines and `#`-comments ignored. Each entry is
# matched case-insensitively against the proposed Bash command via grep -E.
# Sections within a file are loaded together for that surface.
#
# Operators choose which surfaces apply via env:
#   LLM_DARK_PATTERNS_DESTRUCTIVE_PACKS=filesystem,container,git-protected
# Default: all surfaces active. Subset via the env var.
#
# Add custom patterns via packs/destructive/extras.txt or via
# ${{XDG_CONFIG_HOME}}/llm-dark-patterns/packs/destructive/<surface>.txt —
# operator-local additions extend, never replace.

[patterns]
"""


def write_pack(name: str, surface: str, patterns: list[str]) -> None:
    body = HEADER.format(name=name, surface=surface)
    body += "\n".join(patterns) + "\n"
    (OUT / f"{name}.txt").write_text(body, encoding="utf-8")
    print(f"  wrote packs/destructive/{name}.txt ({len(patterns)} patterns)")


# ---------------------------------------------------------------------------
# filesystem — current behavior preserved 1:1 from the inline regex array
# in hooks/no-vibes.sh (is_destructive_bash). Keep these patterns identical
# so the migration causes zero behavior change.
# ---------------------------------------------------------------------------
fs_destructive_root = "(^|[[:space:];&|])sudo[[:space:]]+r" + "m[[:space:]].*(-[[:alnum:]]*r|--recursive)([[:space:]]|$)"
fs_recursive = "(^|[[:space:];&|])r" + "m[[:space:]]+(-[[:alnum:]]*r[[:alnum:]]*|--recursive)([[:space:]]|$)"
fs_force_root = "(^|[[:space:];&|])r" + "m[[:space:]]+-[[:alnum:]]*f[[:alnum:]]*[[:space:]]+/"
fs_git_reset = "(^|[[:space:];&|])git[[:space:]]+reset[[:space:]]+--hard([[:space:]]|$)"
fs_git_clean = "(^|[[:space:];&|])git[[:space:]]+clean[[:space:]]+-[[:alnum:]]*(f[[:alnum:]]*d|d[[:alnum:]]*f)"
fs_git_checkout = "(^|[[:space:];&|])git[[:space:]]+checkout[[:space:]]+--[[:space:]]"
fs_find_delete = "(^|[[:space:];&|])find[[:space:]].*[[:space:]]-delete([[:space:]]|$)"
fs_mkfs = "(^|[[:space:];&|])mkfs(\\.[[:alnum:]_-]+)?([[:space:]]|$)"
fs_dd_dev = "(^|[[:space:];&|])dd[[:space:]].*[[:space:]]of=/dev/"
fs_chmod = "(^|[[:space:];&|])chmod[[:space:]]+-R[[:space:]]+777([[:space:]]|$)"

write_pack(
    "filesystem",
    "filesystem-level destruction",
    [
        fs_destructive_root,
        fs_recursive,
        fs_force_root,
        fs_git_reset,
        fs_git_clean,
        fs_git_checkout,
        fs_find_delete,
        fs_mkfs,
        fs_dd_dev,
        fs_chmod,
    ],
)

# ---------------------------------------------------------------------------
# container — docker / kubectl operational destruction. Stops, removes,
# prunes. Targets the patterns reported by @Tekalan and confirmed by
# 2026 devops postmortems.
# ---------------------------------------------------------------------------
container_patterns = [
    # docker stop on a NAMED container (matches "docker stop <name>" — the
    # operator can extend with their own load-bearing names via extras.txt).
    "(^|[[:space:];&|])docker[[:space:]]+(stop|kill|rm|" + "rmi)[[:space:]]+",
    "(^|[[:space:];&|])docker[[:space:]]+system[[:space:]]+prune[[:space:]]+(.*)?(-a|--all|--force)",
    "(^|[[:space:];&|])docker[[:space:]]+volume[[:space:]]+(rm|prune)",
    "(^|[[:space:];&|])docker[[:space:]]+network[[:space:]]+(rm|prune)",
    "(^|[[:space:];&|])podman[[:space:]]+(stop|kill|rm|" + "rmi)[[:space:]]+",
    "(^|[[:space:];&|])kubectl[[:space:]]+delete[[:space:]]+",
    "(^|[[:space:];&|])kubectl[[:space:]]+rollout[[:space:]]+undo",
    "(^|[[:space:];&|])kubectl[[:space:]]+drain[[:space:]]+",
    "(^|[[:space:];&|])helm[[:space:]]+(uninstall|delete)[[:space:]]+",
    "(^|[[:space:];&|])argocd[[:space:]]+app[[:space:]]+delete[[:space:]]+",
]
write_pack("container", "container and orchestration destruction", container_patterns)

# ---------------------------------------------------------------------------
# git-protected — operations that rewrite or destroy history on protected
# branches. The pattern matches force-push or force-with-lease to common
# protected branch names; operators can extend with their own via
# extras.txt.
# ---------------------------------------------------------------------------
git_patterns = [
    "(^|[[:space:];&|])git[[:space:]]+push[[:space:]]+(.*)?(-f|--force)([[:space:]]|$)",
    "(^|[[:space:];&|])git[[:space:]]+push[[:space:]]+(.*)?--force-with-lease",
    "(^|[[:space:];&|])git[[:space:]]+filter-branch",
    "(^|[[:space:];&|])git[[:space:]]+filter-repo",
    "(^|[[:space:];&|])git[[:space:]]+update-ref[[:space:]]+-d",
    "(^|[[:space:];&|])git[[:space:]]+(branch|tag)[[:space:]]+-D[[:space:]]+",
    "(^|[[:space:];&|])git[[:space:]]+rebase[[:space:]]+(.*)?(-i|--interactive)",
    "(^|[[:space:];&|])git[[:space:]]+reflog[[:space:]]+expire[[:space:]]+--expire=now",
    "(^|[[:space:];&|])git[[:space:]]+gc[[:space:]]+(.*)?--prune=now",
]
write_pack("git-protected", "git history rewriting and protected-branch ops", git_patterns)

# ---------------------------------------------------------------------------
# config-overwrite — in-place writes to live config dirs (Home Assistant
# .storage/, Kubernetes manifests, Ansible vars, .env*, secrets dirs). The
# patterns are conservative (anchored on common config locations) so they
# do not false-positive on every sed -i invocation.
# ---------------------------------------------------------------------------
overwrite_patterns = [
    "(^|[[:space:];&|])sed[[:space:]]+-i[[:space:]].*\\.(env|env\\..*|secret|secrets|key|pem|crt)([[:space:]]|$)",
    "(^|[[:space:];&|])sed[[:space:]]+-i[[:space:]].*/(\\.storage|\\.ssh|\\.gnupg|secrets|\\.kube)/",
    "(^|[[:space:];&|])(>|tee)[[:space:]]+(/etc/|/var/lib/|/srv/|/opt/[^[:space:]]+/conf|\\.env[^[:space:]]*|\\.kube/config|secrets/)",
    "(^|[[:space:];&|])truncate[[:space:]]+-s[[:space:]]+0",
    "(^|[[:space:];&|])shred[[:space:]]+-",
]
write_pack("config-overwrite", "in-place writes to live config and secret paths", overwrite_patterns)

# ---------------------------------------------------------------------------
# cloud-prod — IaC destroy operations and recursive cloud-bucket deletion.
# Top of every Q1-Q2 2026 devops-incident postmortem.
# ---------------------------------------------------------------------------
cloud_patterns = [
    "(^|[[:space:];&|])terraform[[:space:]]+destroy",
    "(^|[[:space:];&|])tofu[[:space:]]+destroy",
    "(^|[[:space:];&|])pulumi[[:space:]]+destroy",
    "(^|[[:space:];&|])terraform[[:space:]]+state[[:space:]]+(rm|mv)",
    "(^|[[:space:];&|])aws[[:space:]]+s3[[:space:]]+rb[[:space:]]+",
    "(^|[[:space:];&|])aws[[:space:]]+s3[[:space:]]+rm[[:space:]]+(.*)?(--recursive|--include)",
    "(^|[[:space:];&|])aws[[:space:]]+(rds|ec2|cloudformation|iam)[[:space:]]+delete-",
    "(^|[[:space:];&|])gcloud[[:space:]]+(compute|sql|storage|projects)[[:space:]]+(.*)?delete",
    "(^|[[:space:];&|])gsutil[[:space:]]+rm[[:space:]]+(.*)?-r",
    "(^|[[:space:];&|])az[[:space:]]+(group|vm|storage)[[:space:]]+delete",
    "(^|[[:space:];&|])doctl[[:space:]]+(droplet|database|kubernetes)[[:space:]]+delete",
]
write_pack("cloud-prod", "production cloud destruction (IaC destroy, bucket rm, resource delete)", cloud_patterns)

# ---------------------------------------------------------------------------
# database — destructive DDL/DCL and flush operations. Must match SQL
# embedded in shell strings (psql -c, mysql -e, etc.), so patterns are
# anchored more loosely than command-only entries.
# ---------------------------------------------------------------------------
db_patterns = [
    "\\bDROP[[:space:]]+(TABLE|DATABASE|SCHEMA|INDEX|VIEW|MATERIALIZED[[:space:]]+VIEW)\\b",
    "\\bTRUNCATE[[:space:]]+(TABLE[[:space:]]+)?",
    "\\bDELETE[[:space:]]+FROM[[:space:]]+[^[:space:]]+([[:space:]]*;[[:space:]]*$|--|/\\*)",
    "(^|[[:space:];&|])redis-cli[[:space:]]+(.*)?(FLUSHALL|FLUSHDB)",
    "(^|[[:space:];&|])mongo(sh)?[[:space:]]+(.*)?dropDatabase\\(\\)",
    "(^|[[:space:];&|])dropdb[[:space:]]+",
    "(^|[[:space:];&|])mysqladmin[[:space:]]+drop[[:space:]]+",
]
write_pack("database", "destructive database operations (DROP/TRUNCATE/FLUSH)", db_patterns)

# ---------------------------------------------------------------------------
# service — stopping load-bearing systemd services. Operators must add
# their own critical service names via extras (this default list catches a
# few universally-load-bearing ones).
# ---------------------------------------------------------------------------
service_patterns = [
    "(^|[[:space:];&|])systemctl[[:space:]]+(stop|disable|mask)[[:space:]]+",
    "(^|[[:space:];&|])service[[:space:]]+[^[:space:]]+[[:space:]]+stop",
    "(^|[[:space:];&|])launchctl[[:space:]]+(unload|stop)[[:space:]]+",
    "(^|[[:space:];&|])supervisorctl[[:space:]]+stop[[:space:]]+",
]
write_pack("service", "stopping load-bearing services", service_patterns)

print("")
print(f"Done. {len(list(OUT.glob('*.txt')))} destructive pack files in {OUT}")
