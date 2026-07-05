#!/usr/bin/env bash
# test-stop-git-auto-unit-check-surfacing.sh
# Regression test for an asymmetry between start-git-auto.sh and
# stop-git-auto.sh: start-git-auto.sh surfaces unit-check.json's contents via
# a STALE_UNIT_CHECK marker before deleting an orphaned copy (crash/interrupt
# recovery, so the uncommitted-work trail isn't silently lost). stop-git-auto.sh
# deleted the same file unconditionally and silently — no equivalent marker —
# breaking the "never silently lose the trail" invariant the rest of this
# codebase holds to (see development-details.md's STALE_UNIT_CHECK/
# STALE_PENDING_COMMIT precedent).
#
# Asserts: when unit-check.json exists at wrapup/stop time, its contents
# (branch, stat_summary, files) are printed before the file is removed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/stop-git-auto.sh"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

REPO="$WORKDIR/repo"
STUB_BIN="$WORKDIR/bin"
mkdir -p "$REPO" "$STUB_BIN"

git init -q "$REPO"
git -C "$REPO" config user.email "test@example.com"
git -C "$REPO" config user.name "Test"
echo "init" > "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -q -m "init"

# Minimal stub — this test isn't exercising PID/signal behavior (see
# test-stop-git-auto.sh for that), just the unit-check.json surfacing step,
# so "git-auto stop" only needs to succeed without a real daemon.
cat > "$STUB_BIN/git-auto" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$STUB_BIN/git-auto"

PASS=true

echo "=== unit-check.json present at stop time is surfaced before deletion ==="

cat > "$REPO/.git/unit-check.json" <<'EOF'
{
  "branch": "feature-z",
  "files_changed": ["src/wip.py"],
  "stat_summary": "1 file changed, 3 insertions(+)",
  "timestamp": "2026-07-05T10:00:00"
}
EOF

OUTPUT=$(cd "$REPO" && PATH="$STUB_BIN:$PATH" bash "$SCRIPT" 2>&1) || true

if echo "$OUTPUT" | grep -q "UNIT_CHECK.*feature-z\|UNIT_CHECK.*src/wip.py"; then
  echo "PASS: unit-check.json contents surfaced before stop-git-auto.sh removed it"
else
  echo "FAIL: unit-check.json contents were not surfaced — silent data loss"
  echo "--- output ---"
  echo "$OUTPUT"
  PASS=false
fi

if [ -f "$REPO/.git/unit-check.json" ]; then
  echo "FAIL: unit-check.json still present after stop — should be cleared"
  PASS=false
else
  echo "PASS: unit-check.json cleared as before"
fi

echo ""
echo "=== no unit-check.json present — no spurious marker ==="

OUTPUT=$(cd "$REPO" && PATH="$STUB_BIN:$PATH" bash "$SCRIPT" 2>&1) || true

if echo "$OUTPUT" | grep -qi "UNIT_CHECK"; then
  echo "FAIL: marker printed even though no unit-check.json existed"
  echo "--- output ---"
  echo "$OUTPUT"
  PASS=false
else
  echo "PASS: no marker printed when there's nothing to surface"
fi

echo ""
if $PASS; then
  echo "=== ALL CHECKS PASSED ==="
  exit 0
else
  echo "=== FAILURES DETECTED ==="
  exit 1
fi
