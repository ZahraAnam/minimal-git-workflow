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
rm -f "$REPO_ROOT/.git/unit-check.json"

# Run git-auto stop scoped to this project path.
# --force: without it, git-auto stop blocks on an interactive "Stop anyway?"
# confirm whenever uncommitted/unpushed work exists. In Claude's non-interactive
# shell that confirm gets no stdin and silently aborts the stop — the daemon
# keeps running while this script reports success/failure based on the wrong
# signal. wrapup.md already surfaces those warnings to the user beforehand,
# so the confirm here is redundant.
if command -v git-auto &>/dev/null; then
  git-auto stop --path "$REPO_ROOT" --force && \
    echo "[minimal-git-workflow] git-auto stopped for $REPO_ROOT." >&2 || \
    echo "[minimal-git-workflow] git-auto was not running for $REPO_ROOT." >&2
else
  echo "[minimal-git-workflow] git-auto not found in PATH." >&2
  exit 1
fi
