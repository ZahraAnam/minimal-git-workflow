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

If there are no uncommitted changes, skip to Step 3.

If there are uncommitted changes, use `AskUserQuestion` with the short-form
file list (no content) shown to the user, and these three options:

- **Commit and push now (recommended)** — commits everything with an
  auto-generated message and pushes
- **Write a catchup note** — leaves the working tree as-is, but saves a note
  describing what's unfinished so the next session can pick it up
- **Leave as-is** — does nothing, continues with the existing uncommitted
  state

### Step 2a — Commit and push now

Generate a conventional commit message:
- Format: `type(scope): description`
- Types: feat, fix, docs, refactor, chore, test, perf
- Subject line max 72 characters
- Scope = most relevant module or file area changed
- Do NOT read file contents or run `git diff` — use session context and the
  file list from Step 2 only

Run immediately — no confirmation prompt:
```bash
git add .
git commit -m '<commit message>'
git push
```

If push fails (diverged remote, auth error, etc.), surface the exact error
text to the user. Do NOT retry automatically and do NOT force-push — let the
user resolve it manually.

Tell the user: "Committed: `<message>` — pushed."

### Step 2b — Write a catchup note

Reuse the same session summary path from the session instructions (same
directory and timestamp), but swap the `.summary.md` suffix for
`.catchup.md`, e.g.:
`.claude/sessions/<group>/<timestamp>_<name>.catchup.md`

Content:
```markdown
## Catchup — unfinished at wrapup

<git status --short output>

## What's unfinished
<1-3 sentences from session context — what's done, what's not, what's next>
```

Do NOT read file contents or run `git diff` for this — same invariant as
every commit-generating flow in this plugin: summarize from session context
only.

Tell the user: "Wrote catchup note to `<path>`. Working tree left
uncommitted."

### Step 2c — Leave as-is

No git operations. Tell the user:
"Leaving uncommitted changes as-is. git-auto stop will warn about these."

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
