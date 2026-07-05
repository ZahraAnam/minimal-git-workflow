#!/usr/bin/env bash
# test-unit-commit-default-fallback.sh
# Regression test: a git-auto-config.json that omits the `unit_commit` key
# entirely must be treated as unit_commit: true (Pathway B enabled) — not
# false. Also guards that an explicit `unit_commit: false` is still honored.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/check-unit-complete.sh"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

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

run_hook() {
  local repo="$1"
  local edited_file="$repo/src.py"
  echo "print('hello')" > "$edited_file"
  local hook_input
  hook_input=$(python3 -c "
import json
print(json.dumps({'tool_name': 'Write', 'tool_input': {'file_path': '$edited_file'}}))
")
  (cd "$repo" && echo "$hook_input" | bash "$HOOK") || true
}

PASS=true

# --- Case 1: unit_commit key omitted entirely -> must behave as true ---
REPO_MISSING="$WORKDIR/repo-missing-key"
setup_repo "$REPO_MISSING"
cat > "$REPO_MISSING/git-auto-config.json" <<'EOF'
{"start": {"files_threshold": 15}}
EOF
git -C "$REPO_MISSING" add git-auto-config.json
git -C "$REPO_MISSING" commit -q -m "add config"

run_hook "$REPO_MISSING"

echo "=== Case 1: unit_commit key missing entirely ==="
if [ -f "$REPO_MISSING/.git/unit-check.json" ]; then
  echo "PASS: missing unit_commit key treated as enabled (unit-check.json written)"
else
  echo "FAIL: missing unit_commit key was NOT treated as enabled"
  PASS=false
fi
echo ""

# --- Case 2: unit_commit explicitly false -> must stay disabled ---
REPO_FALSE="$WORKDIR/repo-explicit-false"
setup_repo "$REPO_FALSE"
cat > "$REPO_FALSE/git-auto-config.json" <<'EOF'
{"start": {"files_threshold": 3}, "unit_commit": false}
EOF
git -C "$REPO_FALSE" add git-auto-config.json
git -C "$REPO_FALSE" commit -q -m "add config"

run_hook "$REPO_FALSE"

echo "=== Case 2: unit_commit explicitly false ==="
if [ -f "$REPO_FALSE/.git/unit-check.json" ]; then
  echo "FAIL: explicit unit_commit:false was NOT respected (unit-check.json written anyway)"
  PASS=false
else
  echo "PASS: explicit unit_commit:false still disables Pathway B"
fi
echo ""

if $PASS; then
  echo "=== ALL CHECKS PASSED ==="
  exit 0
else
  echo "=== FAILURES DETECTED ==="
  exit 1
fi
