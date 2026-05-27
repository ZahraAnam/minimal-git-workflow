---
description: Show git-auto monitor status, current branch, pending commits, and handshake state.
---

## Step 1 — git-auto process status

Run:
```bash
git-auto status
```

Show the output — this covers PID, branch, mode, thresholds.

## Step 2 — Handshake status

Run:
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/handshake.py" status
```

Report:
- Whether a commit message is pending (pending-commit.json exists)
- Whether a commit message has already been written (commit-message.txt exists)
- Branch and stat_summary from pending file if present

## Step 3 — Git state summary

Run:
```bash
git status --short
git log --oneline -5
```

Show:
- Number of uncommitted files (not full content)
- Last 5 commit messages for context

## Step 4 — Summarize

Give the user a clear one-line summary:
- "git-auto is running. No pending commits."
- "git-auto is running. Commit pending — run /minimal-git-workflow:commit"
- "git-auto is not running — run /minimal-git-workflow:configure to set up, or check SessionStart hook."
