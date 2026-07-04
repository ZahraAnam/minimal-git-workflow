#!/usr/bin/env bash
# test-wrapup-resolution.sh
# Regression test for the git/file mechanics behind the wrapup skill's Step 2
# three actions (commit+push / write catchup note / leave-as-is). The skill's
# AskUserQuestion can't be driven headlessly, so this test exercises the
# underlying git and file commands directly and asserts the resulting state.

set -euo pipefail

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

REMOTE="$WORKDIR/remote.git"
git init -q --bare "$REMOTE"

make_repo() {
  local name="$1"
  local repo="$WORKDIR/$name"
  git init -q "$repo"
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test"
  git -C "$repo" remote add origin "$REMOTE"
  git -C "$repo" checkout -q -b "$name"
  echo "init-$name" > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "init"
  git -C "$repo" push -q -u origin "$name"
  echo "$repo"
}

PASS=true

# --- Commit and push now ---
echo "=== Action: Commit and push now ==="
REPO_COMMIT=$(make_repo "commit-branch")
echo "uncommitted" >> "$REPO_COMMIT/README.md"

git -C "$REPO_COMMIT" add .
git -C "$REPO_COMMIT" commit -q -m "docs: wrap up pending README edit"
git -C "$REPO_COMMIT" push -q

DIRTY_AFTER=$(git -C "$REPO_COMMIT" status --short)
SUBJECT=$(git -C "$REPO_COMMIT" log -1 --format=%s)
REMOTE_SUBJECT=$(git -C "$REPO_COMMIT" log -1 --format=%s "origin/commit-branch")

if [ -z "$DIRTY_AFTER" ] && [ "$SUBJECT" = "docs: wrap up pending README edit" ] && [ "$REMOTE_SUBJECT" = "$SUBJECT" ]; then
  echo "PASS: commit+push clears the working tree and lands on the remote"
else
  echo "FAIL: expected clean tree and matching remote commit, got dirty='$DIRTY_AFTER' local='$SUBJECT' remote='$REMOTE_SUBJECT'"
  PASS=false
fi

# --- Write a catchup note ---
echo ""
echo "=== Action: Write a catchup note ==="
REPO_CATCHUP=$(make_repo "catchup-branch")
echo "uncommitted" >> "$REPO_CATCHUP/README.md"

CATCHUP_DIR="$REPO_CATCHUP/.claude/sessions/debug"
mkdir -p "$CATCHUP_DIR"
CATCHUP_FILE="$CATCHUP_DIR/20260704_1546_wrapup-debug.catchup.md"

{
  echo "## Catchup — unfinished at wrapup"
  echo ""
  git -C "$REPO_CATCHUP" status --short
  echo ""
  echo "## What's unfinished"
  echo "README edit in progress, not yet committed."
} > "$CATCHUP_FILE"

STILL_DIRTY=$(git -C "$REPO_CATCHUP" status --short -- README.md)

if [ -f "$CATCHUP_FILE" ] && grep -q "README.md" "$CATCHUP_FILE" && [ -n "$STILL_DIRTY" ]; then
  echo "PASS: catchup note written and working tree left uncommitted"
else
  echo "FAIL: expected catchup file with README reference and dirty tree, got file_exists=$([ -f "$CATCHUP_FILE" ] && echo yes || echo no) dirty='$STILL_DIRTY'"
  PASS=false
fi

# --- Leave as-is ---
echo ""
echo "=== Action: Leave as-is ==="
REPO_SKIP=$(make_repo "skip-branch")
echo "uncommitted" >> "$REPO_SKIP/README.md"

BEFORE=$(git -C "$REPO_SKIP" status --short)
# (no git operation — this IS the "leave as-is" action)
AFTER=$(git -C "$REPO_SKIP" status --short)

if [ -n "$BEFORE" ] && [ "$BEFORE" = "$AFTER" ]; then
  echo "PASS: leave-as-is performs no git operation, dirty state unchanged"
else
  echo "FAIL: expected unchanged dirty state, got before='$BEFORE' after='$AFTER'"
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
