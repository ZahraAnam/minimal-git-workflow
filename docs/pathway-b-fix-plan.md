# Pathway B (unit-commit) — Readiness Findings & Fix Plan

Source: delivery-readiness review of `skills/unit-commit`, `commands/unit-commit.md`,
`scripts/check-unit-complete.sh`, `scripts/watch-pending.sh`, `scripts/handshake.py`,
`scripts/start-git-auto.sh`, `scripts/stop-git-auto.sh`, `skills/status`, and
`skills/configure` / `commands/configure.md`, dated 2026-07-05.

Verdict: Pathway B works end-to-end as documented in `plugin-working.md`. Two
findings are blocking; four are non-blocking gaps worth closing before calling
the pathway fully hardened.

Each finding below has its own branch, created off `main`, so fixes can land
independently.

---

## 1. No secrets-scan guard before commit (blocking)
**Branch:** `fix/unit-commit-secrets-guard`

`git-auto` (Pathway A) scans the working tree for secret-looking files and
aborts *before* `git add` if any are found (`plugin-working.md:31`). Pathway
B's `unit-commit` skill (Step 3a) runs `git add . && git commit` unconditionally
with zero user confirmation — no equivalent check. Since Pathway B is the
fully-autonomous, no-confirmation-gate commit path, this is the highest-risk
asymmetry versus its sibling pathway.

**Fix approach:** add a secret-file scan (mirroring whatever heuristic
git-auto uses, or a reasonable equivalent — filename patterns for `.env`,
`*.pem`, `*.key`, `credentials*`, `secrets*`, etc.) to `check-unit-complete.sh`
or as a guard inside the `unit-commit` skill before `git add .`, aborting the
commit and surfacing the flagged file(s) to the user instead of committing.

---

## 2. Config-default documentation mismatch (blocking)
**Branch:** `docs/reconcile-config-defaults`

`skills/configure/SKILL.md` and `commands/configure.md` both document
`push_threshold` defaulting to 4 and `files_threshold` to 2. `README.md` and
`plugin-working.md` both document 0 and 10 respectively. A user accepting
`/configure`'s defaults gets different auto-push behavior than what the
architecture docs describe.

**Fix approach:** determine the actual intended defaults (cross-check against
git-auto's own default behavior if possible), then align all four docs
(`skills/configure/SKILL.md`, `commands/configure.md`, `README.md`,
`plugin-working.md`) to the same values.

---

## 3. Untested mid-session unit-check staleness sweep
**Branch:** `test/unit-check-mid-session-staleness`

`check-unit-complete.sh`'s 300s TTL sweep (added in PR #6, widening the
original SessionStart-only sweep to mid-session) has no regression test.
Only the SessionStart sweep is covered, by `test-start-git-auto.sh`. A
regression in the mid-session path would currently go uncaught.

**Fix approach:** add a test (e.g. `test-unit-check-staleness.sh`, mirroring
the structure of `test-handshake-staleness.sh`) that writes an aged
`unit-check.json` (timestamp > 300s old) directly in a repo, invokes
`check-unit-complete.sh` via its hook-input stdin contract, and asserts the
stale file is surfaced via `STALE_UNIT_CHECK` and regenerated from current
state rather than left blocking.

---

## 4. Asymmetric cleanup at session end
**Branch:** `fix/stop-git-auto-unit-check-surfacing`

`start-git-auto.sh` surfaces `unit-check.json`'s contents via a
`STALE_UNIT_CHECK` marker before deleting it. `stop-git-auto.sh` deletes the
same file unconditionally and silently, with no equivalent surfacing. Low
practical risk today (wrapup's own `git status --short` check independently
catches any uncommitted files), but it breaks the "never silently lose the
trail" invariant the rest of this codebase holds to.

**Fix approach:** before the `rm -f "$REPO_ROOT/.git/unit-check.json"` in
`stop-git-auto.sh`, read and log its contents (branch/stat_summary/files) the
same way `start-git-auto.sh` does, if the file exists.

---

## 5. `/status` doesn't surface unit-check state
**Branch:** `feat/status-surface-unit-check`

`handshake.py status`'s own output already includes `unit-check.json`
EXISTS/branch/stat_summary (see `handshake.py:295,299-301`), but
`skills/status/SKILL.md` Step 2 only instructs Claude to report
`pending-commit.json`/`commit-message.txt` state. Pathway B state is
invisible in the one command whose job is visibility.

**Fix approach:** add a bullet to `skills/status/SKILL.md` Step 2 (and its
`commands/status.md` twin) instructing Claude to also report whether
`unit-check.json` exists and its `stat_summary`, using the data
`handshake.py status` already prints.

---

## 6. Skill/command message wording drift in unit-commit
**Branch:** `fix/unit-commit-message-drift`

`skills/unit-commit/SKILL.md` and `commands/unit-commit.md` are functionally
identical (both commit with no confirmation gate — the real 2026-07-04 bug is
fixed), but their final user-facing messages in Step 3a/3b still differ in
wording. Cosmetic only, but this codebase has a documented history of
skill/command drift causing real bugs later (the commit-confirmation saga,
the wrapup silent-warn gap) — closing small drifts early is cheap insurance.

**Fix approach:** pick one wording (recommend the skill's, since skills are
the primary invocation path) and make the command file match verbatim, aside
from the required frontmatter difference (`name:` field).

---

## Branch summary

| Priority | Branch | Finding |
|---|---|---|
| Blocking | `fix/unit-commit-secrets-guard` | #1 |
| Blocking | `docs/reconcile-config-defaults` | #2 |
| Gap | `test/unit-check-mid-session-staleness` | #3 |
| Gap | `fix/stop-git-auto-unit-check-surfacing` | #4 |
| Gap | `feat/status-surface-unit-check` | #5 |
| Gap | `fix/unit-commit-message-drift` | #6 |
