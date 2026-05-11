#!/bin/bash
# Stop hook: refresh working state after each completed Claude Code turn.

set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
exec bash "${CLAUDE_PLUGIN_ROOT}/hooks/state.sh" stop
