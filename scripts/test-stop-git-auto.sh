#!/usr/bin/env bash
# test-stop-git-auto.sh
# Regression test for the SIGINT/SIG_IGN masking bug in stop-git-auto.sh
# (found 2026-06-08, debug/fix-wrapup-command):
#
# Bash forces SIGINT/SIGQUIT to SIG_IGN on a bare `cmd &` (simple command run
# asynchronously) when job control is off — which is exactly what the old
# start-git-auto.sh did: `nohup git-auto start ... &`. That forced ignore
# survives exec (nohup itself only touches SIGHUP), so the real daemon ended
# up with SIGINT permanently ignored — `git-auto stop`'s SIGINT was then a
# structural no-op, and the script reported success unconditionally.
#
# The fix wraps the launch in a `( ... ) &` subshell instead of a bare async
# command — bash does not apply the same forced-ignore to a subshelled async
# job, so the daemon inherits normal signal dispositions. stop-git-auto.sh
# additionally verifies the PID actually died and escalates to SIGTERM/SIGKILL
# if not, as defense in depth.
#
# This test exercises stop-git-auto.sh directly against both daemon shapes:
#   1. A bare `cmd &` daemon — reproduces the historical bug.
#   2. The `( ... ) &` subshell daemon — today's shape, should die cleanly on
#      the first SIGINT with no escalation needed.
#
# The stub `git-auto stop` sends a real SIGINT to the recorded PID, just like
# the real binary does, so both scenarios are driven by actual signal
# delivery rather than mocked-out script logic. The daemon stand-in is a bare
# `sleep` process (no shell loop) — a `while` loop around `sleep` would let
# bash's own job-control signal handling interrupt-and-continue the loop
# forever, which isn't how the real (non-shell) git-auto daemon behaves.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/stop-git-auto.sh"

WORKDIR=$(mktemp -d)
SPAWNED_PIDS=()
cleanup() {
  for pid in "${SPAWNED_PIDS[@]:-}"; do
    [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null || true
  done
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

REPO="$WORKDIR/repo"
STUB_BIN="$WORKDIR/bin"
mkdir -p "$REPO" "$STUB_BIN"

git init -q "$REPO"
git -C "$REPO" config user.email "test@example.com"
git -C "$REPO" config user.name "Test"
echo "init" > "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -q -m "init"

# Stub git-auto: `stop` reads the recorded PID and sends a real SIGINT,
# exactly like the real binary — so the test exercises actual signal
# delivery, not just script control flow.
cat > "$STUB_BIN/git-auto" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "stop" ]; then
  path=""
  prev=""
  for arg in "$@"; do
    if [ "$prev" = "--path" ]; then path="$arg"; fi
    prev="$arg"
  done
  pid=$(python3 -c "
import json
try:
    print(json.load(open('$path/.git/git-auto-state.json')).get('pid') or '')
except Exception:
    print('')
")
  [ -n "$pid" ] && kill -INT "$pid" 2>/dev/null
  echo "git-auto: stop requested"
fi
exit 0
STUB
chmod +x "$STUB_BIN/git-auto"

PASS=true

echo "=== Scenario 1: bare async daemon inherits SIG_IGN, survives SIGINT, gets escalated ==="

# A bare simple-command async job — exactly the pre-fix start-git-auto.sh
# shape (`nohup ... &` with no subshell).
sleep 100000 &
MASKED_PID=$!
SPAWNED_PIDS+=("$MASKED_PID")
echo "{\"pid\": $MASKED_PID}" > "$REPO/.git/git-auto-state.json"

OUTPUT=$(cd "$REPO" && PATH="$STUB_BIN:$PATH" bash "$SCRIPT" 2>&1) || true

if kill -0 "$MASKED_PID" 2>/dev/null; then
  echo "FAIL: masked daemon (PID $MASKED_PID) still alive after stop-git-auto.sh ran"
  PASS=false
else
  echo "PASS: masked daemon actually died"
fi

if echo "$OUTPUT" | grep -q "escalating to SIGTERM"; then
  echo "PASS: script detected the SIGINT no-op and escalated"
else
  echo "FAIL: script did not report escalation for a masked daemon"
  echo "--- output ---"
  echo "$OUTPUT"
  PASS=false
fi

if echo "$OUTPUT" | grep -q "confirmed dead"; then
  echo "PASS: final status confirms the daemon is dead (not a blind success claim)"
else
  echo "FAIL: script did not confirm death in its final message"
  PASS=false
fi

kill -0 "$MASKED_PID" 2>/dev/null && kill -KILL "$MASKED_PID" 2>/dev/null
rm -f "$REPO/.git/git-auto-state.json"

echo ""
echo "=== Scenario 2: subshelled daemon (today's shape) dies on the first SIGINT, no escalation ==="

# Mirrors start-git-auto.sh's actual launch shape.
( trap - INT QUIT
  exec sleep 100000
) &
CLEAN_PID=$!
SPAWNED_PIDS+=("$CLEAN_PID")
echo "{\"pid\": $CLEAN_PID}" > "$REPO/.git/git-auto-state.json"

OUTPUT=$(cd "$REPO" && PATH="$STUB_BIN:$PATH" bash "$SCRIPT" 2>&1) || true

if kill -0 "$CLEAN_PID" 2>/dev/null; then
  echo "FAIL: subshelled daemon (PID $CLEAN_PID) still alive after stop-git-auto.sh ran"
  PASS=false
else
  echo "PASS: subshelled daemon died on the real SIGINT"
fi

if echo "$OUTPUT" | grep -q "escalating to SIGTERM"; then
  echo "FAIL: script escalated even though the daemon responds to SIGINT normally"
  PASS=false
else
  echo "PASS: no unnecessary escalation for a daemon that honors SIGINT"
fi

if echo "$OUTPUT" | grep -q "confirmed dead"; then
  echo "PASS: final status confirms the daemon is dead"
else
  echo "FAIL: script did not confirm death in its final message"
  PASS=false
fi

kill -0 "$CLEAN_PID" 2>/dev/null && kill -KILL "$CLEAN_PID" 2>/dev/null
rm -f "$REPO/.git/git-auto-state.json"

echo ""
if $PASS; then
  echo "=== ALL CHECKS PASSED ==="
  exit 0
else
  echo "=== FAILURES DETECTED ==="
  exit 1
fi
