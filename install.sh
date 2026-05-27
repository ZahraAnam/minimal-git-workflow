#!/usr/bin/env bash
# install.sh
# Installs minimal-git-workflow plugin and its git-auto dependency.
# Run from the plugin repo root.

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_PLUGINS_DIR="$HOME/.claude/plugins"
PLUGIN_LINK="$CLAUDE_PLUGINS_DIR/minimal-git-workflow"
GIT_AUTO_REPO="https://github.com/ZahraAnam/automate-git-commands"
GIT_AUTO_DIR="$HOME/workdir/repositories/automate-git-commands"

echo "[install] minimal-git-workflow installer"
echo ""

# --- Step 1: git-auto ---
echo "[install] Checking git-auto..."

if command -v git-auto &>/dev/null; then
  echo "[install] git-auto already on PATH — skipping install."
else
  echo "[install] git-auto not found. Installing from $GIT_AUTO_REPO"

  if [ -d "$GIT_AUTO_DIR/.git" ]; then
    echo "[install] Repo exists — pulling latest."
    git -C "$GIT_AUTO_DIR" pull --ff-only
  else
    echo "[install] Cloning into $GIT_AUTO_DIR"
    git clone "$GIT_AUTO_REPO" "$GIT_AUTO_DIR"
  fi

  echo "[install] Installing git-auto (pip install -e)..."
  if command -v uv &>/dev/null; then
    uv pip install -e "$GIT_AUTO_DIR"
  else
    pip install -e "$GIT_AUTO_DIR"
  fi

  if ! command -v git-auto &>/dev/null; then
    echo "[install] ERROR: git-auto still not found on PATH after install." >&2
    echo "[install] You may need to activate your virtualenv or add pip's bin dir to PATH." >&2
    exit 1
  fi

  echo "[install] git-auto installed: $(git-auto --version 2>/dev/null || echo 'version unknown')"
fi

# --- Step 2: plugin symlink ---
echo ""
echo "[install] Linking plugin to $PLUGIN_LINK"

mkdir -p "$CLAUDE_PLUGINS_DIR"

if [ -L "$PLUGIN_LINK" ]; then
  CURRENT_TARGET=$(readlink "$PLUGIN_LINK")
  if [ "$CURRENT_TARGET" = "$PLUGIN_DIR" ]; then
    echo "[install] Symlink already correct — nothing to do."
  else
    echo "[install] Replacing existing symlink (was: $CURRENT_TARGET)"
    rm "$PLUGIN_LINK"
    ln -s "$PLUGIN_DIR" "$PLUGIN_LINK"
  fi
elif [ -d "$PLUGIN_LINK" ]; then
  echo "[install] WARNING: $PLUGIN_LINK is a real directory, not a symlink."
  echo "[install] Backup it up first, then re-run. Aborting."
  exit 1
else
  ln -s "$PLUGIN_DIR" "$PLUGIN_LINK"
fi

echo "[install] Plugin linked: $PLUGIN_LINK -> $PLUGIN_DIR"

# --- Done ---
echo ""
echo "[install] Done. Restart Claude Code to activate the plugin."
echo "[install] Then run /minimal-git-workflow:configure in a session to create git-auto-config.json."
