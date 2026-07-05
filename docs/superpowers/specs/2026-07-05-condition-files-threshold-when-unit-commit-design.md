# Condition files_threshold when unit_commit is true

## Problem

Two commit pathways run in parallel in this plugin:

- **Pathway A** (`git-auto` daemon) — session-blind, fires autonomously when
  `files_threshold` distinct files have changed.
- **Pathway B** (`unit-commit`) — Claude-driven, fires when Claude judges a
  logical unit of work complete, gated by `unit_commit: true`.

`/configure` currently asks for `files_threshold` early in Step 2 and
`unit_commit` last, with `unit_commit` defaulting to `false`. Nothing
conditions `files_threshold` on the `unit_commit` answer, so Pathway A can
still fire mid-unit and race Pathway B's commit — the same class of problem
already solved for `catchup` vs `unit_commit` (Step 2.5's existing warning).

`README.md:112` and `plugin-working.md:134` already gesture at this ("set
files_threshold high, e.g. 999") but no code enforces it, and 999 is high
enough to effectively disable Pathway A altogether — defeating its secondary
purpose as a safety net for edits made outside Claude's own tool calls (which
Pathway B's `PostToolUse` hook never observes).

## Goals

1. Collect `unit_commit` first in the `/configure` flow, defaulting to `true`.
2. When `unit_commit` is true, condition `files_threshold` so Pathway A can't
   race Pathway B, while still acting as a safety net for non-Claude edits.
3. Keep a config file that omits `unit_commit` entirely behaving as enabled,
   matching the new interactive default.
4. Reconcile docs that currently recommend `999`.

## Design

### 1. `/configure` step order and defaults

Both `skills/configure/SKILL.md` and `commands/configure.md` (kept mirrored —
these two have drifted before and are deliberately kept in sync):

- Move the `unit_commit` question to the front of Step 2. Default: **true**.
  Prompt explanation stays the same ("Enable logical-unit-based commits?
  ...").
- `files_threshold` question becomes conditional on the answer just given:
  - `unit_commit: true` → suggested/default **15**. If the user enters a
    value below **10**, explain why (races with Pathway A's autonomous
    commits) and re-prompt — same UX pattern as the existing `squash_threshold`
    "min 4 if enabled" rule.
  - `unit_commit: false` → unchanged: default 3, no floor.
- Step 2.5 (the existing `catchup` + `unit_commit` conflict warning) is
  unaffected in logic, only renumbered to follow the new question order.

### 2. Code-level default fallback

`scripts/check-unit-complete.sh:46`:

```diff
-    print('true' if c.get('unit_commit', False) else 'false')
+    print('true' if c.get('unit_commit', True) else 'false')
```

A config file that omits the `unit_commit` key entirely is now treated as
enabled, matching the new interactive default. Explicit `unit_commit: false`
in a config is still respected — this only changes the fallback for a missing
key.

### 3. Docs reconciliation

- `README.md`:
  - Config table: `unit_commit` default row changes `false` → `true`.
  - Line 112's guidance ("set files_threshold high, e.g. 999") is replaced
    with the new floor/default (10 / 15) and a short rationale: high enough
    to avoid racing Pathway B, low enough to still catch changes made outside
    Claude within a session.
- `plugin-working.md`:
  - Example config's `files_threshold: 999` → `15`.
  - Inline comment at line 134 updated to reference the new floor/default and
    drop the "999" example.

### 4. New regression test

`scripts/test-unit-commit-default-fallback.sh`: write a config fixture that
omits the `unit_commit` key entirely (mirroring the fixture style already
used in `test-cross-repo-unit-check.sh`), make a dirty-tree edit, and assert
`check-unit-complete.sh` still writes `unit-check.json` — i.e., confirms the
missing-key fallback behaves as enabled.

## Out of scope

- No change to `git-auto`'s own defaults (`files_threshold: 3` remains its
  independent, unrelated baseline when `unit_commit` is off).
- No change to `push_threshold` or `squash_threshold` conditioning.
- No scripted test for the `/configure` interactive flow itself — consistent
  with this repo's existing pattern that `AskUserQuestion`-driven flows are
  verified live, not via `test-*.sh` scripts.

## Testing

- New: `scripts/test-unit-commit-default-fallback.sh`.
- Existing `test-*.sh` suite should continue to pass unchanged (no fixture in
  the current suite relies on the old `False` fallback or the old
  `files_threshold` defaults from `/configure`).
