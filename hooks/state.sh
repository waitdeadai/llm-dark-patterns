#!/bin/bash
# no-amnesia working state CLI
# Keeps a compact, compaction-safe handoff for the current task.

set -euo pipefail

COMMAND="${1:-status}"
ROOT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

if [ ! -d "$ROOT_DIR" ]; then
  ROOT_DIR="$(pwd)"
fi

cd "$ROOT_DIR"

STATE_DIR="${NO_AMNESIA_STATE_DIR:-$ROOT_DIR/.no-amnesia/state}"
mkdir -p "$STATE_DIR/events" "$STATE_DIR/snapshots"

INPUT_FILE="$(mktemp)"
cleanup() {
  rm -f "$INPUT_FILE"
}
trap cleanup EXIT

if [ -t 0 ]; then
  printf '{}\n' > "$INPUT_FILE"
else
  cat > "$INPUT_FILE"
  if [ ! -s "$INPUT_FILE" ]; then
    printf '{}\n' > "$INPUT_FILE"
  fi
fi

python3 - "$COMMAND" "$ROOT_DIR" "$STATE_DIR" "$INPUT_FILE" <<'PY'
import collections
import datetime as dt
import glob
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import time


COMMAND = sys.argv[1]
ROOT = pathlib.Path(sys.argv[2]).resolve()
STATE_DIR = pathlib.Path(sys.argv[3]).resolve()
INPUT_FILE = pathlib.Path(sys.argv[4])
CURRENT = STATE_DIR / "CURRENT.md"
EVENTS_DIR = STATE_DIR / "events"
SNAPSHOTS_DIR = STATE_DIR / "snapshots"


def read_input() -> dict:
    try:
        raw = INPUT_FILE.read_text()
        return json.loads(raw) if raw.strip() else {}
    except Exception:
        return {}


def run_git(args: list[str]) -> str:
    try:
        result = subprocess.run(
            ["git", *args],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except FileNotFoundError:
        return ""
    return result.stdout.strip()


def redact(value: object) -> str:
    text = "" if value is None else str(value)
    replacements = [
        (re.compile(r"sk-cp-[A-Za-z0-9_\-]{12,}"), "sk-cp-[REDACTED]"),
        (re.compile(r"sk-[A-Za-z0-9_\-]{12,}"), "sk-[REDACTED]"),
        (
            re.compile(
                r"(?i)\b(api[_-]?key|auth[_-]?token|bearer|password|secret)\b"
                r"([\"']?\s*[:=]\s*[\"']?)([^\"'\s,}]+)"
            ),
            r"\1\2[REDACTED]",
        ),
    ]
    for pattern, repl in replacements:
        text = pattern.sub(repl, text)
    return text


def truncate(text: object, limit: int = 900) -> str:
    clean = redact(text).strip()
    if len(clean) <= limit:
        return clean
    return clean[: limit - 24].rstrip() + "\n...[truncated]"


def latest_workflow_artifact() -> str:
    paths = glob.glob(str(ROOT / ".taste" / "workflow-runs" / "*-workflow.md"))
    if not paths:
        return "none"
    latest = max(paths, key=lambda p: pathlib.Path(p).stat().st_mtime)
    return os.path.relpath(latest, ROOT)


def latest_spec_archive() -> str:
    paths = glob.glob(str(ROOT / ".taste" / "specs" / "*.md"))
    if not paths:
        return "none"
    latest = max(paths, key=lambda p: pathlib.Path(p).stat().st_mtime)
    return os.path.relpath(latest, ROOT)


def path_status(path: str) -> str:
    return "present" if (ROOT / path).exists() else "missing"


def read_recent_transcript(path_value: str, limit: int = 120) -> tuple[str, str]:
    if not path_value:
        return "", ""

    transcript = pathlib.Path(os.path.expanduser(path_value))
    if not transcript.exists() or not transcript.is_file():
        return "", ""

    lines: collections.deque[str] = collections.deque(maxlen=limit)
    try:
        with transcript.open("r", encoding="utf-8", errors="replace") as handle:
            for line in handle:
                lines.append(line)
    except Exception:
        return "", ""

    last_user = ""
    last_assistant = ""

    for line in lines:
        try:
            item = json.loads(line)
        except Exception:
            continue

        role = item.get("role") or item.get("type") or ""
        message = item.get("message")
        if isinstance(message, dict):
            role = message.get("role") or role
            content = message.get("content")
        else:
            content = item.get("content") or item.get("text") or item.get("prompt")

        text = extract_text(content)
        if not text:
            continue

        if role == "user":
            last_user = text
        elif role == "assistant":
            last_assistant = text

    return truncate(last_user, 900), truncate(last_assistant, 900)


def extract_text(value: object, depth: int = 0) -> str:
    if depth > 4 or value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return "\n".join(filter(None, (extract_text(v, depth + 1) for v in value)))
    if isinstance(value, dict):
        if value.get("type") == "tool_result":
            return ""
        if isinstance(value.get("text"), str):
            return value["text"]
        if isinstance(value.get("content"), (str, list, dict)):
            return extract_text(value["content"], depth + 1)
        if isinstance(value.get("message"), (str, list, dict)):
            return extract_text(value["message"], depth + 1)
    return ""


def rel_paths_from_status(status: str) -> list[str]:
    paths: list[str] = []
    for line in status.splitlines():
        if not line.strip():
            continue
        raw = line[3:] if len(line) > 3 else line
        if " -> " in raw:
            raw = raw.split(" -> ", 1)[1]
        paths.append(raw.strip())
    return paths[:80]


def state_payload(input_data: dict) -> dict:
    now_local_dt = dt.datetime.now(dt.timezone.utc).astimezone()
    now_utc_dt = now_local_dt.astimezone(dt.timezone.utc)
    now = now_local_dt.isoformat(timespec="seconds")
    status = run_git(["status", "--short"])
    branch = run_git(["branch", "--show-current"]) or "unknown"
    head = run_git(["rev-parse", "--short", "HEAD"]) or "unknown"
    session_id = redact(input_data.get("session_id", "unknown"))
    event = input_data.get("hook_event_name", COMMAND)
    trigger = input_data.get("trigger") or input_data.get("source") or ""
    transcript_path = input_data.get("transcript_path", "")
    last_user, transcript_assistant = read_recent_transcript(transcript_path)
    last_assistant = input_data.get("last_assistant_message") or transcript_assistant
    compact_summary = input_data.get("compact_summary", "")
    files = rel_paths_from_status(status)

    return {
        "updated_at": now,
        "current_local_time": now_local_dt.isoformat(timespec="seconds"),
        "current_utc_time": now_utc_dt.isoformat(timespec="seconds"),
        "current_timezone": f"{now_local_dt.tzname() or 'unknown'} ({now_local_dt.strftime('%z')})",
        "current_local_date": now_local_dt.date().isoformat(),
        "current_local_hour": now_local_dt.strftime("%H:%M:%S"),
        "event": event,
        "command": COMMAND,
        "trigger": redact(trigger),
        "session_id": session_id,
        "transcript_path": redact(transcript_path),
        "git_branch": redact(branch),
        "git_head": redact(head),
        "git_status": "clean" if not status else redact(status),
        "git_status_count": len(status.splitlines()) if status else 0,
        "spec_status": path_status("SPEC.md"),
        "latest_spec_archive": latest_spec_archive(),
        "taste_status": f"taste.md {path_status('taste.md')}, taste.vision {path_status('taste.vision')}",
        "latest_workflow_artifact": latest_workflow_artifact(),
        "files_in_play": files,
        "last_user": input_data.get("prompt") or last_user,
        "last_assistant": last_assistant,
        "compact_summary": compact_summary,
    }


def markdown(payload: dict) -> str:
    files = payload["files_in_play"]
    file_lines = "\n".join(f"- {redact(path)}" for path in files) if files else "- none detected"
    compact = truncate(payload["compact_summary"], 3500) if payload.get("compact_summary") else "none recorded"
    last_user = truncate(payload["last_user"], 1200) or "none detected"
    last_assistant = truncate(payload["last_assistant"], 1200) or "none detected"

    return f"""# Current Working State

Generated by minmaxing. Keep this file compact; it is rehydrated after Claude Code startup, resume, and compaction.

updated_at: {payload['updated_at']}
event: {redact(payload['event'])}
trigger: {payload['trigger'] or 'none'}
session_id: {payload['session_id']}
git_branch: {payload['git_branch']}
git_head: {payload['git_head']}
git_status_count: {payload['git_status_count']}

## Temporal Anchor
- Local system-clock time: {payload['current_local_time']}
- UTC time: {payload['current_utc_time']}
- Timezone: {payload['current_timezone']}
- Local date: {payload['current_local_date']}
- Local hour: {payload['current_local_hour']}
- Research rule: resolve relative dates against this anchor. For current,
  latest, recent, SOTA 2026, pricing, models, APIs, docs, benchmarks, laws,
  schedules, or news, verify live sources and cite source dates/access date
  instead of relying on pretrained memory.

## Source Of Truth
- SPEC.md: {payload['spec_status']}
- Latest archived spec: {payload['latest_spec_archive']}
- Taste kernel: {payload['taste_status']}
- Latest workflow artifact: {payload['latest_workflow_artifact']}
- Durable memory: use `bash scripts/memory.sh recall "<task>" --depth medium`

## Active Signals
Last user request:
{last_user}

Last assistant closeout:
{last_assistant}

## Files In Play
{file_lines}

## Git Status
```text
{payload['git_status']}
```

## Last Compact Summary
{compact}

## Rehydrate Instructions
1. Treat this as working state, not durable memory.
2. Reconcile it with live `git status`, `SPEC.md`, and the latest workflow artifact before editing.
3. Preserve user-owned changes and refresh stale assumptions before continuing.
4. Move durable lessons into `bash scripts/memory.sh add ...`; keep ephemeral task progress here.
"""


def append_event(payload: dict) -> None:
    EVENTS_DIR.mkdir(parents=True, exist_ok=True)
    event_path = EVENTS_DIR / f"{dt.date.today().isoformat()}.jsonl"
    event = {
        "timestamp": payload["updated_at"],
        "event": payload["event"],
        "command": COMMAND,
        "trigger": payload["trigger"],
        "session_id": payload["session_id"],
        "git_head": payload["git_head"],
        "git_branch": payload["git_branch"],
        "git_status_count": payload["git_status_count"],
        "state_path": str(CURRENT.relative_to(ROOT)) if CURRENT.is_relative_to(ROOT) else str(CURRENT),
    }
    with event_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(event, ensure_ascii=False) + "\n")


def write_current(payload: dict) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    SNAPSHOTS_DIR.mkdir(parents=True, exist_ok=True)
    text = markdown(payload)
    # PID-unique tmp to avoid races when multiple hook entries (user/project/
    # plugin scopes) all fire state-precompact concurrently. Without this,
    # one process's tmp.replace(CURRENT) consumes the file before the next's
    # rename, yielding FileNotFoundError on the .tmp source path.
    tmp = CURRENT.with_suffix(f".{os.getpid()}.tmp")
    tmp.write_text(text, encoding="utf-8")
    # Retry the atomic rename a couple of times in case a concurrent writer
    # has the destination momentarily locked on Windows-style filesystems.
    last_err: Exception | None = None
    for _ in range(3):
        try:
            tmp.replace(CURRENT)
            last_err = None
            break
        except FileNotFoundError as e:
            last_err = e
            # The source tmp vanished — almost certainly because a concurrent
            # writer already moved its own tmp into CURRENT. That's fine; the
            # invariant (CURRENT.md exists with fresh content) is preserved.
            break
        except OSError as e:
            last_err = e
            time.sleep(0.05)
    if last_err is not None and tmp.exists():
        try:
            tmp.unlink()
        except OSError:
            pass

    if CURRENT.exists():
        stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        session = re.sub(r"[^A-Za-z0-9_.-]+", "-", payload["session_id"])[:80] or "unknown"
        snapshot = SNAPSHOTS_DIR / f"{stamp}-{session}-{os.getpid()}.md"
        shutil.copy2(CURRENT, snapshot)
    append_event(payload)


def hydrate() -> int:
    if not CURRENT.exists():
        return 0
    text = CURRENT.read_text(encoding="utf-8", errors="replace")
    text = truncate(text, 9000)
    context = (
        "working state rehydrated from `.no-amnesia/state/CURRENT.md`.\n\n"
        f"{text}"
    )
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "SessionStart",
                    "additionalContext": context,
                }
            }
        )
    )
    return 0


def status() -> int:
    if CURRENT.exists():
        print(CURRENT.read_text(encoding="utf-8", errors="replace"))
    else:
        print("No working state found. Run `bash .claude/hooks/state.sh snapshot` to create one.")
    return 0


def prune(days: int = 14) -> int:
    cutoff = time.time() - (days * 24 * 60 * 60)
    removed = 0
    for folder in (SNAPSHOTS_DIR, EVENTS_DIR):
        if not folder.exists():
            continue
        for path in folder.iterdir():
            if path.is_file() and path.stat().st_mtime < cutoff:
                path.unlink()
                removed += 1
    print(f"Pruned {removed} old working-state file(s).")
    return 0


def main() -> int:
    if COMMAND == "hydrate":
        return hydrate()
    if COMMAND == "status":
        return status()
    if COMMAND == "prune":
        return prune()
    if COMMAND in {"snapshot", "stop", "precompact", "postcompact"}:
        payload = state_payload(read_input())
        write_current(payload)
        return 0
    print("Usage: state.sh snapshot|hydrate|precompact|postcompact|stop|status|prune", file=sys.stderr)
    return 2


raise SystemExit(main())
PY
