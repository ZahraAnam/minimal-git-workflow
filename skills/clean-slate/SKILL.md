---
name: clean-slate
description: Detect unpushed commits and let the user choose what to do with them (push, squash, or leave as-is) before starting a session or applying a config change. Ensures a known-clean state before git-auto begins operating.
---

This skill is invoked from two places:
- `start-git-auto.sh` (SessionStart), when it prints an `UNPUSHED_COMMITS:` marker
- `/minimal-git-workflow:configure`, before reading or writing `git-auto-config.json`

It can also be run manually at any time.

## Step 1 — Detect unpushed commits

Run:
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/handshake.py" unpushed-status
```

If `count` is `0` (including the no-upstream case where `upstream` is `null`):
silent no-op — say nothing, return control to the calling flow immediately.

## Step 2 — Ask the user what to do

If `count > 0`, use `AskUserQuestion` with the branch name, upstream, and the
`subjects` list (commit subjects only — never diffs) shown to the user, and
these three options:

- **Push now (recommended)** — pushes the unpushed commits as-is
- **Squash into one** — combines them into a single commit, then pushes
- **Leave as-is** — does nothing, continues with the existing history

## Step 3a — Push now

```bash
git push
```

If this fails (diverged remote, auth error, etc.), surface the exact error
text to the user. Do NOT retry automatically and do NOT force-push — let the
user resolve it manually, then re-run this skill if they want.

On success, tell the user: "Pushed `<count>` commit(s) to `<upstream>`."

## Step 3b — Squash into one

```bash
git reset --soft @{u}
```

This un-commits (but keeps staged) all unpushed changes, leaving HEAD at the
upstream commit. Then generate ONE conventional commit message summarizing the
work, using ONLY:
- The collected `subjects` from Step 1
- Your own knowledge of the session's work (if any of these commits happened
  in this session)

Do NOT read file contents or run `git diff` — same invariant as every other
commit-generating flow in this plugin.

```bash
git commit -m '<squashed commit message>'
git push
```

Tell the user: "Squashed `<count>` commits into one and pushed: `<message>`"

If the push fails, surface the error — do not force-push.

## Step 3c — Leave as-is

No git operations. Tell the user: "Leaving `<count>` unpushed commit(s) as-is."

## Step 4 — Hand back control

Whichever branch was taken, this skill's job is done — return control to
whichever flow invoked it (SessionStart continues to `MONITOR_REQUIRED`,
`/configure` continues to its Step 1).
