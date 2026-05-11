#!/bin/bash
# time-anchor
# Emits a fresh local-system-clock anchor for Claude Code context.

set -euo pipefail

COMMAND="${1:-hook}"
ROOT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

if [ ! -d "$ROOT_DIR" ]; then
  ROOT_DIR="$(pwd)"
fi

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

python3 - "$COMMAND" "$ROOT_DIR" "$INPUT_FILE" <<'PY'
import datetime as dt
import json
import pathlib
import sys
import time


COMMAND = sys.argv[1]
ROOT = pathlib.Path(sys.argv[2]).resolve()
INPUT_FILE = pathlib.Path(sys.argv[3])


def read_input() -> dict:
    try:
        raw = INPUT_FILE.read_text(encoding="utf-8", errors="replace")
        return json.loads(raw) if raw.strip() else {}
    except Exception:
        return {}


def time_payload(input_data: dict) -> dict:
    local_now = dt.datetime.now().astimezone()
    utc_now = local_now.astimezone(dt.timezone.utc)
    return {
        "source": "local system clock via time-anchor.sh",
        "local_time": local_now.isoformat(timespec="seconds"),
        "utc_time": utc_now.isoformat(timespec="seconds"),
        "epoch_seconds": int(time.time()),
        "timezone_name": local_now.tzname() or "unknown",
        "timezone_offset": local_now.strftime("%z"),
        "local_date": local_now.date().isoformat(),
        "local_hour": local_now.strftime("%H:%M:%S"),
        "weekday": local_now.strftime("%A"),
        "project_dir": str(ROOT),
        "hook_event_name": input_data.get("hook_event_name") or "SessionStart",
    }


def context(payload: dict) -> str:
    return f"""temporal anchor from the local system clock.

local_time: {payload['local_time']}
utc_time: {payload['utc_time']}
timezone: {payload['timezone_name']} ({payload['timezone_offset']})
local_date: {payload['local_date']}
local_hour: {payload['local_hour']}
weekday: {payload['weekday']}
source: {payload['source']}

Temporal reasoning rules:
1. Treat local_time as the current present date and hour for this Claude Code prompt.
2. Resolve "today", "yesterday", "tomorrow", "this week", "current", "latest", "recent", and year-specific claims relative to this anchor.
3. For SOTA 2026, current model/provider behavior, pricing, laws, docs, benchmarks, APIs, schedules, or news, do live source verification before making factual claims.
4. Cite source publish/update dates and the access date when research is time-sensitive.
5. If live verification is unavailable or incomplete, say the claim is stale, unverified, or insufficient_data instead of relying on pretrained memory.
"""


def hook_event_name(input_data: dict) -> str:
    event = input_data.get("hook_event_name")
    if event in {"SessionStart", "UserPromptSubmit"}:
        return event
    if COMMAND == "prompt":
        return "UserPromptSubmit"
    return "SessionStart"


def main() -> int:
    input_data = read_input()
    payload = time_payload(input_data)

    if COMMAND in {"json", "--json"}:
        print(json.dumps(payload, indent=2))
        return 0

    if COMMAND in {"text", "--text"}:
        print(context(payload))
        return 0

    if COMMAND in {"hook", "prompt", "session"}:
        print(
            json.dumps(
                {
                    "hookSpecificOutput": {
                        "hookEventName": hook_event_name(input_data),
                        "additionalContext": context(payload),
                    }
                }
            )
        )
        return 0

    print("Usage: time-anchor.sh hook|prompt|session|text|json", file=sys.stderr)
    return 2


raise SystemExit(main())
PY
