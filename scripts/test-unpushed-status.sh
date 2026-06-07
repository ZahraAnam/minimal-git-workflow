#!/usr/bin/env bash
# test-unpushed-status.sh
# Regression test for `handshake.py unpushed-status`.
# Verifies count, subjects (never diffs), and the no-upstream case.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

REMOTE="$WORKDIR/remote.git"
REPO="$WORKDIR/repo"

git init -q --bare "$REMOTE"

git init -q "$REPO"
git -C "$REPO" config user.email "test@example.com"
git -C "$REPO" config user.name "Test"
git -C "$REPO" remote add origin "$REMOTE"

echo "init" > "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -q -m "init"
git -C "$REPO" push -q -u origin HEAD:main

PASS=true

echo "=== unpushed-status: clean repo ==="
STATUS=$(cd "$REPO" && python3 "$SCRIPT_DIR/handshake.py" unpushed-status)
echo "$STATUS"
COUNT=$(echo "$STATUS" | python3 -c "import json,sys; print(json.load(sys.stdin)['count'])")
if [ "$COUNT" -eq 0 ]; then
  echo "PASS: count == 0 on clean repo"
else
  echo "FAIL: expected count 0, got $COUNT"
  PASS=false
fi

echo ""
echo "=== unpushed-status: 2 unpushed commits ==="
echo "a" >> "$REPO/README.md"
git -C "$REPO" commit -q -am "feat: add a"
echo "b" >> "$REPO/README.md"
git -C "$REPO" commit -q -am "fix: add b"

STATUS=$(cd "$REPO" && python3 "$SCRIPT_DIR/handshake.py" unpushed-status)
echo "$STATUS"
COUNT=$(echo "$STATUS" | python3 -c "import json,sys; print(json.load(sys.stdin)['count'])")
SUBJECTS=$(echo "$STATUS" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['subjects']))")

if [ "$COUNT" -eq 2 ]; then
  echo "PASS: count == 2"
else
  echo "FAIL: expected count 2, got $COUNT"
  PASS=false
fi

if [ "$SUBJECTS" = '["fix: add b", "feat: add a"]' ]; then
  echo "PASS: subjects in newest-first order, subjects only (no diffs)"
else
  echo "FAIL: unexpected subjects: $SUBJECTS"
  PASS=false
fi

echo ""
echo "=== unpushed-status: no upstream configured ==="
NOUP="$WORKDIR/no-upstream"
git init -q "$NOUP"
git -C "$NOUP" config user.email "test@example.com"
git -C "$NOUP" config user.name "Test"
echo "x" > "$NOUP/f.txt"
git -C "$NOUP" add f.txt
git -C "$NOUP" commit -q -m "no upstream commit"

STATUS=$(cd "$NOUP" && python3 "$SCRIPT_DIR/handshake.py" unpushed-status)
echo "$STATUS"
COUNT=$(echo "$STATUS" | python3 -c "import json,sys; print(json.load(sys.stdin)['count'])")
UPSTREAM=$(echo "$STATUS" | python3 -c "import json,sys; print(json.load(sys.stdin)['upstream'])")

if [ "$COUNT" -eq 0 ] && [ "$UPSTREAM" = "None" ]; then
  echo "PASS: no-upstream repo reports count 0, upstream null"
else
  echo "FAIL: expected count 0 / upstream null, got count=$COUNT upstream=$UPSTREAM"
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
