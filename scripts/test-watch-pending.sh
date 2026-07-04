#!/usr/bin/env bash
# test-watch-pending.sh
# Regression test for watch-pending.sh bypassing handshake.py's staleness
# check (found reviewing PR #12, 2026-07-04).
#
# watch-pending.sh used to poll pending-commit.json's raw existence/mtime
# directly, never the JSON's internal `timestamp` field — so a file stale by
# handshake.py's 300s TTL still fired a "run /commit" notification, even
# though /commit's own read-pending call would immediately clear it as stale
# and silently do nothing. Asserts: watch-pending.sh now shares the exact
# same staleness definition as read-pending/status (no notification for a
# stale file; notification with the right summary for a fresh one).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/watch-pending.sh"

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

run_watch_for() {
  local seconds="$1"
  local out="$WORKDIR/out.log"
  (cd "$REPO" && timeout "$seconds" bash "$SCRIPT" > "$out" 2>&1) || true
  cat "$out"
}

echo "=== Scenario 1: stale pending-commit.json — no notification ==="

cat > "$REPO/.git/pending-commit.json" <<'EOF'
{
  "branch": "feature-x",
  "files_changed": ["src/example.py"],
  "stat_summary": "2 files changed, 10 insertions(+), 2 deletions(-)",
  "timestamp": "2026-06-01T10:00:00"
}
EOF

OUTPUT=$(run_watch_for 7)

if echo "$OUTPUT" | grep -q "^PENDING_COMMIT:"; then
  echo "FAIL: stale file still triggered a PENDING_COMMIT notification"
  echo "--- output ---"
  echo "$OUTPUT"
  PASS=false
else
  echo "PASS: no notification for a stale pending-commit.json"
fi

if [ -f "$REPO/.git/pending-commit.json" ]; then
  echo "FAIL: stale pending-commit.json was not cleared by the poll loop"
  PASS=false
else
  echo "PASS: stale pending-commit.json cleared as a side effect of the poll"
fi

echo ""
echo "=== Scenario 2: fresh pending-commit.json — notification with summary ==="

python3 -c "
import json
from datetime import datetime
payload = {
    'branch': 'feature-x',
    'files_changed': ['src/real.py'],
    'stat_summary': 'REAL_SUMMARY_MARKER 1 file changed',
    'timestamp': datetime.now().isoformat(),
}
with open('$REPO/.git/pending-commit.json', 'w') as f:
    json.dump(payload, f, indent=2)
"

OUTPUT=$(run_watch_for 7)

if echo "$OUTPUT" | grep -q "^PENDING_COMMIT:.*REAL_SUMMARY_MARKER"; then
  echo "PASS: fresh pending-commit.json triggered a notification with the real summary"
else
  echo "FAIL: fresh pending-commit.json did not trigger the expected notification"
  echo "--- output ---"
  echo "$OUTPUT"
  PASS=false
fi

echo ""
echo "=== Scenario 3: multi-line stat_summary (realistic multi-file diff --stat) isn't truncated ==="

# stat_summary is real `git diff --stat` output, which spans multiple lines
# for any multi-file change (found reviewing PR #12's watch-pending.sh fix,
# 2026-07-04) — the positional line-splitting used to silently drop
# everything after the first line.
python3 -c "
import json
from datetime import datetime
payload = {
    'branch': 'feature-x',
    'files_changed': ['a.py', 'b.py'],
    'stat_summary': 'a.py | 2 ++\n b.py | 1 +\n LAST_LINE_MARKER 2 files changed, 3 insertions(+)',
    'timestamp': datetime.now().isoformat(),
}
with open('$REPO/.git/pending-commit.json', 'w') as f:
    json.dump(payload, f, indent=2)
"

OUTPUT=$(run_watch_for 7)

if echo "$OUTPUT" | grep -q "LAST_LINE_MARKER"; then
  echo "PASS: multi-line stat_summary preserved through to the notification"
else
  echo "FAIL: multi-line stat_summary was truncated before reaching the notification"
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
