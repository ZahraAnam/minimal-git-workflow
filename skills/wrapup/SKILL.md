---
name: wrapup
description: Wrap up the session — commit any pending changes and stop git-auto cleanly.
---

Run this at the end of your Claude session to ensure clean git state before stopping.

## Step 1 — Check for pending handshake

Run:
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/handshake.py" status
```

If a pending commit exists, generate and write the commit message first
(follow the same steps as the commit command) before stopping.

## Step 2 — Check for uncommitted changes

Run:
```bash
git status --short
```

If there are uncommitted changes, inform the user:
"There are uncommitted changes. git-auto stop will warn about these."
Show the file list (short form only — no content).

## Step 3 — Stop git-auto

Run:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/stop-git-auto.sh"
```

Show the output to the user.

## Step 4 — Final git state

Run:
```bash
git log --oneline -3
git status --short
```

Report:
- Last 3 commits for confirmation
- Whether working tree is clean

## Step 5 — Confirm to user

Give a clear summary:
- "Session wrapped up. git-auto stopped. Working tree is clean."
- "Session wrapped up. git-auto stopped. Note: N uncommitted files remain — commit manually if needed."
