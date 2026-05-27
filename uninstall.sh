#!/usr/bin/env bash
# uninstall.sh
# Removes the minimal-git-workflow plugin symlink from ~/.claude/plugins/.
# Does NOT uninstall git-auto (shared tool, may be used elsewhere).

set -euo pipefail

PLUGIN_LINK="$HOME/.claude/plugins/minimal-git-workflow"

echo "[uninstall] minimal-git-workflow uninstaller"
echo ""

if [ -L "$PLUGIN_LINK" ]; then
  rm "$PLUGIN_LINK"
  echo "[uninstall] Removed symlink: $PLUGIN_LINK"
elif [ -d "$PLUGIN_LINK" ]; then
  echo "[uninstall] $PLUGIN_LINK is a real directory — not removing automatically."
  echo "[uninstall] Delete it manually if you want to fully remove the plugin."
  exit 1
else
  echo "[uninstall] Plugin not installed at $PLUGIN_LINK — nothing to do."
fi

echo ""
echo "[uninstall] Done. Note: git-auto was NOT uninstalled (run 'pip uninstall git-auto' manually if needed)."
