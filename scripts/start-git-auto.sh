#!/usr/bin/env bash
# start-git-auto.sh
# Called on SessionStart. Starts git-auto if not already running.
# Reads config from git-auto-config.json in the repo root.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "[minimal-git-workflow] Not a git repo — skipping git-auto start." >&2
  exit 0
}

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="$REPO_ROOT/.git/git-auto-state.json"

# Guard: git-auto must be installed
if ! command -v git-auto &>/dev/null; then
  echo "[minimal-git-workflow] git-auto not found on PATH." >&2
  echo "[minimal-git-workflow] Run install.sh from the plugin repo to install it." >&2
  exit 1
fi

# Check if already running FOR THIS PROJECT specifically
if [ -f "$STATE_FILE" ]; then
  PID=$(python3 -c "
import json
try:
    s = json.load(open('$STATE_FILE'))
    # Only match if both PID exists and path matches this repo
    if s.get('path') == '$REPO_ROOT':
        print(s.get('pid', ''))
    else:
        print('')
except:
    print('')
")
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    echo "[minimal-git-workflow] git-auto already running for this project (PID $PID) — skipping." >&2
    echo "[minimal-git-workflow] MONITOR_REQUIRED: Call the Monitor tool with command: bash \"$PLUGIN_ROOT/scripts/watch-pending.sh\" — this delivers pending commit notifications to your session."
    exit 0
  fi
fi

# Find config file in repo root
CONFIG_FILE=""
for ext in json toml yaml yml; do
  if [ -f "$REPO_ROOT/git-auto-config.$ext" ]; then
    CONFIG_FILE="$REPO_ROOT/git-auto-config.$ext"
    break
  fi
done

if [ -z "$CONFIG_FILE" ]; then
  echo "[minimal-git-workflow] No git-auto-config file found in $REPO_ROOT." >&2
  echo "[minimal-git-workflow] Run /minimal-git-workflow:configure to create one." >&2
  exit 0
fi

echo "[minimal-git-workflow] Starting git-auto with config: $CONFIG_FILE" >&2

# Start git-auto in background, scoped to this project, logging to .git/git-auto.log
nohup git-auto start --path "$REPO_ROOT" \
  >> "$REPO_ROOT/.git/git-auto.log" 2>&1 &

echo "[minimal-git-workflow] git-auto started for $REPO_ROOT (PID $!)." >&2
echo "[minimal-git-workflow] MONITOR_REQUIRED: Call the Monitor tool with command: bash \"$PLUGIN_ROOT/scripts/watch-pending.sh\" — this delivers pending commit notifications to your session."
