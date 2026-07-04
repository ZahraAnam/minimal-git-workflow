#!/usr/bin/env bash
# watch-pending.sh
# Background monitor script. Claude Code runs this for the lifetime of the session.
# Polls .git/pending-commit.json every 5 seconds.
# When found, prints a notification line to stdout — Claude receives it automatically.

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PENDING="$REPO_ROOT/.git/pending-commit.json"
UNIT_CHECK="$REPO_ROOT/.git/unit-check.json"
NOTIFIED=""
NOTIFIED_UNIT=""

while true; do
  # --- threshold-based commit (git-auto) ---
  # CHANGED: read through handshake.py's read_pending_commit() instead of
  # stat'ing the file directly — that function is staleness-aware (300s TTL
  # on the JSON's own timestamp field), so this poll loop now shares the
  # exact same freshness definition /commit's read-pending uses instead of
  # notifying on a file /commit will silently ignore as stale.
  if [ -f "$PENDING" ]; then
    # CHANGED: stat_summary is real `git diff --stat` output, which spans
    # multiple lines for any multi-file change — positional array indexing
    # (mapfile) silently dropped everything after its first line. Timestamp
    # is always a single line, so split on "first line vs. the rest" instead:
    # that keeps an arbitrarily multi-line summary intact.
    PENDING_OUT=$(cd "$REPO_ROOT" && python3 -c "
import sys
sys.path.insert(0, '$PLUGIN_ROOT/scripts')
from handshake import read_pending_commit
d = read_pending_commit()
print(d.get('timestamp', '') if d else '')
print(d.get('stat_summary', 'changes detected') if d else '', end='')
")
    PENDING_TS=$(printf '%s\n' "$PENDING_OUT" | head -n1)
    SUMMARY=$(printf '%s\n' "$PENDING_OUT" | tail -n +2)
    if [ -n "$PENDING_TS" ]; then
      if [ "$PENDING_TS" != "$NOTIFIED" ]; then
        NOTIFIED="$PENDING_TS"
        echo "PENDING_COMMIT: git-auto needs a commit message. Summary: $SUMMARY. Run /minimal-git-workflow:commit to generate one."
      fi
    else
      NOTIFIED=""
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
