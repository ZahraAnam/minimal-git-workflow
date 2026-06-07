#!/usr/bin/env bash
# test-clean-slate.sh
# Regression test for the git mechanics behind the clean-slate skill's three
# actions (push / squash+push / leave-as-is). The skill's AskUserQuestion
# can't be driven headlessly, so this test exercises the underlying git
# commands directly and asserts the resulting repo state.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
  git -C "$repo" config push.default upstream
  git -C "$repo" remote add origin "$REMOTE"
  echo "init-$name" > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "init"
  git -C "$repo" push -q -u origin "HEAD:$name"
  echo "$repo"
}

unpushed_count() {
  git -C "$1" rev-list "@{u}..HEAD" --count
}

PASS=true

# --- Push now ---
echo "=== Action: Push now ==="
REPO_PUSH=$(make_repo "push-branch")
echo "a" >> "$REPO_PUSH/README.md"
git -C "$REPO_PUSH" commit -q -am "feat: a"
echo "b" >> "$REPO_PUSH/README.md"
git -C "$REPO_PUSH" commit -q -am "fix: b"
[ "$(unpushed_count "$REPO_PUSH")" -eq 2 ]

git -C "$REPO_PUSH" push -q

if [ "$(unpushed_count "$REPO_PUSH")" -eq 0 ]; then
  echo "PASS: push now clears unpushed count"
else
  echo "FAIL: expected 0 unpushed after push, got $(unpushed_count "$REPO_PUSH")"
  PASS=false
fi

# --- Squash into one ---
echo ""
echo "=== Action: Squash into one ==="
REPO_SQUASH=$(make_repo "squash-branch")
echo "a" >> "$REPO_SQUASH/README.md"
git -C "$REPO_SQUASH" commit -q -am "feat: a"
echo "b" >> "$REPO_SQUASH/README.md"
git -C "$REPO_SQUASH" commit -q -am "fix: b"
[ "$(unpushed_count "$REPO_SQUASH")" -eq 2 ]

git -C "$REPO_SQUASH" reset -q --soft '@{u}'
git -C "$REPO_SQUASH" commit -q -m "feat: squashed a and b"
git -C "$REPO_SQUASH" push -q

SQUASH_COUNT=$(unpushed_count "$REPO_SQUASH")
SQUASH_SUBJECT=$(git -C "$REPO_SQUASH" log -1 --format=%s)

if [ "$SQUASH_COUNT" -eq 0 ] && [ "$SQUASH_SUBJECT" = "feat: squashed a and b" ]; then
  echo "PASS: squash collapses to one pushed commit with the new message"
else
  echo "FAIL: expected 0 unpushed / 'feat: squashed a and b', got $SQUASH_COUNT / '$SQUASH_SUBJECT'"
  PASS=false
fi

# --- Leave as-is ---
echo ""
echo "=== Action: Leave as-is ==="
REPO_SKIP=$(make_repo "skip-branch")
echo "a" >> "$REPO_SKIP/README.md"
git -C "$REPO_SKIP" commit -q -am "feat: a"
echo "b" >> "$REPO_SKIP/README.md"
git -C "$REPO_SKIP" commit -q -am "fix: b"

BEFORE=$(unpushed_count "$REPO_SKIP")
# (no git operation — this IS the "leave as-is" action)
AFTER=$(unpushed_count "$REPO_SKIP")

if [ "$BEFORE" -eq 2 ] && [ "$AFTER" -eq 2 ]; then
  echo "PASS: leave-as-is performs no git operation, count unchanged (2)"
else
  echo "FAIL: expected unchanged count of 2, got before=$BEFORE after=$AFTER"
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
