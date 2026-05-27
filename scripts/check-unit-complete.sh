#!/usr/bin/env bash
# check-unit-complete.sh
# PostToolUse hook — fires after Edit/Write tool calls.
# Checks for uncommitted changes and writes unit-check.json to trigger Claude evaluation.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Find config file
CONFIG_FILE=""
for ext in json toml yaml yml; do
  if [ -f "$REPO_ROOT/git-auto-config.$ext" ]; then
    CONFIG_FILE="$REPO_ROOT/git-auto-config.$ext"
    break
  fi
done

if [ -z "$CONFIG_FILE" ]; then
  exit 0
fi

# Check if unit_commit is enabled
UNIT_COMMIT_ENABLED=$(python3 -c "
import json, sys
try:
    c = json.load(open('$CONFIG_FILE'))
    print('true' if c.get('unit_commit', False) else 'false')
except:
    print('false')
" 2>/dev/null)

if [ "$UNIT_COMMIT_ENABLED" != "true" ]; then
  exit 0
fi

UNIT_CHECK="$REPO_ROOT/.git/unit-check.json"

# Don't overwrite existing unit-check.json — Claude hasn't responded to the last one yet
if [ -f "$UNIT_CHECK" ]; then
  exit 0
fi

# Check for uncommitted changes
CHANGED_COUNT=$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

if [ "$CHANGED_COUNT" -eq 0 ]; then
  exit 0
fi

# Write unit-check.json via handshake.py
python3 "$PLUGIN_ROOT/scripts/handshake.py" write-unit-check >/dev/null

echo "[minimal-git-workflow] unit-check.json written ($CHANGED_COUNT changed file(s)) — watch-pending.sh will notify Claude." >&2
