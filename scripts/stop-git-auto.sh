#!/usr/bin/env bash
# stop-git-auto.sh
# Gracefully stops git-auto for the CURRENT PROJECT only.
# Multiple projects can run git-auto simultaneously — this only stops the one
# matching the current repo root.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "[minimal-git-workflow] Not a git repo." >&2
  exit 1
}

echo "[minimal-git-workflow] Stopping git-auto for $REPO_ROOT" >&2

# Clean up any stale handshake files for this project
rm -f "$REPO_ROOT/.git/pending-commit.json"
rm -f "$REPO_ROOT/.git/commit-message.txt"

# Surface unit-check.json's contents before removing it — mirrors
# start-git-auto.sh's STALE_UNIT_CHECK sweep. Without this, a unit-check.json
# still pending at wrapup time (dirty tree detected but never evaluated by
# Claude) was deleted silently, losing the uncommitted-work trail; wrapup's
# own `git status --short` check still catches the underlying files, but the
# handshake's own record of them disappeared with no trace.
UNIT_CHECK="$REPO_ROOT/.git/unit-check.json"
if [ -f "$UNIT_CHECK" ]; then
  UNIT_CHECK_INFO=$(python3 -c "
import json
try:
    d = json.load(open('$UNIT_CHECK'))
    print(f\"{d.get('timestamp', 'unknown time')} | {d.get('stat_summary', 'changes detected')} | files: {', '.join(d.get('files_changed', []))}\")
except Exception:
    print('unreadable snapshot')
" 2>/dev/null)
  echo "[minimal-git-workflow] UNIT_CHECK: pending check being cleared on stop ($UNIT_CHECK_INFO) — if uncommitted changes remain, review them before ending the session." >&2
  rm -f "$UNIT_CHECK"
fi

# Capture the PID before stopping — git-auto stop sends SIGINT, but a daemon
# launched via `nohup ... &` inherits SIGINT/SIGQUIT forced to SIG_IGN by bash's
# job-control rules. SIGINT against a SIG_IGN process is a structural no-op:
# git-auto stop reports success unconditionally without re-checking the PID.
# We verify for real below and escalate to SIGTERM (not maskable this way) if
# the daemon survived. (Newly started daemons reset these traps — see
# start-git-auto.sh — but old/already-running ones may still carry the mask.)
STATE_FILE="$REPO_ROOT/.git/git-auto-state.json"
PRIOR_PID=""
if [ -f "$STATE_FILE" ]; then
  # CHANGED: a racing writer (e.g. an orphaned prior daemon instance
  # overlapping a newly started one — see automate-git-commands commit
  # b0a6b42) can leave this file as a complete, valid JSON object followed
  # by a stale trailing fragment from a longer previous write. The old
  # `except Exception: print('')` treated that unparseable-as-a-whole file
  # as "no PID", which meant PRIOR_PID came back empty and this script fell
  # straight to its "wasn't running" branch below — a false negative that
  # left a live daemon running untouched. Try a lenient parse (recover the
  # leading valid object) first, and only fall back to a live process-table
  # lookup (pgrep) if even that fails, instead of silently giving up.
  PRIOR_PID=$(python3 -c "
import json, subprocess, sys

path = '$STATE_FILE'
repo_root = '$REPO_ROOT'

def find_running_pid(repo_path):
    try:
        out = subprocess.check_output(
            ['pgrep', '-f', f'git-auto start --path {repo_path}'],
            stderr=subprocess.DEVNULL,
        ).decode('utf-8').strip()
    except subprocess.CalledProcessError:
        return None
    pids = [int(p) for p in out.splitlines() if p.strip()]
    return pids[0] if pids else None

try:
    text = open(path).read()
    try:
        state = json.loads(text)
    except json.JSONDecodeError:
        state, _ = json.JSONDecoder().raw_decode(text)
    print(state.get('pid') or '')
except Exception as e:
    print(f'[minimal-git-workflow] Could not parse state file ({e}); falling back to process check.', file=sys.stderr)
    print(find_running_pid(repo_root) or '')
")
fi

# Run git-auto stop scoped to this project path.
# --force: without it, git-auto stop blocks on an interactive "Stop anyway?"
# confirm whenever uncommitted/unpushed work exists. In Claude's non-interactive
# shell that confirm gets no stdin and silently aborts the stop — the daemon
# keeps running while this script reports success/failure based on the wrong
# signal. wrapup.md already surfaces those warnings to the user beforehand,
# so the confirm here is redundant.
if command -v git-auto &>/dev/null; then
  git-auto stop --path "$REPO_ROOT" --force >&2 || true
else
  echo "[minimal-git-workflow] git-auto not found in PATH." >&2
  exit 1
fi

# Verify the daemon actually died — don't trust git-auto stop's report.
# Give SIGINT a real grace window first: the daemon's signal handler runs
# observer.stop() + observer.join() + a state-file rewrite before exiting,
# which takes a beat — checking immediately would false-positive into an
# unnecessary SIGTERM escalation.
if [ -n "$PRIOR_PID" ]; then
  for _ in 1 2 3 4 5 6; do
    kill -0 "$PRIOR_PID" 2>/dev/null || break
    sleep 0.5
  done
fi
if [ -n "$PRIOR_PID" ] && kill -0 "$PRIOR_PID" 2>/dev/null; then
  echo "[minimal-git-workflow] PID $PRIOR_PID survived SIGINT (likely masked to SIG_IGN by bash job control) — escalating to SIGTERM." >&2
  kill -TERM "$PRIOR_PID" 2>/dev/null || true
  for _ in 1 2 3 4; do
    sleep 0.5
    kill -0 "$PRIOR_PID" 2>/dev/null || break
  done
  if kill -0 "$PRIOR_PID" 2>/dev/null; then
    echo "[minimal-git-workflow] PID $PRIOR_PID still alive after SIGTERM — forcing SIGKILL." >&2
    kill -KILL "$PRIOR_PID" 2>/dev/null || true
    sleep 0.5
  fi
fi

if [ -n "$PRIOR_PID" ] && kill -0 "$PRIOR_PID" 2>/dev/null; then
  echo "[minimal-git-workflow] FAILED to stop git-auto (PID $PRIOR_PID still running) for $REPO_ROOT." >&2
  exit 1
elif [ -n "$PRIOR_PID" ]; then
  echo "[minimal-git-workflow] git-auto stopped for $REPO_ROOT (PID $PRIOR_PID confirmed dead)." >&2
else
  echo "[minimal-git-workflow] git-auto was not running for $REPO_ROOT." >&2
fi
