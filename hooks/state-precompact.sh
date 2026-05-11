#!/bin/bash
# PreCompact hook: snapshot current working state before conversation compaction.

set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
exec bash "${CLAUDE_PLUGIN_ROOT}/hooks/state.sh" precompact
