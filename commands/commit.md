---
description: Generate a commit message using Claude's session context and write it for git-auto to pick up. Use when notified of a pending commit.
---

This command is the core of the Claude-plugin handshake. Claude generates a commit message
from its own session context — no raw diff is ever read into context.

## Step 1 — Read pending commit info

Run:
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/handshake.py" read-pending
```

This returns a small JSON object:
```json
{
  "branch": "feat/login",
  "files_changed": ["src/auth.py", "tests/test_auth.py"],
  "stat_summary": "2 files changed, 45 insertions(+), 3 deletions(-)",
  "timestamp": "2026-05-26T10:00:00"
}
```

If the output is `{}` or the file doesn't exist, tell the user:
"No pending commit found. git-auto hasn't hit a threshold yet."
Stop here.

## Step 2 — Generate commit message from session context

Using ONLY:
- The `stat_summary` and `files_changed` from the JSON above
- Your own knowledge of what was worked on in this session

Generate a conventional commit message:
- Format: `type(scope): description`
- Types: feat, fix, docs, refactor, chore, test, perf
- Subject line max 72 characters
- Scope = most relevant module or file area changed
- Do NOT read file contents or run git diff — use session context only

Example: `feat(auth): add login validation and session token handling`

## Step 3 — Write message for git-auto

Run immediately — no confirmation prompt:
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/handshake.py" write-message '<commit message>'
```

## Step 4 — Report

After writing, tell the user:
- What message was used
- That git-auto will now execute the commit
- Suggest running /minimal-git-workflow:status in a few seconds to confirm
