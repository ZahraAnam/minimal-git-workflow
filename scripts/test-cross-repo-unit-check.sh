#!/usr/bin/env bash
# test-cross-repo-unit-check.sh
# Regression test for check-unit-complete.sh REPO_ROOT resolution.
#
# Bug: the hook used `git rev-parse --show-toplevel` against the session's
# $PWD instead of the edited file's path (tool_input.file_path). When Claude
# edits a file in a *different* repo than the session started in, the hook
# silently no-ops (or worse, writes unit-check.json into the wrong repo).
#
# This test simulates that exact scenario: cwd = repo-a, edited file = repo-b.
# Asserts unit-check.json lands in repo-b/.git/, never repo-a/.git/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/check-unit-complete.sh"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

REPO_A="$WORKDIR/repo-a"
REPO_B="$WORKDIR/repo-b"

setup_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test"
  echo "init" > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "init"
}

setup_repo "$REPO_A"
setup_repo "$REPO_B"

# repo-b is the one with unit_commit enabled
cat > "$REPO_B/git-auto-config.json" <<'EOF'
{"start": {"files_threshold": 999}, "unit_commit": true}
EOF
git -C "$REPO_B" add git-auto-config.json
git -C "$REPO_B" commit -q -m "add config"

# Simulate Claude editing a file in repo-b while the session's cwd is repo-a
EDITED_FILE="$REPO_B/src.py"
echo "print('hello')" > "$EDITED_FILE"

HOOK_INPUT=$(python3 -c "
import json
print(json.dumps({'tool_name': 'Write', 'tool_input': {'file_path': '$EDITED_FILE'}}))
")

PASS=true

echo "=== Cross-repo unit-check resolution ==="
echo "cwd      : $REPO_A"
echo "edited   : $EDITED_FILE (repo-b)"
echo ""

(cd "$REPO_A" && echo "$HOOK_INPUT" | bash "$HOOK") || true

if [ -f "$REPO_B/.git/unit-check.json" ]; then
  echo "PASS: unit-check.json written to repo-b/.git/ (correct repo)"
else
  echo "FAIL: unit-check.json missing from repo-b/.git/"
  PASS=false
fi

if [ -f "$REPO_A/.git/unit-check.json" ]; then
  echo "FAIL: unit-check.json incorrectly written to repo-a/.git/ (session cwd)"
  PASS=false
else
  echo "PASS: repo-a/.git/ untouched"
fi

echo ""
if $PASS; then
  echo "=== ALL CHECKS PASSED ==="
  exit 0
else
  echo "=== FAILURES DETECTED ==="
  exit 1
fi
