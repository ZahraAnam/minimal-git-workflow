---
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
- **Commit as WIP (no push)** — commits everything locally with a
  `wip:`-prefixed message describing what's unfinished, but doesn't push, so
  the next session can find and resume it
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

### Step 2b — Commit as WIP (no push)

Generate a commit message in the same conventional format as Step 2a, but
using a `wip` type and a body summarizing what's unfinished:
- Format: `wip(scope): description`
- Body: 1-3 sentences from session context — what's done, what's not,
  what's next
- Do NOT read file contents or run `git diff` — use session context and the
  file list from Step 2 only, same invariant as every commit-generating flow
  in this plugin

Run immediately — no confirmation prompt, no push:
```bash
git add .
git commit -m '<wip commit message>'
```

This deliberately does NOT push. The next session's `SessionStart` hook
already surfaces unpushed commits via `UNPUSHED_COMMITS` — no separate
tracking mechanism needed. Also, `catchup: true` only acts on the dirty
working tree, so a local, unpushed WIP commit is safe from being swept up
by it on the next session's start.

Tell the user: "Committed as WIP: `<message>` — not pushed. It'll be
flagged by `UNPUSHED_COMMITS` next session; run `/minimal-git-workflow:clean-slate`
to push, squash, or resume it."

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
