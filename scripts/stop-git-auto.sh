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

# Run git-auto stop scoped to this project path
if command -v git-auto &>/dev/null; then
  git-auto stop --path "$REPO_ROOT" && \
    echo "[minimal-git-workflow] git-auto stopped for $REPO_ROOT." >&2 || \
    echo "[minimal-git-workflow] git-auto was not running for $REPO_ROOT." >&2
else
  echo "[minimal-git-workflow] git-auto not found in PATH." >&2
  exit 1
fi
