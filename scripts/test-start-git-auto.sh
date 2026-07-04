#!/usr/bin/env bash
# test-start-git-auto.sh
# Regression test for start-git-auto.sh bugs found during unit-commit
# retesting (2026-06-07) and wrapup debugging (2026-07-04):
#
# 1. STALE unit-check.json BLOCKS ALL FUTURE DETECTION
#    Any unit-check.json present at SessionStart is orphaned from a prior
#    session (the new session hasn't edited anything yet). Without a sweep,
#    check-unit-complete.sh refuses to overwrite it forever, permanently
#    blocking Pathway B. Asserts: the stale file is surfaced via a
#    STALE_UNIT_CHECK marker (carrying its info forward) and removed.
#
# 2. INVALID CONFIG KEYS CRASH git-auto SILENTLY ON START
#    start-git-auto.sh used to report "started (PID …)" even when the daemon
#    died ~1s later. Asserts: when the launched process exits immediately,
#    the script reports failure (not false success) and surfaces the log tail.
#
# 3. STALE pending-commit.json MISLEADS wrapup/commit INTO FABRICATING A
#    COMMIT MESSAGE
#    pending-commit.json is only ever written by test-handshake.sh (git-auto
#    never writes it in real operation — see plugin-working.md), and
#    test-handshake.sh's --dry-run / timeout paths never clean it up. Any
#    copy present at SessionStart is therefore orphaned, exactly like
#    unit-check.json above. Asserts: it's surfaced via a
#    STALE_PENDING_COMMIT marker and removed.
#
# All scenarios are exercised against a stub `git-auto` on PATH — we don't
# need the real binary's behavior, just to control whether it stays alive.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/start-git-auto.sh"

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

cat > "$REPO/git-auto-config.json" <<'EOF'
{"start": {"files_threshold": 999}}
EOF

PASS=true

run_with_stub() {
  local stub_body="$1"
  cat > "$STUB_BIN/git-auto" <<EOF
#!/usr/bin/env bash
$stub_body
EOF
  chmod +x "$STUB_BIN/git-auto"
  PATH="$STUB_BIN:$PATH" bash "$SCRIPT" 2>"$WORKDIR/stderr.log" 1>"$WORKDIR/stdout.log" || true
  cat "$WORKDIR/stderr.log" "$WORKDIR/stdout.log"
}

echo "=== Scenario 1: stale unit-check.json is surfaced and swept ==="

cat > "$REPO/.git/unit-check.json" <<'EOF'
{
  "branch": "feature-x",
  "files_changed": ["src/a.py", "src/b.py"],
  "stat_summary": "2 files changed",
  "timestamp": "2026-06-01T10:00:00"
}
EOF

# Long-lived stub so we can observe the sweep without racing daemon shutdown
OUTPUT=$(cd "$REPO" && run_with_stub 'sleep 30 &
disown
exit 0')

if echo "$OUTPUT" | grep -q "STALE_UNIT_CHECK:.*feature-x\|STALE_UNIT_CHECK:.*src/a.py"; then
  echo "PASS: stale unit-check.json surfaced via STALE_UNIT_CHECK marker with its contents"
else
  echo "FAIL: STALE_UNIT_CHECK marker missing or didn't carry forward stale info"
  echo "--- output ---"
  echo "$OUTPUT"
  PASS=false
fi

if [ -f "$REPO/.git/unit-check.json" ]; then
  echo "FAIL: unit-check.json still present after sweep"
  PASS=false
else
  echo "PASS: orphaned unit-check.json removed"
fi

pkill -f "sleep 30" 2>/dev/null || true
rm -f "$REPO/.git/git-auto-state.json" "$REPO/.git/git-auto.log"

echo ""
echo "=== Scenario 2: daemon that exits immediately is reported as a failure ==="

OUTPUT=$(cd "$REPO" && run_with_stub 'echo "Error: Unknown config key(s): claude_handshake, claude_timeout" >&2
exit 1')

if echo "$OUTPUT" | grep -q "git-auto failed to start"; then
  echo "PASS: immediate daemon exit reported as failure (not false 'started')"
else
  echo "FAIL: script did not detect the daemon dying — risk of false 'started' report"
  echo "--- output ---"
  echo "$OUTPUT"
  PASS=false
fi

if echo "$OUTPUT" | grep -q "Unknown config key"; then
  echo "PASS: real crash reason (log tail) surfaced to the user"
else
  echo "FAIL: crash reason not surfaced — user would have no clue why it failed"
  PASS=false
fi

if echo "$OUTPUT" | grep -q "git-auto started for"; then
  echo "FAIL: false 'started' message printed despite immediate exit"
  PASS=false
else
  echo "PASS: no false 'started' message printed"
fi

rm -f "$REPO/.git/git-auto-state.json" "$REPO/.git/git-auto.log"

echo ""
echo "=== Scenario 3: stale pending-commit.json is surfaced and swept ==="

cat > "$REPO/.git/pending-commit.json" <<'EOF'
{
  "branch": "feature-x",
  "files_changed": ["src/example.py", "tests/test_example.py"],
  "stat_summary": "2 files changed, 10 insertions(+), 2 deletions(-)",
  "timestamp": "2026-06-01T10:00:00"
}
EOF

OUTPUT=$(cd "$REPO" && run_with_stub 'sleep 30 &
disown
exit 0')

if echo "$OUTPUT" | grep -q "STALE_PENDING_COMMIT:.*feature-x\|STALE_PENDING_COMMIT:.*src/example.py"; then
  echo "PASS: stale pending-commit.json surfaced via STALE_PENDING_COMMIT marker with its contents"
else
  echo "FAIL: STALE_PENDING_COMMIT marker missing or didn't carry forward stale info"
  echo "--- output ---"
  echo "$OUTPUT"
  PASS=false
fi

if [ -f "$REPO/.git/pending-commit.json" ]; then
  echo "FAIL: pending-commit.json still present after sweep"
  PASS=false
else
  echo "PASS: orphaned pending-commit.json removed"
fi

pkill -f "sleep 30" 2>/dev/null || true
rm -f "$REPO/.git/git-auto-state.json" "$REPO/.git/git-auto.log"

echo ""
if $PASS; then
  echo "=== ALL CHECKS PASSED ==="
  exit 0
else
  echo "=== FAILURES DETECTED ==="
  exit 1
fi
