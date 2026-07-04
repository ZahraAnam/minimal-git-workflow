# Report: wrapup catchup notes are never surfaced, and race with `catchup: true`

Date: 2026-07-04
Scope: investigation only — no code changed. Proposed fixes below are for review.

## Issue 1 — "Write a catchup note" is a write-only mechanism

### What happens today

`/minimal-git-workflow:wrapup` (`commands/wrapup.md` / `skills/wrapup/SKILL.md`,
Step 2b) writes a note to:

```
.claude/sessions/<group>/<timestamp>_<name>.catchup.md
```

containing `git status --short` output and a 1-3 sentence summary of what's
unfinished. The working tree is deliberately left dirty.

Nothing reads this file back. Checked both places that run at session start:

- `scripts/start-git-auto.sh` (the plugin's only `SessionStart` hook, per
  `hooks/hooks.json`) — surfaces two other classes of leftover state
  (`unit-check.json`, `pending-commit.json`) but has no logic that looks for
  `*.catchup.md`.
- The separate session-tracking hook that generates the "Session Context" /
  `session-specific-instructions.md` block
  (`/home/anam/workdir/repositories/claude-plugins/session-start.sh`) — no
  reference to "catchup" anywhere in the file.

Net effect: the note is only ever found if a human (or Claude, if told to)
manually browses `.claude/sessions/<group>/`. A new session with a different
name/aim — which is the common case, since sessions are one-off-named — has
no way to discover it exists.

### Proposed fix

Mirror the existing stale-file pattern in `start-git-auto.sh`: it already
scans for orphaned `unit-check.json` / `pending-commit.json` at
`SessionStart` and prints a `STALE_*` marker to stderr for Claude to act on.
Add an equivalent step:

1. On `SessionStart`, glob `$REPO_ROOT/.claude/sessions/*/*.catchup.md`.
2. For any file **newer than the last commit touching the files it lists**
   (or simply: any file whose listed paths are still dirty in
   `git status --short` — cheaper and avoids clock-skew logic), print a
   `PENDING_CATCHUP: <path>` marker with the file's content (or a
   head -n from it) to stderr.
3. Do **not** auto-delete it — unlike the orphaned-handshake files, a
   catchup note isn't invalidated by being read; only by the listed files
   getting committed. So clear it (or move it to `.catchup.md.done`) at the
   point a subsequent commit actually lands, e.g. from
   `check-unit-complete.sh` or the commit skill, once the files it names are
   no longer dirty.
4. Document the marker in `plugin-working.md` next to the existing
   `STALE_UNIT_CHECK` / `STALE_PENDING_COMMIT` write-up so the three
   "orphaned session artifact" cases stay together.

This keeps the same shape as the two markers that already exist, rather than
introducing a new mechanism.

## Issue 2 — `catchup: true` races the wrapup "Write a catchup note" option

### What happens today

Traced in `automate-git-commands/git-auto/cli.py:623-630` (the daemon
itself, not the plugin):

```python
if catchup:
    logger.info("Catchup enabled. Checking for pending changes...")
    _get_worker_loop().run_until_complete(event_handler.sync_workflow())
    # Reset counters after catchup to start fresh
    event_handler.count = 0
    ...
```

When `git-auto start` runs with `catchup: true` (config default `false`),
it immediately runs the full commit workflow against **whatever is dirty at
that instant**, using a generic auto-generated commit message, before the
file watcher even starts. This is the same mechanism `git-auto stop`'s own
help text points to (`Suggestion: commit with 'git-auto start --catchup'`)
— it's an intentional "absorb pending changes on boot" feature.

The problem: `start-git-auto.sh` runs on every `SessionStart` and starts
`git-auto` with whatever `catchup` value is in `git-auto-config.json`. If a
prior session ended via wrapup's "Write a catchup note" option — which
*by design* leaves the tree dirty so the note has something to describe —
and `catchup: true` is set, the next session's `SessionStart` hook
auto-commits exactly those files, under a throwaway message, before the note
is ever read (and before Issue 1's fix, if implemented, would even get a
chance to surface it). The catchup note is instantly stale: it now describes
files that are already committed under an unrelated message, and any
in-progress/incomplete work it flagged has been silently locked into history.

This is the same category of bug already known and documented for
`catchup` vs `unit_commit` (`development-details.md:116-121`,
`README.md:50-53` — the two features "fight over the same dirty tree").
The wrapup catchup-note interaction is a second, currently-undocumented
instance of the identical root cause: `catchup: true` unconditionally
commits on start with no awareness of *why* the tree is dirty.

### Proposed fix

Two independent, stackable options:

1. **Warn at configure-time** (cheapest, matches precedent): extend the
   existing Step 2.5 guard in `skills/configure/SKILL.md` /
   `commands/configure.md` (currently only warns on `catchup: true` +
   `unit_commit: true`) to also note: "catchup: true will also auto-commit
   any tree left dirty by wrapup's 'Write a catchup note' option, before
   the note can be reviewed." This costs nothing but a doc/prompt change,
   consistent with how the `unit_commit` race was handled.
2. **Make `start-git-auto.sh` catchup-note-aware** (only if Issue 1 is
   fixed first): before launching `git-auto start`, check whether any
   `*.catchup.md` file's listed paths are still dirty; if so and
   `catchup: true` is set in the config, print a warning marker
   (`CATCHUP_NOTE_AT_RISK: <path>`) so Claude can offer to resolve the note
   (commit/discard/keep) *before* starting the daemon, rather than letting
   the daemon silently absorb it on boot.

Recommend (1) alone first — it's a one-line doc/prompt addition with no new
runtime logic, and it's the same fix shape already applied for the
`unit_commit` race. (2) is only worth doing once Issue 1's surfacing
mechanism exists to hook into.

## Summary

| # | Issue | Root cause | Fix effort |
|---|-------|------------|------------|
| 1 | Catchup notes never surfaced to next session | No `SessionStart` code path reads `*.catchup.md`; both relevant hooks checked and confirmed silent on it | Medium — new glob + marker in `start-git-auto.sh`, mirroring existing `STALE_*` pattern |
| 2 | `catchup: true` auto-commits a tree a catchup note was written about | `git-auto start --catchup` unconditionally runs `sync_workflow()` on boot with a generic message, unaware a catchup note exists | Low — Step 2.5 warning text extension (matches existing `unit_commit` precedent); optional follow-up hook check once Issue 1 lands |

Neither issue causes data loss (git history is preserved either way), but
both silently defeat the intent of the "Write a catchup note" wrapup option:
Issue 1 makes the note invisible, Issue 2 makes it inaccurate.
