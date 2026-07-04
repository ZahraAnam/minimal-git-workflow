#!/usr/bin/env bash
# test-handshake-staleness.sh
# Regression test for a stale pending-commit.json misleading wrapup/commit
# mid-session (found 2026-07-04 debugging the wrapup command).
#
# start-git-auto.sh's STALE_PENDING_COMMIT sweep only runs at SessionStart.
# A pending-commit.json written mid-session (e.g. by test-handshake.sh) and
# then abandoned — dry-run, or the wait loop timing out — survives past that
# sweep for the rest of the session. handshake.py's read_pending_commit()
# (backing both `commit`'s read-pending and `wrapup`'s status) must treat an
# old-enough file as stale itself, same TTL pattern check-unit-complete.sh
# already applies to unit-check.json mid-session.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HANDSHAKE="$SCRIPT_DIR/handshake.py"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

REPO="$WORKDIR/repo"
mkdir -p "$REPO"
git init -q "$REPO"
git -C "$REPO" config user.email "test@example.com"
git -C "$REPO" config user.name "Test"
echo "init" > "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -q -m "init"

PASS=true

echo "=== Scenario 1: stale pending-commit.json (past TTL) is treated as none ==="

cat > "$REPO/.git/pending-commit.json" <<'EOF'
{
  "branch": "feature-x",
  "files_changed": ["src/example.py", "tests/test_example.py"],
  "stat_summary": "2 files changed, 10 insertions(+), 2 deletions(-)",
  "timestamp": "2026-06-01T10:00:00"
}
EOF

OUTPUT=$(cd "$REPO" && python3 "$HANDSHAKE" status 2>&1)

if echo "$OUTPUT" | grep -q "pending-commit.json : none"; then
  echo "PASS: stale pending-commit.json reported as none by status"
else
  echo "FAIL: status still reports the stale file as EXISTS"
  echo "--- output ---"
  echo "$OUTPUT"
  PASS=false
fi

if echo "$OUTPUT" | grep -q "STALE_PENDING_COMMIT:.*feature-x\|STALE_PENDING_COMMIT:.*src/example.py"; then
  echo "PASS: staleness surfaced via STALE_PENDING_COMMIT marker with its contents"
else
  echo "FAIL: STALE_PENDING_COMMIT marker missing or didn't carry forward stale info"
  echo "--- output ---"
  echo "$OUTPUT"
  PASS=false
fi

if [ -f "$REPO/.git/pending-commit.json" ]; then
  echo "FAIL: pending-commit.json still present after staleness check"
  PASS=false
else
  echo "PASS: stale pending-commit.json cleared"
fi

echo ""
echo "=== Scenario 2: fresh pending-commit.json (within TTL) is still honored ==="

python3 -c "
import json
from datetime import datetime
payload = {
    'branch': 'feature-x',
    'files_changed': ['src/real.py'],
    'stat_summary': '1 file changed, 5 insertions(+)',
    'timestamp': datetime.now().isoformat(),
}
with open('$REPO/.git/pending-commit.json', 'w') as f:
    json.dump(payload, f, indent=2)
"

OUTPUT=$(cd "$REPO" && python3 "$HANDSHAKE" status 2>&1)

if echo "$OUTPUT" | grep -q "pending-commit.json : EXISTS"; then
  echo "PASS: fresh pending-commit.json still reported as EXISTS"
else
  echo "FAIL: fresh pending-commit.json incorrectly treated as stale"
  echo "--- output ---"
  echo "$OUTPUT"
  PASS=false
fi

echo ""
if $PASS; then
  echo "=== ALL CHECKS PASSED ==="
  exit 0
else
  echo "=== FAILURES DETECTED ==="
  exit 1
fi
