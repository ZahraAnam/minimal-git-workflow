---
description: Evaluate whether the current uncommitted changes represent a complete logical unit. If yes, generate a commit message from session context and commit. If no, dismiss the check and continue working.
---

This command is triggered automatically when `watch-pending.sh` detects a `unit-check.json` file,
which is written by `check-unit-complete.sh` after each file edit when `unit_commit: true` is set.
It can also be run manually at any time to evaluate and commit pending work.

## Step 1 — Read unit-check info

Run:
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/handshake.py" read-unit-check
```

If the output is `{}` or the file doesn't exist, tell the user:
"No unit check pending. Either `unit_commit` is disabled or no changes detected."
Stop here.

## Step 2 — Evaluate: is this a complete logical unit?

Using ONLY:
- The `stat_summary` and `files_changed` from the JSON above
- Your own knowledge of what was worked on in this session

Ask yourself: **"Did I just finish a self-contained piece of work?"**

Examples of a complete logical unit:
- Implemented a full feature (function/class/module + its tests)
- Fixed a bug end-to-end (found root cause, applied fix, verified)
- Completed a refactor (renamed, restructured, or simplified a component)
- Finished a documentation update or configuration change
- Reached a stable checkpoint mid-task (e.g., "auth flow works, moving to session management")

Examples that are NOT a complete logical unit:
- Half-way through implementing a feature — more edits expected imminently
- Just added an import or a stub placeholder
- Mid-refactor with broken state
- Minor formatting or whitespace only

**Make a clear yes/no decision.** If uncertain, lean toward no — the check will re-trigger on the next edit.

## Step 3a — If YES: generate and commit

Generate a conventional commit message:
- Format: `type(scope): description`
- Types: feat, fix, docs, refactor, chore, test, perf
- Subject line max 72 characters
- Scope = most relevant module or file area changed
- Do NOT read file contents or run git diff — use session context only

If `secret_files_excluded` from Step 1's JSON is non-empty, stage everything
except those files (they must never be staged or committed):
```bash
git add . -- ':(exclude)<path1>' ':(exclude)<path2>'
```
Otherwise:
```bash
git add .
```

Run immediately — no confirmation prompt:
```bash
git commit -m '<commit message>'
```

If `secret_files_excluded` was non-empty, append to the commit-confirmation
message: "(left `<path1>`, `<path2>` uncommitted — looked like secrets)".

Then clear the unit-check:
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/handshake.py" clear-unit-check
```

Then check if push is needed. Read push_threshold from config:
```bash
python3 -c "
import json
try:
    c = json.load(open('git-auto-config.json'))
    print(c.get('start', {}).get('push_threshold', 0))
except:
    print(0)
"
```

If push_threshold > 0, count unpushed commits:
```bash
git rev-list @{u}..HEAD --count 2>/dev/null || echo 0
```

If unpushed count >= push_threshold, run:
```bash
git push
```

Confirm to the user:
- Committed and pushed: "Committed and pushed."
- Committed only: "Committed. (Push disabled or threshold not yet reached.)"

## Step 3b — If NO: dismiss and continue

Clear the unit-check file so the monitor resets:
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/handshake.py" clear-unit-check
```

Tell the user: "Not a complete unit yet — continuing. Will check again after next edit."
No commit is made. The check will re-trigger automatically on the next file modification.
