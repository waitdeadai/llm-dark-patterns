#!/bin/bash
# SessionStart hook: inject compact working state into Claude Code context.

set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
exec bash "${CLAUDE_PLUGIN_ROOT}/hooks/state.sh" hydrate
