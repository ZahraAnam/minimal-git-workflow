#!/usr/bin/env bash
# test-unit-check-mid-session-staleness.sh
# Regression test for check-unit-complete.sh's mid-session unit-check.json
# staleness sweep (STALE_AFTER_SECONDS=300, added in PR #6 per
# development-details.md:123-128).
#
# The original stale-unit-check.json fix (PR #5) only swept at SessionStart
# (start-git-auto.sh) — a check-unit-complete.sh guard that "refuses to
# overwrite an existing unit-check.json, trusting Claude to clear it" would
# still wedge Pathway B forever if the file went stale *mid-session* (e.g.
# Claude never evaluated it and the session kept running). PR #6 widened the
# sweep into check-unit-complete.sh itself, aging the existing file against
# its own timestamp. That mid-session path had no dedicated regression test
# until now — only the SessionStart sweep (test-start-git-auto.sh) is
# covered.
#
# Asserts:
#   1. A unit-check.json older than 300s is surfaced via STALE_UNIT_CHECK,
#      cleared, and regenerated from current repo state.
#   2. A unit-check.json within 300s (fresh) is left untouched — the hook
#      exits without overwriting it, so Claude's in-flight evaluation isn't
#      clobbered.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/check-unit-complete.sh"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

REPO="$WORKDIR/repo"
mkdir -p "$REPO"
git init -q "$REPO"
git -C "$REPO" config user.email "test@example.com"
git -C "$REPO" config user.name "Test"
echo "init" > "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -q -m "init"

cat > "$REPO/git-auto-config.json" <<'EOF'
{"start": {"files_threshold": 999}, "unit_commit": true}
EOF
git -C "$REPO" add git-auto-config.json
git -C "$REPO" commit -q -m "add config"

hook_input_for() {
  local edited_file="$1"
  python3 -c "
import json
print(json.dumps({'tool_name': 'Write', 'tool_input': {'file_path': '$edited_file'}}))
"
}

PASS=true

echo "=== Scenario 1: unit-check.json older than 300s is swept mid-session ==="

STALE_TS=$(python3 -c "
from datetime import datetime, timedelta
print((datetime.now() - timedelta(seconds=400)).isoformat())
")
cat > "$REPO/.git/unit-check.json" <<EOF
{
  "branch": "feature-x",
  "files_changed": ["old.py"],
  "stat_summary": "1 file changed",
  "timestamp": "$STALE_TS"
}
EOF

EDITED_FILE="$REPO/new.py"
echo "print('hello')" > "$EDITED_FILE"

OUTPUT=$(cd "$REPO" && hook_input_for "$EDITED_FILE" | bash "$HOOK" 2>&1) || true

if echo "$OUTPUT" | grep -q "STALE_UNIT_CHECK:.*feature-x\|STALE_UNIT_CHECK:.*old.py"; then
  echo "PASS: mid-session stale unit-check.json surfaced via STALE_UNIT_CHECK marker"
else
  echo "FAIL: STALE_UNIT_CHECK marker missing or didn't carry forward stale info"
  echo "--- output ---"
  echo "$OUTPUT"
  PASS=false
fi

if [ -f "$REPO/.git/unit-check.json" ]; then
  NEW_FILES=$(python3 -c "import json; print(json.load(open('$REPO/.git/unit-check.json')).get('files_changed'))")
  if echo "$NEW_FILES" | grep -q "new.py"; then
    echo "PASS: unit-check.json regenerated from current repo state (new.py present)"
  else
    echo "FAIL: unit-check.json was not regenerated with current changes"
    echo "--- contents ---"
    cat "$REPO/.git/unit-check.json"
    PASS=false
  fi
else
  echo "FAIL: unit-check.json missing after sweep — should have regenerated, not just deleted"
  PASS=false
fi

rm -f "$REPO/.git/unit-check.json" "$EDITED_FILE"
git -C "$REPO" clean -qfd

echo ""
echo "=== Scenario 2: unit-check.json within 300s (fresh) is left untouched ==="

FRESH_TS=$(python3 -c "
from datetime import datetime, timedelta
print((datetime.now() - timedelta(seconds=30)).isoformat())
")
cat > "$REPO/.git/unit-check.json" <<EOF
{
  "branch": "feature-y",
  "files_changed": ["pending.py"],
  "stat_summary": "1 file changed",
  "timestamp": "$FRESH_TS"
}
EOF

EDITED_FILE="$REPO/another.py"
echo "print('world')" > "$EDITED_FILE"

OUTPUT=$(cd "$REPO" && hook_input_for "$EDITED_FILE" | bash "$HOOK" 2>&1) || true

if echo "$OUTPUT" | grep -q "STALE_UNIT_CHECK"; then
  echo "FAIL: fresh unit-check.json incorrectly treated as stale"
  echo "--- output ---"
  echo "$OUTPUT"
  PASS=false
else
  echo "PASS: fresh unit-check.json not flagged as stale"
fi

CURRENT_BRANCH=$(python3 -c "import json; print(json.load(open('$REPO/.git/unit-check.json')).get('branch'))" 2>/dev/null || echo "")
if [ "$CURRENT_BRANCH" = "feature-y" ]; then
  echo "PASS: fresh unit-check.json left untouched (original content preserved)"
else
  echo "FAIL: fresh unit-check.json was overwritten despite being within the TTL"
  echo "--- contents ---"
  cat "$REPO/.git/unit-check.json" 2>/dev/null || echo "(missing)"
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
