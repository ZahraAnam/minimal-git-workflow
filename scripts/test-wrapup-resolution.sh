#!/usr/bin/env bash
# test-wrapup-resolution.sh
# Regression test for the git/file mechanics behind the wrapup skill's Step 2
# three actions (commit+push / commit as WIP, no push / leave-as-is). The
# skill's AskUserQuestion can't be driven headlessly, so this test exercises
# the underlying git and file commands directly and asserts the resulting
# state.

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

# --- Commit as WIP (no push) ---
echo ""
echo "=== Action: Commit as WIP (no push) ==="
REPO_WIP=$(make_repo "wip-branch")
echo "uncommitted" >> "$REPO_WIP/README.md"

git -C "$REPO_WIP" add .
git -C "$REPO_WIP" commit -q -m "wip(readme): finish edit next session

README edit in progress, not yet complete."

DIRTY_AFTER=$(git -C "$REPO_WIP" status --short)
SUBJECT=$(git -C "$REPO_WIP" log -1 --format=%s)
UNPUSHED=$(git -C "$REPO_WIP" rev-list '@{u}..HEAD' --count)

if [ -z "$DIRTY_AFTER" ] && [ "$SUBJECT" = "wip(readme): finish edit next session" ] && [ "$UNPUSHED" -eq 1 ]; then
  echo "PASS: WIP commit clears the working tree and stays unpushed locally"
else
  echo "FAIL: expected clean tree, wip commit subject, and 1 unpushed commit, got dirty='$DIRTY_AFTER' subject='$SUBJECT' unpushed=$UNPUSHED"
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
