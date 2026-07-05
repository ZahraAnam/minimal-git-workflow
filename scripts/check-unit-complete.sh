#!/usr/bin/env bash
# check-unit-complete.sh
# PostToolUse hook — fires after Edit/Write tool calls.
# Checks for uncommitted changes and writes unit-check.json to trigger Claude evaluation.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Resolve the repo from the edited file's path (tool_input.file_path), not the
# session's $PWD — Claude may edit files in a different repo than it started in.
HOOK_INPUT="$(cat)"
EDITED_FILE=$(printf '%s' "$HOOK_INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('tool_input', {}).get('file_path', ''))
except Exception:
    print('')
")

if [ -n "$EDITED_FILE" ]; then
  REPO_ROOT=$(git -C "$(dirname "$EDITED_FILE")" rev-parse --show-toplevel 2>/dev/null) || exit 0
else
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
fi

# Find config file
CONFIG_FILE=""
for ext in json toml yaml yml; do
  if [ -f "$REPO_ROOT/git-auto-config.$ext" ]; then
    CONFIG_FILE="$REPO_ROOT/git-auto-config.$ext"
    break
  fi
done

if [ -z "$CONFIG_FILE" ]; then
  exit 0
fi

# Check if unit_commit is enabled
UNIT_COMMIT_ENABLED=$(python3 -c "
import json, sys
try:
    c = json.load(open('$CONFIG_FILE'))
    print('true' if c.get('unit_commit', True) else 'false')
except:
    print('false')
" 2>/dev/null)

if [ "$UNIT_COMMIT_ENABLED" != "true" ]; then
  exit 0
fi

UNIT_CHECK="$REPO_ROOT/.git/unit-check.json"

# Don't overwrite a fresh unit-check.json — Claude hasn't responded to it yet.
# But one stuck past STALE_AFTER_SECONDS is orphaned (crash/interrupt mid-eval —
# the same failure mode start-git-auto.sh's STALE_UNIT_CHECK sweep handles at
# session start, just arriving mid-session instead). Clear it and fall through
# to regenerate from current state, instead of blocking detection forever.
STALE_AFTER_SECONDS=300
if [ -f "$UNIT_CHECK" ]; then
  CHECK_STATE=$(python3 -c "
import json, time
from datetime import datetime
try:
    d = json.load(open('$UNIT_CHECK'))
    age = int(time.time() - datetime.fromisoformat(d['timestamp']).timestamp())
    if age < $STALE_AFTER_SECONDS:
        print('FRESH')
    else:
        print(f\"STALE|{d.get('timestamp', 'unknown time')} | {age}s old | {d.get('stat_summary', 'changes detected')} | files: {', '.join(d.get('files_changed', []))}\")
except Exception:
    print('STALE|unreadable snapshot')
" 2>/dev/null)

  if [ "$CHECK_STATE" = "FRESH" ]; then
    exit 0
  fi

  STALE_INFO="${CHECK_STATE#STALE|}"
  echo "[minimal-git-workflow] STALE_UNIT_CHECK: orphaned check from earlier in this session ($STALE_INFO) — never evaluated. Clearing it and regenerating from current state." >&2
  rm -f "$UNIT_CHECK"
fi

# Check for uncommitted changes
PORCELAIN=$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)
CHANGED_COUNT=$(printf '%s\n' "$PORCELAIN" | grep -c . || true)

if [ "$CHANGED_COUNT" -eq 0 ]; then
  exit 0
fi

# Secrets guard — mirrors git-auto's own pre-commit scan (plugin-working.md:31)
# in spirit, but Pathway B excludes rather than aborts: since Claude commits
# with no confirmation gate, a secret-looking file must never be staged, but
# legitimate work sitting alongside it shouldn't be blocked from committing
# either. The excluded file(s) stay uncommitted and keep re-surfacing on
# every future edit until the user deals with them.
SECRET_FILES=()
while IFS= read -r line; do
  [ -z "$line" ] && continue
  path="${line:3}"
  base=$(basename "$path")
  lower=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    .env|.env.*|*.pem|*.key|*credentials*|*secrets*|id_rsa*|.netrc|.pgpass)
      SECRET_FILES+=("$path")
      ;;
  esac
done <<< "$PORCELAIN"

if [ "${#SECRET_FILES[@]}" -gt 0 ]; then
  echo "[minimal-git-workflow] SECRETS_DETECTED: excluding from auto-commit — ${SECRET_FILES[*]}. Left uncommitted; review and commit manually if intended." >&2
fi

SAFE_COUNT=$((CHANGED_COUNT - ${#SECRET_FILES[@]}))
if [ "$SAFE_COUNT" -le 0 ]; then
  exit 0
fi

# Write unit-check.json via handshake.py — cd into REPO_ROOT first since
# handshake.py resolves the repo via `git rev-parse --show-toplevel` from cwd.
(cd "$REPO_ROOT" && python3 "$PLUGIN_ROOT/scripts/handshake.py" write-unit-check "${SECRET_FILES[@]}") >/dev/null

echo "[minimal-git-workflow] unit-check.json written ($SAFE_COUNT changed file(s)) — watch-pending.sh will notify Claude." >&2
