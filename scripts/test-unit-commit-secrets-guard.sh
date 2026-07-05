#!/usr/bin/env bash
# test-unit-commit-secrets-guard.sh
# Regression test for Pathway B's missing secrets guard.
#
# git-auto (Pathway A) scans the working tree for secret-looking files
# (git status --porcelain, not just staged) and aborts before `git add` if
# any are found (plugin-working.md:31). Pathway B's check-unit-complete.sh
# had no equivalent — it would write unit-check.json (triggering Claude's
# no-confirmation auto-commit) even when a secret-looking file was part of
# the dirty tree, staging and committing it along with everything else.
#
# Unlike git-auto's all-or-nothing abort, Pathway B excludes just the
# secret-looking file(s) from the auto-commit and proceeds with the rest —
# via a `secret_files_excluded` list on unit-check.json's payload — so a
# stray secret file doesn't block legitimate work from being committed, but
# never gets staged either.
#
# Asserts:
#   1. Mixed dirty tree (safe file + secret file): unit-check.json is still
#      written, lists the secret file under secret_files_excluded, and a
#      SECRETS_DETECTED marker names it.
#   2. No secrets: unit-check.json written as before, secret_files_excluded
#      empty.
#   3. Only a secret file dirty (nothing safe to commit): no unit-check.json
#      written at all — nothing to commit — but still surfaced via marker.

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

read_unit_check_json() {
  python3 -c "
import json
try:
    print(json.dumps(json.load(open('$REPO/.git/unit-check.json'))))
except Exception:
    print('{}')
"
}

PASS=true

echo "=== Scenario 1: secret file + safe file — excluded, not blocked ==="

echo '{"api_key": "abc123"}' > "$REPO/credentials.json"
EDITED_FILE="$REPO/src.py"
echo "print('hello')" > "$EDITED_FILE"

OUTPUT=$(cd "$REPO" && hook_input_for "$EDITED_FILE" | bash "$HOOK" 2>&1) || true

if [ -f "$REPO/.git/unit-check.json" ]; then
  echo "PASS: unit-check.json still written despite a secret-looking file present"
else
  echo "FAIL: unit-check.json missing — mixed dirty tree should not block the whole trigger"
  echo "--- output ---"
  echo "$OUTPUT"
  PASS=false
fi

JSON=$(read_unit_check_json)
if echo "$JSON" | grep -q "credentials.json"; then
  echo "PASS: unit-check.json's secret_files_excluded lists credentials.json"
else
  echo "FAIL: unit-check.json does not record credentials.json as excluded"
  echo "--- json ---"
  echo "$JSON"
  PASS=false
fi

if echo "$JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('files_changed'))" | grep -q "credentials.json"; then
  echo "FAIL: credentials.json also appears in files_changed — it must only be in secret_files_excluded, not treated as normal committable content"
  PASS=false
fi

if echo "$OUTPUT" | grep -q "SECRETS_DETECTED.*credentials\.json"; then
  echo "PASS: SECRETS_DETECTED marker surfaced, naming credentials.json"
else
  echo "FAIL: SECRETS_DETECTED marker missing or didn't name the file"
  echo "--- output ---"
  echo "$OUTPUT"
  PASS=false
fi

rm -f "$REPO/credentials.json" "$REPO/.git/unit-check.json" "$EDITED_FILE"
git -C "$REPO" clean -qfd

echo ""
echo "=== Scenario 2: no secrets present — unit-check.json unchanged behavior ==="

EDITED_FILE="$REPO/src.py"
echo "print('hello')" > "$EDITED_FILE"

OUTPUT=$(cd "$REPO" && hook_input_for "$EDITED_FILE" | bash "$HOOK" 2>&1) || true

if [ -f "$REPO/.git/unit-check.json" ]; then
  echo "PASS: unit-check.json written when no secrets are present"
else
  echo "FAIL: unit-check.json missing — secrets guard is blocking normal changes too"
  echo "--- output ---"
  echo "$OUTPUT"
  PASS=false
fi

JSON=$(read_unit_check_json)
if echo "$JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('secret_files_excluded'))" | grep -qx "\[\]"; then
  echo "PASS: secret_files_excluded is empty when nothing secret-looking changed"
else
  echo "FAIL: secret_files_excluded is not empty despite no secrets present"
  echo "--- json ---"
  echo "$JSON"
  PASS=false
fi

rm -f "$REPO/.git/unit-check.json" "$EDITED_FILE"
git -C "$REPO" clean -qfd

echo ""
echo "=== Scenario 3: only a secret file dirty — nothing safe to commit ==="

echo '{"api_key": "abc123"}' > "$REPO/credentials.json"

OUTPUT=$(cd "$REPO" && hook_input_for "$REPO/credentials.json" | bash "$HOOK" 2>&1) || true

if [ -f "$REPO/.git/unit-check.json" ]; then
  echo "FAIL: unit-check.json written despite nothing safe to commit"
  PASS=false
else
  echo "PASS: unit-check.json not written when only a secret file is dirty"
fi

if echo "$OUTPUT" | grep -q "SECRETS_DETECTED.*credentials\.json"; then
  echo "PASS: SECRETS_DETECTED marker still surfaced"
else
  echo "FAIL: SECRETS_DETECTED marker missing"
  echo "--- output ---"
  echo "$OUTPUT"
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
