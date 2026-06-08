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

# Any unit-check.json present at SessionStart is necessarily orphaned from a
# prior session — the new session hasn't made any edits yet, so it can't have
# written one itself. (check-unit-complete.sh refuses to overwrite an existing
# unit-check.json, trusting Claude to clear it after responding — but a session
# that ends without responding, e.g. a crash or restart while git-auto keeps
# running, leaves it stuck forever and silently blocks Pathway B from then on.)
#
# Before clearing, surface its contents — it represents uncommitted work that
# was never evaluated, and the new session should know about it rather than
# silently lose the trail.
UNIT_CHECK="$REPO_ROOT/.git/unit-check.json"
if [ -f "$UNIT_CHECK" ]; then
  STALE_INFO=$(python3 -c "
import json
try:
    d = json.load(open('$UNIT_CHECK'))
    print(f\"{d.get('timestamp', 'unknown time')} | {d.get('stat_summary', 'changes detected')} | files: {', '.join(d.get('files_changed', []))}\")
except Exception:
    print('unreadable snapshot')
" 2>/dev/null)
  echo "[minimal-git-workflow] STALE_UNIT_CHECK: orphaned check from a previous session ($STALE_INFO) — never evaluated. Clearing it; if uncommitted changes remain, run /minimal-git-workflow:unit-commit to evaluate them now." >&2
  rm -f "$UNIT_CHECK"
fi

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
    UNPUSHED=$(git -C "$REPO_ROOT" rev-list '@{u}..HEAD' --count 2>/dev/null || echo 0)
    if [ "$UNPUSHED" -gt 0 ]; then
      UPSTREAM=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo "unknown")
      echo "[minimal-git-workflow] UNPUSHED_COMMITS: $UNPUSHED ahead of $UPSTREAM — invoke /minimal-git-workflow:clean-slate before continuing." >&2
    fi
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

# Detect unpushed commits — surface them so Claude can offer clean-slate triage
# before git-auto starts operating on this branch.
UNPUSHED=$(git -C "$REPO_ROOT" rev-list '@{u}..HEAD' --count 2>/dev/null || echo 0)
if [ "$UNPUSHED" -gt 0 ]; then
  UPSTREAM=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo "unknown")
  echo "[minimal-git-workflow] UNPUSHED_COMMITS: $UNPUSHED ahead of $UPSTREAM — invoke /minimal-git-workflow:clean-slate before continuing." >&2
fi

# Start git-auto in background, scoped to this project, logging to .git/git-auto.log
#
# Bash forces SIGINT/SIGQUIT to SIG_IGN on any `&` async job in a script —
# nohup only touches SIGHUP. That masked disposition is inherited straight
# through exec into the daemon, permanently blocking `git-auto stop`'s
# `os.kill(pid, SIGINT)` (a structural no-op against a SIG_IGN process).
# Reset both traps to default in a subshell before exec'ing so the daemon can
# actually receive and act on the stop signal.
( trap - INT QUIT
  exec nohup git-auto start --path "$REPO_ROOT" \
    >> "$REPO_ROOT/.git/git-auto.log" 2>&1
) &
GIT_AUTO_PID=$!

# Verify the daemon actually stayed alive — invalid config keys (or other
# startup errors) cause git-auto to exit, but a naive launch report would
# still claim success. Measured live: real crash lands ~2.0s in (uv/python
# venv startup runs before config validation) — 1.5s missed it, 3s clears
# it with margin.
sleep 3
if kill -0 "$GIT_AUTO_PID" 2>/dev/null; then
  echo "[minimal-git-workflow] git-auto started for $REPO_ROOT (PID $GIT_AUTO_PID)." >&2
else
  echo "[minimal-git-workflow] git-auto failed to start — it exited immediately. Last log lines:" >&2
  tail -n 5 "$REPO_ROOT/.git/git-auto.log" >&2 2>/dev/null || true
  echo "[minimal-git-workflow] Check $CONFIG_FILE for invalid keys or run 'git-auto start --path \"$REPO_ROOT\"' directly to see the full error." >&2
  exit 1
fi

echo "[minimal-git-workflow] MONITOR_REQUIRED: Call the Monitor tool with command: bash \"$PLUGIN_ROOT/scripts/watch-pending.sh\" — this delivers pending commit notifications to your session."
