#!/usr/bin/env bash
# test-handshake.sh
# Simulates git-auto hitting a threshold and writing pending-commit.json.
# Use this to test the plugin handshake WITHOUT modifying git-auto.
#
# Usage:
#   ./scripts/test-handshake.sh              # auto-detect current repo state
#   ./scripts/test-handshake.sh --wait 30    # wait up to 30s for Claude response
#   ./scripts/test-handshake.sh --dry-run    # just write pending file, don't wait

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAIT=30
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --wait) WAIT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

REPO_ROOT=$(git rev-parse --show-toplevel)
PENDING="$REPO_ROOT/.git/pending-commit.json"
COMMIT_MSG="$REPO_ROOT/.git/commit-message.txt"

echo "=== test-handshake.sh ==="
echo "Repo: $REPO_ROOT"

# Build payload using handshake.py helpers
BRANCH=$(git rev-parse --abbrev-ref HEAD)
FILES=$(git status --porcelain | awk '{print $2}' | head -10 | python3 -c "
import sys, json
files = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(files))
")
STAT=$(git diff --stat 2>/dev/null || git diff --cached --stat 2>/dev/null || echo "2 files changed, 10 insertions(+)")

# If no real changes, use a realistic fake for testing
if [ -z "$STAT" ]; then
  STAT="2 files changed, 10 insertions(+), 2 deletions(-)"
  FILES='["src/example.py", "tests/test_example.py"]'
fi

echo "Branch : $BRANCH"
echo "Files  : $FILES"
echo "Stat   : $STAT"
echo ""

# Write pending-commit.json
python3 -c "
import json
from datetime import datetime
payload = {
    'branch': '$BRANCH',
    'files_changed': $FILES,
    'stat_summary': '''$STAT''',
    'timestamp': datetime.now().isoformat(),
}
with open('$PENDING', 'w') as f:
    json.dump(payload, f, indent=2)
print('Written: $PENDING')
"

if $DRY_RUN; then
  echo ""
  echo "[dry-run] pending-commit.json written. Not waiting for response."
  echo "[dry-run] Run: python3 $SCRIPT_DIR/handshake.py status"
  exit 0
fi

echo ""
echo "Waiting up to ${WAIT}s for Claude to write commit-message.txt..."
echo "(Run /minimal-git-workflow:commit in your Claude session now)"
echo ""

ELAPSED=0
while [ $ELAPSED -lt $WAIT ]; do
  if [ -f "$COMMIT_MSG" ]; then
    MSG=$(cat "$COMMIT_MSG")
    echo "=== SUCCESS ==="
    echo "Commit message received: $MSG"
    echo ""
    echo "Cleaning up handshake files..."
    python3 "$SCRIPT_DIR/handshake.py" clear
    echo "Done. In real use, git-auto would now run: git commit -m \"$MSG\""
    exit 0
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
  echo "  ...waiting (${ELAPSED}s / ${WAIT}s)"
done

echo ""
echo "=== TIMEOUT ==="
echo "No commit message received in ${WAIT}s."
echo "In real use, git-auto would fall back to Mistral."
echo ""
echo "Debug: check handshake status with:"
echo "  python3 $SCRIPT_DIR/handshake.py status"
