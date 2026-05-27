#!/usr/bin/env bash
# watch-pending.sh
# Background monitor script. Claude Code runs this for the lifetime of the session.
# Polls .git/pending-commit.json every 5 seconds.
# When found, prints a notification line to stdout — Claude receives it automatically.

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

PENDING="$REPO_ROOT/.git/pending-commit.json"
UNIT_CHECK="$REPO_ROOT/.git/unit-check.json"
NOTIFIED=""
NOTIFIED_UNIT=""

while true; do
  # --- threshold-based commit (git-auto) ---
  if [ -f "$PENDING" ]; then
    MTIME=$(stat -c %Y "$PENDING" 2>/dev/null || echo "0")
    if [ "$MTIME" != "$NOTIFIED" ]; then
      NOTIFIED="$MTIME"
      SUMMARY=$(python3 -c "
import json, sys
try:
    d = json.load(open('$PENDING'))
    print(d.get('stat_summary', 'changes detected'))
except:
    print('changes detected')
" 2>/dev/null)
      echo "PENDING_COMMIT: git-auto needs a commit message. Summary: $SUMMARY. Run /minimal-git-workflow:commit to generate one."
    fi
  else
    NOTIFIED=""
  fi

  # --- logical-unit-based commit ---
  if [ -f "$UNIT_CHECK" ]; then
    MTIME_UNIT=$(stat -c %Y "$UNIT_CHECK" 2>/dev/null || echo "0")
    if [ "$MTIME_UNIT" != "$NOTIFIED_UNIT" ]; then
      NOTIFIED_UNIT="$MTIME_UNIT"
      SUMMARY_UNIT=$(python3 -c "
import json, sys
try:
    d = json.load(open('$UNIT_CHECK'))
    print(d.get('stat_summary', 'changes detected'))
except:
    print('changes detected')
" 2>/dev/null)
      echo "UNIT_CHECK: Uncommitted changes detected. Summary: $SUMMARY_UNIT. Run /minimal-git-workflow:unit-commit to evaluate whether this is a complete logical unit."
    fi
  else
    NOTIFIED_UNIT=""
  fi

  sleep 5
done
