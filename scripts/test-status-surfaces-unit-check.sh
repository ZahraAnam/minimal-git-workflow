#!/usr/bin/env bash
# test-status-surfaces-unit-check.sh
# Regression test: handshake.py's `status` CLI command already prints
# unit-check.json's EXISTS/branch/stat_summary (see handshake.py's
# `elif cmd == "status"` block) — but skills/status/SKILL.md and
# commands/status.md only instructed Claude to report pending-commit.json /
# commit-message.txt state, never unit-check.json. Pathway B's state was
# invisible in the one command whose job is visibility, and the underlying
# CLI output itself had no test coverage either.
#
# Asserts: `handshake.py status` reports unit-check.json's EXISTS/none state,
# and its branch/stat_summary when present.

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

echo "=== Scenario 1: unit-check.json present — status reports it ==="

cat > "$REPO/.git/unit-check.json" <<'EOF'
{
  "branch": "feature-status",
  "files_changed": ["src/thing.py"],
  "stat_summary": "1 file changed, 2 insertions(+)",
  "timestamp": "2026-07-05T10:00:00"
}
EOF

OUTPUT=$(cd "$REPO" && python3 "$HANDSHAKE" status 2>&1)

if echo "$OUTPUT" | grep -q "unit-check.json.*EXISTS"; then
  echo "PASS: status reports unit-check.json as EXISTS"
else
  echo "FAIL: status did not report unit-check.json presence"
  echo "--- output ---"
  echo "$OUTPUT"
  PASS=false
fi

if echo "$OUTPUT" | grep -q "feature-status"; then
  echo "PASS: status surfaces the unit-check branch"
else
  echo "FAIL: status did not surface the unit-check branch"
  echo "--- output ---"
  echo "$OUTPUT"
  PASS=false
fi

if echo "$OUTPUT" | grep -q "1 file changed, 2 insertions"; then
  echo "PASS: status surfaces the unit-check stat_summary"
else
  echo "FAIL: status did not surface the unit-check stat_summary"
  echo "--- output ---"
  echo "$OUTPUT"
  PASS=false
fi

rm -f "$REPO/.git/unit-check.json"

echo ""
echo "=== Scenario 2: no unit-check.json — status reports none ==="

OUTPUT=$(cd "$REPO" && python3 "$HANDSHAKE" status 2>&1)

if echo "$OUTPUT" | grep -q "unit-check.json.*none"; then
  echo "PASS: status reports unit-check.json as none when absent"
else
  echo "FAIL: status did not report the none state"
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
