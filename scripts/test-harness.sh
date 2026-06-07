#!/usr/bin/env bash
# test-harness.sh — deterministic test helpers for minimal-git-workflow plugin testing
# Usage: test-harness.sh <subcommand> [args]
#
# Subcommands:
#   setup               kill all git-auto, start fresh with given config, create scratch file
#   teardown            stop git-auto, remove scratch file, show results
#   assert-clean        fail if any handshake files exist or tree is dirty
#   assert-processes N  fail if git-auto process count != N
#   assert-commit MSG   fail if most recent commit subject does not match MSG (regex)
#   assert-commit-count N  fail if commits since test-start != N
#   edit-scratch N      append line N to test-scratch.txt
#   wait-pending SECS   poll for pending-commit.json up to SECS seconds; fail on timeout
#   wait-commit SECS    poll until pending-commit.json gone (commit landed); fail on timeout
#   report PHASE RESULT REASON  append structured result to test-results.log
#   summary             print pass/fail table from test-results.log

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "[test-harness] ERROR: not a git repo" >&2; exit 1
}
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="$REPO_ROOT/test-scratch.txt"
RESULTS_LOG="$REPO_ROOT/.git/test-results.log"
BASELINE_COMMIT_FILE="$REPO_ROOT/.git/test-baseline-commit.txt"

_ts() { date '+%H:%M:%S'; }
_log() { echo "[$(_ts) test-harness] $*" >&2; }
_pass() { _log "PASS: $*"; }
_fail() { _log "FAIL: $*"; exit 1; }

case "${1:-help}" in

  setup)
    _log "=== TEST SETUP ==="
    # Stop the state-file-tracked process via stop script (graceful, project-scoped)
    # This only stops the process owned by THIS project's state file — other projects unaffected
    bash "$PLUGIN_ROOT/scripts/stop-git-auto.sh" 2>&1 || true
    sleep 1
    # Kill true orphans only: PIDs matching this repo's path that are NOT in the state file
    STATE_PID=$(python3 -c "
import json
try:
    s = json.load(open('$REPO_ROOT/.git/git-auto-state.json'))
    if s.get('path') == '$REPO_ROOT':
        print(s.get('pid', ''))
except:
    print('')
" 2>/dev/null || true)
    ORPHANS=$(pgrep -f "git-auto start --path $REPO_ROOT" 2>/dev/null | \
      grep -v "^${STATE_PID}$" || true)
    if [ -n "$ORPHANS" ]; then
      _log "Killing orphaned git-auto (not in state file): $ORPHANS"
      echo "$ORPHANS" | xargs kill -9 2>/dev/null || true
      sleep 1
    fi
    # Clean handshake files
    rm -f "$REPO_ROOT/.git/pending-commit.json"
    rm -f "$REPO_ROOT/.git/commit-message.txt"
    rm -f "$REPO_ROOT/.git/unit-check.json"
    # Remove scratch from previous run
    rm -f "$SCRATCH"
    git checkout -- "$SCRATCH" 2>/dev/null || true
    # Reset results log
    rm -f "$RESULTS_LOG"
    # Record baseline commit
    git rev-parse HEAD > "$BASELINE_COMMIT_FILE"
    _log "Baseline commit: $(cat "$BASELINE_COMMIT_FILE")"
    # Start git-auto
    _log "Starting git-auto..."
    bash "$PLUGIN_ROOT/scripts/start-git-auto.sh" 2>&1
    sleep 2
    # Verify single process
    COUNT=$(pgrep -cf "git-auto start --path $REPO_ROOT" 2>/dev/null || echo 0)
    [ "$COUNT" -eq 1 ] || _fail "Expected 1 git-auto process, got $COUNT"
    _pass "Setup complete. git-auto running ($(pgrep -f "git-auto start --path $REPO_ROOT"))."
    ;;

  teardown)
    _log "=== TEST TEARDOWN ==="
    # Use stop script — only kills this project's git-auto, leaves other projects running
    bash "$PLUGIN_ROOT/scripts/stop-git-auto.sh" 2>&1 || true
    # Remove scratch file and unstage
    if git ls-files --error-unmatch "$SCRATCH" &>/dev/null 2>&1; then
      git rm --force "$SCRATCH" 2>/dev/null && git commit -m "chore(test): remove test scratch file" || true
    else
      rm -f "$SCRATCH"
    fi
    rm -f "$BASELINE_COMMIT_FILE"
    _log "Teardown complete."
    # Print summary
    bash "$0" summary
    ;;

  assert-clean)
    PENDING=$(python3 "$PLUGIN_ROOT/scripts/handshake.py" status 2>/dev/null)
    DIRTY=$(git status --short)
    ERRORS=()
    echo "$PENDING" | grep -q "pending-commit.json : none" || ERRORS+=("pending-commit.json exists")
    echo "$PENDING" | grep -q "commit-message.txt  : none" || ERRORS+=("commit-message.txt exists")
    echo "$PENDING" | grep -q "unit-check.json     : none" || ERRORS+=("unit-check.json exists")
    [ -z "$DIRTY" ] || ERRORS+=("dirty tree: $DIRTY")
    if [ ${#ERRORS[@]} -gt 0 ]; then
      _fail "assert-clean: ${ERRORS[*]}"
    fi
    _pass "assert-clean: handshake files clean, tree clean"
    ;;

  assert-processes)
    EXPECTED="${2:-1}"
    # Count only processes watching THIS repo path — not other projects
    COUNT=$(pgrep -cf "git-auto start --path $REPO_ROOT" 2>/dev/null || echo 0)
    [ "$COUNT" -eq "$EXPECTED" ] || _fail "assert-processes: expected $EXPECTED for this repo, got $COUNT"
    _pass "assert-processes: $COUNT git-auto process(es) for this repo"
    ;;

  assert-commit)
    PATTERN="${2:?Usage: assert-commit REGEX}"
    SUBJECT=$(git log --oneline -1 --format="%s")
    echo "$SUBJECT" | grep -qE "$PATTERN" || _fail "assert-commit: '$SUBJECT' does not match '$PATTERN'"
    _pass "assert-commit: '$SUBJECT' matches '$PATTERN'"
    ;;

  assert-commit-count)
    EXPECTED="${2:?Usage: assert-commit-count N}"
    BASELINE=$(cat "$BASELINE_COMMIT_FILE" 2>/dev/null || echo "")
    if [ -z "$BASELINE" ]; then
      _fail "assert-commit-count: no baseline commit recorded — run setup first"
    fi
    COUNT=$(git rev-list "${BASELINE}..HEAD" --count 2>/dev/null || echo 0)
    [ "$COUNT" -eq "$EXPECTED" ] || _fail "assert-commit-count: expected $EXPECTED since baseline, got $COUNT"
    _pass "assert-commit-count: $COUNT commit(s) since baseline"
    ;;

  edit-scratch)
    N="${2:?Usage: edit-scratch N}"
    echo "test-line-$N: $(_ts)" >> "$SCRATCH"
    _log "Edited $SCRATCH (line $N)"
    ;;

  wait-pending)
    SECS="${2:-30}"
    PENDING_FILE="$REPO_ROOT/.git/pending-commit.json"
    _log "Waiting up to ${SECS}s for pending-commit.json..."
    for i in $(seq 1 "$SECS"); do
      [ -f "$PENDING_FILE" ] && { _pass "wait-pending: appeared after ${i}s"; exit 0; }
      sleep 1
    done
    _fail "wait-pending: pending-commit.json not written within ${SECS}s"
    ;;

  wait-commit)
    SECS="${2:-45}"
    PENDING_FILE="$REPO_ROOT/.git/pending-commit.json"
    _log "Waiting up to ${SECS}s for commit to land (pending-commit.json to clear)..."
    for i in $(seq 1 "$SECS"); do
      [ ! -f "$PENDING_FILE" ] && { _pass "wait-commit: commit landed after ${i}s"; exit 0; }
      sleep 1
    done
    _fail "wait-commit: pending-commit.json still present after ${SECS}s"
    ;;

  report)
    PHASE="${2:?Usage: report PHASE PASS|FAIL REASON}"
    RESULT="${3:?}"
    REASON="${4:-}"
    echo "$(_ts) | PHASE $PHASE | $RESULT | $REASON" >> "$RESULTS_LOG"
    _log "Recorded: PHASE $PHASE → $RESULT"
    ;;

  summary)
    echo ""
    echo "=== TEST RESULTS ==="
    if [ ! -f "$RESULTS_LOG" ]; then
      echo "(no results logged)"
    else
      PASS=$(grep -c "| PASS |" "$RESULTS_LOG" 2>/dev/null || echo 0)
      FAIL=$(grep -c "| FAIL |" "$RESULTS_LOG" 2>/dev/null || echo 0)
      cat "$RESULTS_LOG"
      echo "---"
      echo "PASS: $PASS  FAIL: $FAIL  TOTAL: $((PASS + FAIL))"
    fi
    echo "===================="
    ;;

  help|*)
    echo "Usage: test-harness.sh <subcommand> [args]"
    echo "Subcommands: setup teardown assert-clean assert-processes assert-commit"
    echo "             assert-commit-count edit-scratch wait-pending wait-commit"
    echo "             report summary"
    ;;
esac
